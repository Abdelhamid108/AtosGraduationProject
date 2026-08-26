# SRE & Observability Specification: Spring PetClinic

## 1. Executive Summary

This document establishes the **Site Reliability Engineering (SRE)** and **Observability** architecture for the **Spring PetClinic** application.

Observability is the capability to infer the internal states of a system based on its external outputs (telemetry). By combining **Spring Boot Actuator**, **Micrometer**, and **Prometheus**, this application exposes production-grade metrics that enable automated health checks, SLO tracking, real-time alerting, and capacity planning.

---

## 2. Core Concepts & Architecture

### 2.1 The 4 Golden Signals of SRE

According to Google SRE principles, monitoring focuses on four primary signals:

1. **Latency**: Time taken to service a request (measured in percentiles: p50, p95, p99).
2. **Traffic**: Demand placed on the service (measured in HTTP requests per second or business transaction rates).
3. **Errors**: Rate of failed requests (HTTP 5xx server errors, exceptions).
4. **Saturation**: Degree of resource utilization (JVM Heap, DB connection pool, CPU).

```
+-----------------------------------------------------------------------+
|                         THE 4 GOLDEN SIGNALS                          |
+-------------------+-------------------+---------------+---------------+
|      Latency      |      Traffic      |     Errors    |   Saturation  |
| (p50, p95, p99)   |   (Requests/sec)  |  (HTTP 5xx)   | (JVM Heap/DB) |
+-------------------+-------------------+---------------+---------------+
```

---

### 2.2 End-to-End Prometheus Telemetry Pipeline

Prometheus relies on a **pull-based scraping architecture**:

```
+-------------------------------------------------------------+
|               Spring Boot App (PetClinic)                   |
|                                                             |
|   +-----------------------+     +-----------------------+   |
|   |  Controllers/Services | --> |   Micrometer Engine   |   |
|   +-----------------------+     +-----------+-----------+   |
|                                             |               |
|                                 +-----------v-----------+   |
|                                 |  /actuator/prometheus |   |
|                                 +-----------+-----------+   |
+---------------------------------------------|---------------+
                                              |
                                HTTP GET Scrape (every 15s)
                                              |
                                 +------------v------------+
                                 |    Prometheus Server    |
                                 +------+------------+-----+
                                        |            |
                         Time-Series DB |            | Alert Rules
                                        |            |
                                 +------v-----+  +---v-------------+
                                 |  Grafana   |  |  Alertmanager   |
                                 | Dashboards |  | (Slack/Email/PD)|
                                 +------------+  +-----------------+
```

1. **Instrumentation**: Business events, JVM runtime, and Web MVC handlers feed metrics into the internal **Micrometer** meter registry.
2. **Exposition**: Actuator exposes the metrics via HTTP endpoint `/actuator/prometheus` formatted in standard OpenMetrics plain text.
3. **Collection**: Prometheus periodically scrapes the endpoint.
4. **Action**: Grafana visualizes the telemetry, and Prometheus Alertmanager evaluates alerting rules against SLO thresholds.

---

## 3. Technology Stack: Spring Boot Actuator vs. Micrometer

| Component | Responsibility |
| :--- | :--- |
| **Spring Boot Actuator** | Manages application lifecycle endpoints (`/actuator/health`, `/actuator/info`, `/actuator/prometheus`). Handles Kubernetes liveness and readiness state evaluation. |
| **Micrometer Core** | Serves as the dimensional metrics facade (the "SLF4J for metrics"). Gathers counters, timers, and gauges with dimensional tags. |
| **`micrometer-registry-prometheus`** | Translates internal Micrometer meters into Prometheus-compatible text representation. |

---

## 4. Telemetry Breakdown

### 4.1 Automatic Technical Telemetry (100% Endpoint Coverage)

Without modifying individual controllers, Spring Boot Actuator and Micrometer automatically measure all web requests across all controllers (`WelcomeController`, `VetController`, `CrashController`, `OwnerController`, `PetController`, `VisitController`).

**Automatically Collected Metrics:**
* `http_server_requests_seconds_count`: Total request count per URI, HTTP method, and status code.
* `http_server_requests_seconds_sum`: Total time spent servicing requests.
* `http_server_requests_seconds_bucket`: Latency distribution histogram buckets.
* `jvm_memory_used_bytes` / `jvm_memory_max_bytes`: JVM Heap & Non-Heap utilization.
* `jvm_gc_pause_seconds_count` / `sum`: Garbage collector pause frequency and duration.
* `hikaricp_connections_active` / `hikaricp_connections_idle`: Database connection pool saturation.

---

### 4.2 Custom Business Metrics (Conversion Funnel Tracking)

Technical metrics confirm that HTTP servers are operational (returning `200 OK`), but they cannot detect silent business workflow bugs (such as validation or UI issues preventing customer actions).

