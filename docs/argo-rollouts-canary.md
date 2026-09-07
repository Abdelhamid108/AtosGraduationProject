# Progressive Delivery: Argo Rollouts & Canary Analysis

## 1. Overview & Problem Statement

### 1.1 What We Had Before
Historically, our workloads relied on standard Kubernetes `Deployment` resources with a default `RollingUpdate` strategy (`maxSurge: 25%`, `maxUnavailable: 0`).

While rolling updates provide zero downtime at the pod layer, they suffer from a major operational blind spot:

```
+-------------------------------------------------------------------------+
|                  Standard Kubernetes Rolling Update                     |
+-------------------------------------------------------------------------+
|  1. Start new Pod v2                                                    |
|  2. Check Liveness & Readiness Probes (HTTP GET /actuator/health)        |
|  3. If Status == 200 OK: Route traffic & terminate old Pod v1           |
+-------------------------------------------------------------------------+
|  BLIND SPOT: Readiness probe only proves the JVM booted and can respond |
|  to a basic ping. It does NOT prove:                                    |
|   - Real queries aren't throwing 500 errors under real traffic           |
|   - P95/P99 latency hasn't degraded from 50ms to 2000ms                |
|   - Database connections aren't leaking and exhausting HikariCP         |
|  Result: A broken release rolls out to 100% of users before alerts fire |
+-------------------------------------------------------------------------+
```

### 1.2 What Was Added
We introduced **Progressive Delivery** using **Argo Rollouts** paired with automated Prometheus metric evaluations (`AnalysisTemplate`). 

Instead of replacing pods based solely on static readiness probes, deployments now advance through controlled traffic phases. At each step, Argo Rollouts queries live telemetry from Prometheus. If any Service Level Objective (SLO) is violated, the rollout **automatically aborts and rolls back to the previous stable ReplicaSet** without requiring human intervention.

---

## 2. Architectural Decisions

### 2.1 Why Argo Rollouts?
1. **Drop-in Kubernetes Native Extension**: Argo Rollouts is implemented as a Custom Resource Definition (`Rollout`) that shares the exact same `spec.template` schema as standard Kubernetes Deployments. Migration requires zero changes to the underlying application container.
2. **First-Class GitOps Synergy**: Because we use Argo CD for cluster management, Argo Rollouts integrates directly with Argo CD's health checks and sync policies without fighting desired state in Git.
3. **Automated Analysis Provider**: It has native support for querying Prometheus endpoints directly via PromQL, eliminating the need for custom rollout bash scripts or external webhooks.

---

### 2.2 Why Canary Deployment Instead of Blue/Green?

We deliberately selected a **Canary strategy** with incremental traffic weighting over a Blue/Green deployment for three practical reasons:

| Evaluation Criteria | Blue/Green Deployment | Canary Deployment (Our Choice) |
| :--- | :--- | :--- |
| **Compute / FinOps Cost** | **200% Capacity Required**<br>Must spin up a complete, identical duplicate replica set alongside the active environment. Triggers Karpenter worker node scaling and inflates AWS infrastructure costs. | **Minimal Overhead (~10-20%)**<br>Only runs a fraction of new pods during the verification phase. Remains within existing cluster capacity without unnecessary autoscaler churn. |
| **Blast Radius & SLA Protection** | **All-or-Nothing Exposure**<br>100% of live traffic is shifted instantaneously. If a subtle bug exists (e.g. database deadlocks, connection leaks), all users are affected at once, burning the SLA error budget immediately. | **Strictly Contained (10% Traffic)**<br>Only 10% of users touch the new version while metrics are evaluated. If an issue occurs, 90% of user traffic remains completely unaffected on the stable version. |
| **Stateful Database Interaction** | High risk of locking or connection contention if two full application fleets execute heavy read/write operations simultaneously against the MySQL instance. | Canary traffic gently introduces new queries, allowing HikariCP saturation and latency to be measured safely under low concurrency. |

---

### 2.3 Traffic Routing via AWS Application Load Balancer (ALB)

Standard replica-based canaries rely on pod ratios (e.g. 1 canary pod out of 3 total pods = 33% traffic), which makes low percentages like 10% impossible on small replica counts.

To achieve exact percentage splits regardless of pod count, we integrated Argo Rollouts directly with the **AWS Load Balancer Controller**:
1. **Dual Services**: Helm provisions both `petclinic-prod` (stable) and `petclinic-prod-canary` (canary).
2. **Ingress Annotation Manipulation**: Argo Rollouts dynamically updates the `alb.ingress.kubernetes.io/actions.<service>` annotation on the Ingress resource.
3. **Target Group Weighting**: The AWS ALB adjusts the weighted forward rules at the AWS cloud layer (e.g. 90% stable target group, 10% canary target group), guaranteeing precise traffic shaping.

---

## 3. Metric Selection Rationale

In automated canary analysis, **alert fatigue and false rollbacks are the primary enemy**. A canary template should not query every metric that exists; it must query only deterministic, high-signal metrics that represent the **Google SRE 4 Golden Signals**.

Our `AnalysisTemplate` is intentionally scoped to **4 essential metrics**:

```
+------------------------------------------------------------------------------------+
|                         CANARY ANALYSIS EVALUATION GATE                            |
+--------------------+--------------------+--------------------+---------------------+
| 1. Error Rate      | 2. P95 Latency     | 3. P99 Latency     | 4. DB Saturation    |
| (Availability)     | (User Experience)  | (Tail Spikes)      | (Resource Exhaustion|
+--------------------+--------------------+--------------------+---------------------+
```

