# Runbook 07: ACM Certificates & ALB HTTPS Redirection

## 1. Problem Description
When deploying or updating Ingress resources using the AWS Load Balancer Controller, the controller may fail with errors such as:
- `Failed deploy model due to CertificateNotFound: Certificate 'arn:aws:acm:...' not found`
- `Failed deploy model due to UnsupportedCertificate: The certificate must have a fully-qualified domain name...`
- Traffic connects on HTTP (port 80) and does not automatically redirect to HTTPS (port 443).

---

## 2. Root Causes

### 1. Certificate Not Found
- The ACM certificate ARN specified in `values.yaml` belongs to a different AWS region (e.g. created in `us-west-2` instead of `us-east-1`).
- The ACM certificate was deleted and recreated in AWS, giving it a new UUID.

### 2. Unsupported Certificate
- The certificate was issued with an empty or malformed domain name, or has not completed DNS validation in AWS ACM.
- The certificate was created in IAM instead of ACM and lacks an RSA 2048-bit or ECDSA P-256 key.

### 3. Missing HTTPS Redirect
- The Ingress is missing the `alb.ingress.kubernetes.io/ssl-redirect: '443'` annotation, causing the ALB to treat port 80 as a regular HTTP listener rather than a redirect rule.

---

## 3. Diagnostic Commands

### Step 1: List Valid ACM Certificates in us-east-1
```bash
aws acm list-certificates --region us-east-1 --certificate-statuses ISSUED --output table
```
Verify:
1. The certificate status is `ISSUED`.
2. The `CertificateArn` matches the ARN in `helm/petclinic/values.yaml` or `gitops/workloads/<env>/values.yaml`.

### Step 2: Check AWS Load Balancer Controller Logs
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=100
```
Search for:
```text
{"level":"error","msg":"Reconciler error","error":"CertificateNotFound"}
```

---

## 4. Resolution Steps

### Step 1: Update the Certificate ARN
In your environment values file (`gitops/workloads/<env>/values.yaml`):
```yaml
ingress:
  enabled: true
  annotations:
    alb.ingress.kubernetes.io/certificate-arn: "arn:aws:acm:us-east-1:069089526123:certificate/<VALID_UUID>"
```

### Step 2: Enforce Automatic HTTP to HTTPS Redirection
Ensure both annotations exist in `helm/petclinic/templates/ingress.yaml`:
```yaml
alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
alb.ingress.kubernetes.io/ssl-redirect: '443'
```

### Step 3: Verify ALB Listeners in AWS
```bash
# Get ALB ARN from Ingress
ALB_ARN=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, 'petclinic')].LoadBalancerArn" --output text)

# List Listeners
aws elbv2 describe-listeners --load-balancer-arn $ALB_ARN
```
Confirm:
- Port 80 listener action type is `redirect` with `Port: 443`, `Protocol: HTTPS`, and `StatusCode: HTTP_301`.
- Port 443 listener action type is `forward` to the target group.
