# Helm Chart & Ingress Configuration

This document covers the Kubernetes Helm chart for Spring PetClinic. It details the chart structure, Deployment vs Rollout toggle, AWS Application Load Balancer (ALB) Ingress, and autoscaling policies.

---

## 1. Chart Structure

The chart is located in [`helm/petclinic/`](file:///home/devops/Atos/AtosGraduationProject/helm/petclinic/). It packages all Kubernetes manifests for the application:

### 1.1 Architecture & Directory Layout
```text
helm/petclinic/
├── Chart.yaml                     # Chart metadata, API version (v2), and versioning
├── values.yaml                    # Base default values hierarchy
├── templates/
│   ├── _helpers.tpl               # Template helpers, naming macros, and label standards
│   ├── deployment.yaml            # Standard Kubernetes Deployment (used when rollout.enabled = false)
│   ├── rollout.yaml               # Argo Rollout Custom Resource (used when rollout.enabled = true)
│   ├── service.yaml               # ClusterIP Service exposing port 80 (targets pod 8080)
│   ├── ingress.yaml               # AWS Application Load Balancer Ingress definition
│   ├── hpa.yaml                   # HorizontalPodAutoscaler (CPU & Memory utilization)
│   ├── pdb.yaml                   # PodDisruptionBudget (minAvailable: 1)
│   ├── servicemonitor.yaml        # Prometheus Operator ServiceMonitor scrape target
│   ├── analysis-template.yaml     # Argo Rollouts background metric analysis templates
│   ├── prometheus-rules.yaml      # SRE recording rules (burn rates & 30-day compliance)
│   ├── slo-alerts.yaml            # SRE Multi-Window Multi-Burn-Rate alerting rules
│   ├── externalsecret.yaml        # External Secrets Operator synchronization manifest
│   └── db-statefulset.yaml        # In-cluster MySQL StatefulSet with persistent storage
```

### 1.2 Multi-Environment Values Hierarchy
Environment values files stored in [`gitops/workloads/`](file:///home/devops/Atos/AtosGraduationProject/gitops/workloads/) override base defaults:
- `values.yaml` (Chart Defaults): Base images, probe intervals, resource requests, and security contexts.
- `gitops/workloads/dev/values.yaml`: Enables standard `Deployment`, uses low replica counts (`minReplicas: 1`), and disables strict SLO alerts.
- `gitops/workloads/test/values.yaml`: Enables `Rollout` with canary analysis and in-cluster testing configurations.
- `gitops/workloads/prod/values.yaml`: Enables `Rollout` with progressive canary steps, high availability (`minReplicas: 2`, `maxReplicas: 10`), Multi-AZ spread constraints, and production SLO alerting rules (`monitoring.alerts.enabled: true`).

---

## 2. Workload Controller Abstraction (`Deployment` vs. `Rollout`)

To provide flexibility across environments, the chart abstracts the workload controller type using a single boolean flag: `rollout.enabled`.

```mermaid
flowchart TD
    Config{rollout.enabled}
    Config -->|false (dev)| Dep[templates/deployment.yaml<br/>Native Kubernetes Deployment<br/>Standard RollingUpdate]
    Config -->|true (test / prod)| Rol[templates/rollout.yaml<br/>Argo Rollouts Controller<br/>Canary Steps & Automated Analysis]
    
    Dep --> PodSpec[Shared Pod Specification:<br/>Container Image, Probes, Resources,<br/>Environment Variables & Volume Mounts]
    Rol --> PodSpec
```

### 2.1 Mutual Exclusivity Implementation
To prevent both controllers from running simultaneously (which would cause double-scaling and port conflicts), templates evaluate mutual exclusivity conditions:
```yaml
# templates/deployment.yaml
{{- if not .Values.rollout.enabled }}
apiVersion: apps/v1
kind: Deployment
...
{{- end }}

# templates/rollout.yaml
{{- if .Values.rollout.enabled }}
apiVersion: argoproj.io/v1alpha1
kind: Rollout
...
{{- end }}
```

---

## 3. AWS Application Load Balancer (ALB) Ingress Integration

Public ingress traffic is brokered by the **AWS Load Balancer Controller** via the Kubernetes `Ingress` API.

### 3.1 Template Specification (`templates/ingress.yaml`)
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "petclinic.fullname" . }}
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/certificate-arn: {{ .Values.ingress.certificateArn | quote }}
    alb.ingress.kubernetes.io/healthcheck-path: /actuator/health
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: "15"
    alb.ingress.kubernetes.io/healthcheck-timeout-seconds: "5"
    alb.ingress.kubernetes.io/healthy-threshold-count: "2"
    alb.ingress.kubernetes.io/unhealthy-threshold-count: "3"
