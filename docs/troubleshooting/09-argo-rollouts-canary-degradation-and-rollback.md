# Runbook 09: Argo Rollouts Canary Degradation & Rollback

## 1. Problem Description
During a progressive canary deployment in `test` or `prod`:
- The rollout status reports `Degraded` or `ProgressDeadlineExceeded`.
- The rollout pauses indefinitely at a specific traffic weight (such as 20% or 40%).
- The automated `AnalysisRun` fails because error rates or latencies exceeded thresholds.

---

## 2. Investigating Rollout State

### Step 1: Check Real-Time Rollout Status
Using the `kubectl-argo-rollouts` plugin or standard `kubectl`:
```bash
# View interactive rollout tree
kubectl argo rollouts get rollout petclinic -n petclinic-prod --watch

# View current status summary
kubectl argo rollouts status rollout petclinic -n petclinic-prod
```

### Step 2: Inspect the Failed AnalysisRun
If the rollout aborted, check the background metric queries:
```bash
# List recent analysis runs
kubectl get analysisruns -n petclinic-prod --sort-by=.metadata.creationTimestamp

# View details and PromQL query result
kubectl describe analysisrun <ANALYSIS_RUN_NAME> -n petclinic-prod
```
Look for:
```text
Status: Failed
Message: Metric "petclinic-success-rate" failed: Value 0.967 < 0.990
```

---

## 3. Operational Actions

### 1. What to Do on Automated Abort
When an analysis run fails, Argo Rollouts **automatically** scales down the canary pods and routes 100% of user traffic back to the stable replica set.
- **Action**: Do not manually alter the traffic routing.
- **Root Cause**: Check pod logs for the failed canary pods:
  ```bash
  kubectl logs -n petclinic-prod -l app=petclinic,rollouts-pod-template-hash=<CANARY_HASH> --tail=100
  ```
- Identify whether the failure was due to application exceptions (HTTP 500), database timeouts, or slow response times.

### 2. Manual Emergency Abort
If you detect an issue during a rollout before the automated analysis fails:
```bash
kubectl argo rollouts abort petclinic -n petclinic-prod
```
This halts progression immediately and shifts all traffic back to the previous stable revision.

### 3. Manual Rollout Promotion (Skip Remaining Pauses)
If verification is complete and you want to bypass the remaining wait times:
```bash
kubectl argo rollouts promote petclinic -n petclinic-prod
```
To promote fully to 100% immediately:
```bash
kubectl argo rollouts promote petclinic -n petclinic-prod --full
```

### 4. Retrying an Aborted Rollout
After fixing the underlying external issue (such as restarting a database):
```bash
kubectl argo rollouts retry rollout petclinic -n petclinic-prod
```

### 5. Reverting to a Specific Previous Revision
To roll back to a known good revision:
```bash
# View revision history
kubectl argo rollouts history rollout petclinic -n petclinic-prod

# Revert to revision 1
kubectl argo rollouts undo rollout petclinic -n petclinic-prod --to-revision=1
```