### 3.1 Metric Breakdown

#### 1. Availability SLO (`error-rate`)
- **Signal**: Errors / Traffic.
- **PromQL**:
  ```promql
  (
    sum(rate(http_server_requests_seconds_count{status=~"5..", application="petclinic"}[2m]))
    /
    sum(rate(http_server_requests_seconds_count{application="petclinic"}[2m]))
  ) OR on() vector(0)
  ```
- **Threshold**: `result[0] <= 0.001` (≤ 0.1% errors).
- **Rationale**: Directly protects our 99.9% uptime SLA. The `OR on() vector(0)` operator ensures that during cold starts or off-peak hours with zero 5xx errors, Prometheus yields `0` instead of an empty vector, preventing false analysis failures.

#### 2. Standard Latency SLO (`p95-latency`)
- **Signal**: Latency.
- **PromQL**:
  ```promql
  histogram_quantile(0.95,
    sum(rate(http_server_requests_seconds_bucket{application="petclinic"}[2m])) by (le)
  )
  ```
- **Threshold**: `result[0] <= 0.5` (≤ 500ms).
- **Rationale**: Measures the experience of the majority of users. Supported out of the box by PetClinic's configuration:
  `management.metrics.distribution.percentiles-histogram.http.server.requests=true`.

#### 3. Tail Latency SLO (`p99-latency`)
- **Signal**: Latency.
- **PromQL**:
  ```promql
  histogram_quantile(0.99,
    sum(rate(http_server_requests_seconds_bucket{application="petclinic"}[2m])) by (le)
  )
  ```
- **Threshold**: `result[0] <= 1.0` (≤ 1000ms).
- **Rationale**: P95 smooths out micro-outages. P99 isolates single-query regressions such as unindexed database lookups, N+1 JPA relations, or thread contention before they cascade.

#### 4. Database Connection Pool Saturation (`db-pool-saturation`)
- **Signal**: Saturation.
- **PromQL**:
  ```promql
  (
    sum(hikaricp_connections_active{application="petclinic"})
    /
    sum(hikaricp_connections_max{application="petclinic"})
  ) OR on() vector(0)
  ```
- **Threshold**: `result[0] <= 0.8` (≤ 80% pool utilization).
- **Rationale**: The number one cause of silent failures in Spring Boot applications is database connection starvation. If a new release fails to close connections or executes long-running transactions, the pool saturates. Catching this at 80% stops the rollout before requests queue and crash the service.

---

### 3.2 Metrics Intentionally Omitted & Why

During design review, several candidate metrics were analyzed and rejected to prevent false positives:

1. **Specific Controller Metrics (e.g. `/owners` or `/vets`)**:
   - *Why omitted*: In Spring PetClinic, all sub-controllers (including visits and pets) nest under `/owners` or top-level endpoints. Metric #1 (`error-rate`) already aggregates all endpoints globally. Adding separate controller gates creates duplicate failure alerts without adding new diagnostic information.
2. **JVM Heap Saturation (`jvm_memory_used_bytes / max`)**:
   - *Why omitted*: Java's Garbage Collector does not immediately reclaim memory; it routinely allows heap usage to float between 70% and 85% before triggering a major sweep. Killing a release based on momentary heap levels leads to false rollbacks on healthy Java processes. Kubernetes pod memory limits and cgroup OOM handlers guard this more reliably.
3. **HikariCP Acquire Latency Histograms**:
   - *Why omitted*: Spring Boot Actuator does not export `_bucket` histograms for connection acquisition by default. Querying a non-existent metric would return empty results and disrupt automated verification.

---

## 4. Operational Lifecycle & Analysis Mechanics

### 4.1 Evaluation Cadence
- **Interval**: 30 seconds between metric scrapes.
- **Count**: 5 successful consecutive checks (2.5 minutes total analysis window per step).
- **Failure Limit**: 2 failed checks allowed before triggering an automated abort.
  - *Tolerance Rationale*: A single transient network hiccup or scrape timeout should not abort a release. Requiring 2 failures eliminates false positives while keeping the response time under 60 seconds during genuine degradation.

### 4.2 Traffic Step Progression
```
[Start Deploy]
      |
      v
[Step 1: 10% Canary Traffic] ----> (Run Prometheus Analysis: 2.5 min)
      |                                      |
      | Pass                                 | Fail (Violates SLO)
      v                                      v
[Step 2: 25% Traffic]                 [AUTOMATIC ROLLBACK]
      |                               - Traffic set back to 0%
      | Pass                          - Canary pods terminated
      v                               - Stable v1 pods untouched
[Step 3: 50% Traffic]                 - Alert logged to Argo CD
      |
      | Pass
      v
[Step 4: 100% Full Promotion]
```

---

## 5. Verification & Troubleshooting

### Check Rollout Status via CLI
```bash
# View live interactive progression and analysis run
kubectl argo rollouts get rollout petclinic-prod -n petclinic-prod --watch

# View active and past analysis runs
kubectl get analysistrun -n petclinic-prod

# Manually abort or retry a stuck rollout if needed
kubectl argo rollouts abort petclinic-prod -n petclinic-prod
kubectl argo rollouts retry petclinic-prod -n petclinic-prod
```