To protect core business flows, dedicated counters are registered in `PetClinicMetricsConfig`:

| Metric Name | Type | Description | Location |
| :--- | :--- | :--- | :--- |
| `petclinic.owners.created.total` | Counter | Total new owner registrations | `OwnerController.processCreationForm()` |
| `petclinic.pets.created.total` | Counter | Total new pets registered | `PetController.processCreationForm()` |
| `petclinic.visits.created.total` | Counter | Total clinic visits booked | `VisitController.processNewVisitForm()` |

---

## 5. Configuration Reference (`application.properties`)

### 5.1 Endpoint Exposure & Probes
```properties
# Expose essential monitoring and diagnostic endpoints
management.endpoints.web.exposure.include=health,info,prometheus,metrics,threaddump,heapdump
management.endpoint.health.show-details=always

# Enable Kubernetes Liveness and Readiness probes
management.endpoint.health.probes.enabled=true
```
* **Liveness Probe** (`/actuator/health/liveness`): Tells Kubernetes whether the container needs a restart.
* **Readiness Probe** (`/actuator/health/readiness`): Tells Kubernetes whether the pod is ready to accept user traffic (checks database connectivity).

### 5.2 Latency Percentiles & SLO Histograms
```properties
management.metrics.export.prometheus.enabled=true
management.metrics.distribution.percentiles-histogram.http.server.requests=true
management.metrics.distribution.percentiles.http.server.requests=0.50,0.90,0.95,0.99
management.metrics.distribution.slo.http.server.requests=50ms,100ms,200ms,500ms,1s
```
* Generates percentile distributions (p50, p90, p95, p99) to detect tail-latency outliers.
* Configures fixed SLO histogram buckets (50ms to 1s) to evaluate Service Level Agreements.

### 5.3 Dimensional Metric Tags
```properties
management.metrics.tags.application=petclinic
management.metrics.tags.environment=${SPRING_PROFILES_ACTIVE:default}
```
* Automatically attaches `application="petclinic"` and `environment="<env>"` tags to every emitted metric for multi-cluster/multi-environment filtering.

### 5.4 High-Cardinality Protection
```properties
management.metrics.web.server.request.max-uri-tags=100
```
* Caps the maximum number of unique URI tag values to prevent unbounded memory growth (metric explosion / Out-Of-Memory errors caused by crawlers or dynamic URLs).

### 5.5 Zero-Downtime Graceful Shutdown
```properties
server.shutdown=graceful
spring.lifecycle.timeout-per-shutdown-phase=30s
```
* When receiving `SIGTERM` from Kubernetes, the application stops accepting new requests and allows active in-flight requests up to 30 seconds to complete gracefully.

---

## 6. SRE PromQL Runbook

| Signal | PromQL Expression | Purpose |
| :--- | :--- | :--- |
| **Traffic (RPS)** | `sum(rate(http_server_requests_seconds_count{application="petclinic"}[1m]))` | Real-time requests per second |
| **Error Rate (%)** | `sum(rate(http_server_requests_seconds_count{status=~"5.."}[1m])) / sum(rate(http_server_requests_seconds_count[1m])) * 100` | Percentage of failing requests |
| **p95 Latency** | `histogram_quantile(0.95, sum(rate(http_server_requests_seconds_bucket[1m])) by (le))` | 95% of users experience latency below this value |
| **p99 Latency** | `histogram_quantile(0.99, sum(rate(http_server_requests_seconds_bucket[1m])) by (le))` | Tail latency for worst 1% of users |
| **JVM Heap Saturation** | `jvm_memory_used_bytes{area="heap"} / jvm_memory_max_bytes{area="heap"} * 100` | JVM Heap usage percentage |
| **Owner Registrations Rate** | `sum(rate(petclinic_owners_created_total[5m]))` | Business KPI: Owner creation rate |
| **Visit Bookings Rate** | `sum(rate(petclinic_visits_created_total[5m]))` | Business KPI: Appointment creation rate |

---

## 7. Next Steps & GitOps Integration Roadmap

1. **Kubernetes Probes (`gitops/base/deployment.yaml`)**:
   * Configure `livenessProbe` pointing to `/actuator/health/liveness`.
   * Configure `readinessProbe` pointing to `/actuator/health/readiness`.
   * Set `terminationGracePeriodSeconds: 30` to match graceful shutdown timeout.
2. **Prometheus Operator `ServiceMonitor`**:
   * Create a `ServiceMonitor` resource to instruct Prometheus Operator to scrape port `8080` at `/actuator/prometheus` every 15 seconds.
3. **Grafana Dashboards**:
   * Provision dashboard JSON covering the 4 Golden Signals and custom business counters.
4. **Alertmanager SLO Rules**:
   * Configure alerting rules for High Error Rate (> 1% over 5m) and High Latency (p95 > 500ms over 5m).