spec:
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {{ include "petclinic.fullname" . }}
                port:
                  number: 80
```

### 3.2 Key Architectural Decisions
1. **Target Type IP (`target-type: ip`)**:
   - Routes traffic directly from the ALB to the Kubernetes pod IP in the private subnet.
   - **Why this is critical**: Bypasses the Kubernetes `NodePort` layer and `kube-proxy` iptables/IPVS translation. Eliminates double-hop network latency and preserves source IP addresses.
2. **HTTP to HTTPS Redirection (`ssl-redirect: '443'`)**:
   - The AWS ALB automatically returns an HTTP 301 redirect to port 443 for all unencrypted port 80 connections, enforcing TLS in transit.
3. **Actuator Healthcheck Integration**:
   - Target group health checks poll `/actuator/health`. Unhealthy pods are immediately taken out of the ALB target group before Kubernetes terminates them.

---

## 4. High Availability & Fault Tolerance Policies

### 4.1 Pod Disruption Budget (PDB)
Defined in [`templates/pdb.yaml`](file:///home/devops/Atos/AtosGraduationProject/helm/petclinic/templates/pdb.yaml):
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "petclinic.fullname" . }}
spec:
  minAvailable: 1
  selector:
    matchLabels:
      {{- include "petclinic.selectorLabels" . | nindent 6 }}
```
- **Operational Guarantee**: Protects against voluntary disruptions (such as Kubernetes node drains during EKS AMI upgrades or Karpenter node consolidation).
- Kubernetes will block node drain operations if evicting the pod would drop total healthy replicas below 1.

### 4.2 Horizontal Pod Autoscaler (HPA)
Defined in [`templates/hpa.yaml`](file:///home/devops/Atos/AtosGraduationProject/helm/petclinic/templates/hpa.yaml):
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "petclinic.fullname" . }}
spec:
  scaleTargetRef:
    apiVersion: {{ if .Values.rollout.enabled }}argoproj.io/v1alpha1{{ else }}apps/v1{{ end }}
    kind: {{ if .Values.rollout.enabled }}Rollout{{ else }}Deployment{{ end }}
    name: {{ include "petclinic.fullname" . }}
  minReplicas: {{ .Values.autoscaling.minReplicas | default 2 }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas | default 10 }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 80
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
```
- Automatically targets either the `Rollout` or `Deployment` depending on `rollout.enabled`.
- Triggers scale-out when CPU or memory exceeds 80% average utilization across the pod set.

---

## 5. Security & Secrets Integration (`ExternalSecret`)

Application credentials (MySQL passwords and connection strings) are synchronized dynamically from AWS Secrets Manager using the **External Secrets Operator** via EKS Pod Identity.

### 5.1 Specification (`templates/externalsecret.yaml`)
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: petclinic-mysql
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: petclinic-mysql
    creationPolicy: Owner
  dataFrom:
    - extract:
        key: "atos/petclinic/prod/mysql"
```
- The External Secrets Operator queries AWS Secrets Manager using its IAM Pod Identity role (`atos-eks-cluster-external-secrets-role`).
- It automatically creates and updates native Kubernetes `Secret` resources in the workload namespace, keeping sensitive database credentials out of Git.
