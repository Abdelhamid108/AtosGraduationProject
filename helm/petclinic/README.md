# petclinic Helm chart

Deploys [Spring PetClinic](https://github.com/spring-projects/spring-petclinic) and a MySQL 8.4 database on Kubernetes.

## Prerequisites

| Tool | Minimum version |
|------|----------------|
| Kubernetes | 1.25 |
| Helm | 3.12 |
| A built PetClinic container image | – |

The chart expects a container image built from `application/Dockerfile`. Build and push it before installing:

```bash
cd application
./mvnw package -DskipTests
docker build -t <your-registry>/spring-petclinic:1.0.0 .
docker push <your-registry>/spring-petclinic:1.0.0
```

## Directory structure

```
petclinic/
├── Chart.yaml
├── values.yaml           # Default values (all environments)
├── values-dev.yaml       # Development overlay
├── values-prod.yaml      # Production overlay (structure only, no secrets)
└── templates/
    ├── _helpers.tpl
    ├── deployment.yaml        # Application Deployment
    ├── service.yaml           # Application ClusterIP Service (port 8080)
    ├── secret.yaml            # MySQL credentials Secret
    ├── db-statefulset.yaml    # MySQL StatefulSet
    ├── db-service.yaml        # MySQL internal ClusterIP Service
    ├── serviceaccount.yaml
    ├── hpa.yaml               # HorizontalPodAutoscaler (disabled by default)
    ├── ingress.yaml           # Ingress (disabled by default)
    ├── httproute.yaml         # Gateway API HTTPRoute (disabled by default)
    ├── NOTES.txt
    └── tests/
        └── test-connection.yaml
```

## Important values

| Value | Default | Description |
|-------|---------|-------------|
| `image.repository` | `spring-petclinic` | Application image (no registry prefix) |
| `image.tag` | chart `appVersion` | Image tag |
| `replicaCount` | `1` | Application replicas |
| `service.port` | `8080` | Application service port |
| `mysql.auth.database` | `petclinic` | Database name |
| `mysql.auth.username` | `petclinic` | Database user |
| `mysql.auth.password` | `changeme` | **Change before production** |
| `mysql.auth.rootPassword` | `changeme-root` | **Change before production** |
| `mysql.auth.existingSecret` | `""` | Use a pre-existing Secret instead of creating one |
| `mysql.storage.size` | `1Gi` | PersistentVolumeClaim size |
| `mysql.storage.storageClass` | `""` | StorageClass (empty = cluster default) |
| `ingress.enabled` | `false` | Enable Ingress |

## Installing the chart

```bash
# From inside the petclinic/ directory
helm install petclinic . \
  --set image.repository=<your-registry>/spring-petclinic \
  --set image.tag=1.0.0 \
  --set mysql.auth.password=<strong-password> \
  --set mysql.auth.rootPassword=<strong-root-password>
```

Install into a dedicated namespace:

```bash
helm install petclinic . \
  --namespace petclinic \
  --create-namespace \
  --set image.repository=<your-registry>/spring-petclinic \
  --set image.tag=1.0.0 \
  --set mysql.auth.password=<strong-password> \
  --set mysql.auth.rootPassword=<strong-root-password>
```

## Upgrading

```bash
helm upgrade petclinic . \
  --set image.repository=<your-registry>/spring-petclinic \
  --set image.tag=<new-tag> \
  --set mysql.auth.password=<same-password>
```

> **Note:** The MySQL Secret has `helm.sh/resource-policy: keep`. Helm will not
> overwrite it on upgrade, so existing credentials survive a chart upgrade. If
> you need to rotate the password, update the Secret manually then restart the
> StatefulSet.

## Supplying environment-specific values

Use the provided overlay files to avoid duplicating templates:

```bash
# Development (lighter resources, Always pull policy)
helm install petclinic . -f values-dev.yaml \
  --set image.repository=<your-registry>/spring-petclinic \
  --set image.tag=latest

# Production (2 replicas, larger storage, Ingress enabled)
helm install petclinic . -f values-prod.yaml \
  --set image.repository=<your-registry>/spring-petclinic \
  --set image.tag=1.0.0 \
  --set mysql.auth.password=<strong-password> \
  --set mysql.auth.rootPassword=<strong-root-password> \
  --set ingress.hosts[0].host=petclinic.yourdomain.com
```

## Supplying database credentials

**Option A – `--set` flags (suitable for CI/CD):**

```bash
helm install petclinic . \
  --set mysql.auth.password=<password> \
  --set mysql.auth.rootPassword=<root-password>
```

**Option B – External Secret (recommended for production):**

Create the Secret before installing the chart, then tell the chart to use it:

```bash
kubectl create secret generic petclinic-mysql \
  --from-literal=mysql-password=<password> \
  --from-literal=mysql-root-password=<root-password>

helm install petclinic . \
  --set mysql.auth.existingSecret=petclinic-mysql
```

## Accessing the application

With the default ClusterIP service, use port-forwarding during development:

```bash
kubectl port-forward svc/petclinic 8080:8080
# Open http://localhost:8080
```

For external access, enable the Ingress and set a hostname:

```bash
helm upgrade petclinic . \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.hosts[0].host=petclinic.yourdomain.com \
  --set ingress.hosts[0].paths[0].path=/ \
  --set ingress.hosts[0].paths[0].pathType=Prefix
```

## Troubleshooting / useful commands

```bash
# Overall status
helm status petclinic

# All pods
kubectl get pods -l app.kubernetes.io/instance=petclinic

# Application logs
kubectl logs deploy/petclinic -f

# MySQL logs
kubectl logs sts/petclinic-mysql -f

# Application health
kubectl exec deploy/petclinic -- wget -qO- http://localhost:8080/actuator/health

# Connect to MySQL
kubectl exec -it sts/petclinic-mysql -- \
  mysql -u petclinic -p petclinic

# Describe a failing pod
kubectl describe pod <pod-name>

# Restart the application (e.g. after a config change)
kubectl rollout restart deploy/petclinic

# Run Helm chart tests
helm test petclinic
```

## Notes

- MySQL data is stored in a PersistentVolumeClaim managed by the StatefulSet's
  `volumeClaimTemplates`. The PVC is **not** deleted when you run `helm uninstall`
  so data survives an accidental uninstall. Delete the PVC manually when you no
  longer need the data.
- The application activates the `mysql` Spring profile automatically, which reads
  `MYSQL_URL`, `MYSQL_USER`, and `MYSQL_PASS` environment variables.
- The application waits for MySQL to accept connections (via an init container)
  before starting. The init container uses `nc` from `busybox:1.36`.
- `terminationGracePeriodSeconds: 60` gives Spring Boot's graceful shutdown
  (30 s timeout) plus extra headroom to finish in-flight requests.
