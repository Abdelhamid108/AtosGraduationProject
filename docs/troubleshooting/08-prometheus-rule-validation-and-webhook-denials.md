# Runbook 08: PrometheusRule Validation & Admission Webhook Denials

## 1. Problem Description
When applying Helm templates or syncing Argo CD applications containing `PrometheusRule` custom resources, the deployment fails with:
```text
admission webhook "prometheusrulemutate.monitoring.coreos.com" denied the request: Rules are not valid
```

---

## 2. Why This Happens

The Prometheus Operator runs an admission webhook (`prometheus-operator-admission-webhook`) that parses every `PrometheusRule` resource using an internal PromQL engine before allowing it into etcd. 

If a PromQL expression has invalid syntax, malformed regex, missing durations, or illegal vector matching, the webhook rejects the entire manifest with HTTP 400.

---

## 3. Common Validation Errors & Examples

### 1. Missing Time Range on `rate()` or `increase()`
- **Invalid**: `rate(http_server_requests_seconds_count)`
- **Fix**: `rate(http_server_requests_seconds_count[5m])`
- **Rule**: Functions like `rate()`, `increase()`, and `irate()` require a range vector (a duration in brackets like `[1m]`, `[5m]`, `[1h]`).

### 2. Invalid Regex Quotes in Helm Templates
- **Invalid**: `status!~404|400`
- **Fix**: `status!~"404|400"`
- **Rule**: Prometheus label matchers with regex (`=~` or `!~`) must be enclosed in double quotes.

### 3. Alert Rule Without Comparison Operator
- **Invalid**:
  ```yaml
  alert: HighRequestRate
  expr: rate(http_requests_total[5m])
  ```
- **Fix**:
  ```yaml
  alert: HighRequestRate
  expr: rate(http_requests_total[5m]) > 100
  ```
- **Rule**: An alerting rule (`alert: ...`) must evaluate to a boolean comparison (`>`, `<`, `==`, `!=`). A recording rule (`record: ...`) does not require a comparison.

### 4. Invalid `for` Duration
- **Invalid**: `for: 0` or `for: "none"`
- **Fix**: `for: 1m` or `for: 0s`
- **Rule**: The `for` field requires a valid Go duration string (`30s`, `2m`, `1h`).

---

## 4. How to Inspect Webhook Rejections

### Step 1: Check Prometheus Operator Logs
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-operator --tail=100 | grep -i "rule"
```
The operator prints the exact rule name and character offset that failed parsing:
```text
{"level":"error","error":"could not parse expression: 1:45: parse error: unexpected character: '\\'"}
```

### Step 2: Validate the Rendered YAML Locally
Before committing to Git, render the Helm template and test it:
```bash
helm template petclinic ./helm/petclinic -s templates/prometheus-rules.yaml | kubectl apply --dry-run=server -f -
```
If the webhook accepts it, you will see `prometheusrule.monitoring.coreos.com/... configured (server dry run)`.
