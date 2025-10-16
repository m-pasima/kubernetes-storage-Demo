#!/usr/bin/env bash
set -euo pipefail

# Cleanup script for DevOps Academy storage demos on EKS (EBS/EFS)
# - Deletes ALB Ingress(es), app Deployments/Services, PVCs, and demo StorageClasses
# - Cleans up both App 1 (devops-academy-nginx) and App 2 (devops-academy-nginx-2)
# - Also removes EFS dynamic provisioner stack (namespace 'storage') if present
# - Attempts to clean up earlier static demo resources (manual PV/PVC/SC)
# Usage: ./scripts/cleanup-eks-storage.sh [namespace]

NS=${1:-default}

ts() { date +%H:%M:%S; }
log() { echo "[$(ts)] $*"; }

log "Deleting ALB Ingress (devops-academy-alb) in ns '$NS'"
kubectl delete ingress devops-academy-alb -n "$NS" --ignore-not-found=true --wait=true || true

log "Deleting nginx Ingress (devops-academy-ingress) in ns '$NS' if present"
kubectl delete ingress devops-academy-ingress -n "$NS" --ignore-not-found=true --wait=true || true

log "Deleting ALB Ingress for App 2 (devops-academy-alb-2) in ns '$NS'"
kubectl delete ingress devops-academy-alb-2 -n "$NS" --ignore-not-found=true --wait=true || true

log "Deleting Deployment/Service with label app=devops-academy in ns '$NS'"
kubectl delete deployment,service -l app=devops-academy -n "$NS" --ignore-not-found=true || true
kubectl wait --for=delete deployment/devops-academy-nginx -n "$NS" --timeout=120s || true

log "Deleting Deployment/Service with label app=devops-academy-2 in ns '$NS'"
kubectl delete deployment,service -l app=devops-academy-2 -n "$NS" --ignore-not-found=true || true
kubectl wait --for=delete deployment/devops-academy-nginx-2 -n "$NS" --timeout=120s || true

log "Deleting PVC pvc-gp3 in ns '$NS'"
kubectl delete pvc pvc-gp3 -n "$NS" --ignore-not-found=true || true
kubectl wait --for=delete pvc/pvc-gp3 -n "$NS" --timeout=180s || true

# If a PV still references pvc-gp3, wait for it to delete (dynamic EBS path)
PV_NAME=$(kubectl get pv -o jsonpath='{range .items[?(@.spec.claimRef.name=="pvc-gp3")]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
if [[ -n "${PV_NAME:-}" ]]; then
  log "Waiting for PV '$PV_NAME' to delete"
  kubectl wait --for=delete pv/"$PV_NAME" --timeout=180s || true
fi

log "Deleting PVC test-claim (EFS demo) in ns '$NS'"
kubectl delete pvc test-claim -n "$NS" --ignore-not-found=true || true
kubectl wait --for=delete pvc/test-claim -n "$NS" --timeout=180s || true

# If a PV still references test-claim, wait for it to delete (dynamic EFS path)
PV_NAME=$(kubectl get pv -o jsonpath='{range .items[?(@.spec.claimRef.name=="test-claim")]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
if [[ -n "${PV_NAME:-}" ]]; then
  log "Waiting for PV '$PV_NAME' to delete"
  kubectl wait --for=delete pv/"$PV_NAME" --timeout=180s || true
fi

log "Deleting StorageClass gp3 if unused"
kubectl delete storageclass gp3 --ignore-not-found=true || true

log "Deleting StorageClass efs if unused"
kubectl delete storageclass efs --ignore-not-found=true || true

log "Cleaning up static demo resources (if present)"
kubectl delete pvc pvc-test -n "$NS" --ignore-not-found=true || true
kubectl delete pv test-pv-volume --ignore-not-found=true || true
kubectl delete storageclass manual --ignore-not-found=true || true

log "Cleaning up EFS provisioner stack (namespace 'storage') if present"
kubectl delete deployment nfs-client-provisioner -n storage --ignore-not-found=true --wait=true || true
kubectl delete serviceaccount nfs-client-provisioner -n storage --ignore-not-found=true || true
kubectl delete role leader-locking-nfs-client-provisioner -n storage --ignore-not-found=true || true
kubectl delete rolebinding leader-locking-nfs-client-provisioner -n storage --ignore-not-found=true || true
kubectl delete clusterrole nfs-client-provisioner-runner --ignore-not-found=true || true
kubectl delete clusterrolebinding nfs-client-provisioner --ignore-not-found=true || true

# Attempt to delete the 'storage' namespace if empty
kubectl delete namespace storage --ignore-not-found=true || true

log "Done. Remaining objects in ns '$NS':"
kubectl get deploy,svc,ing,pvc -n "$NS" || true
log "Cluster PVs:"
kubectl get pv || true
