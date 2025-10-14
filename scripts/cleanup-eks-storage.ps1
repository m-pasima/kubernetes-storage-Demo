# Cleanup script for DevOps Academy NGINX + EBS gp3 on EKS
# - Deletes ALB Ingress, app (Deployment/Service), PVC, and gp3 StorageClass
# - Also attempts to clean up earlier static demo resources (manual PV/PVC/SC)
# Usage: powershell -ExecutionPolicy Bypass -File .\scripts\cleanup-eks-storage.ps1 -Namespace default

param(
  [string]$Namespace = "default"
)

$ErrorActionPreference = "Stop"

function Timestamp {
  return (Get-Date).ToString('HH:mm:ss')
}

function Log([string]$Message) {
  Write-Host "[$(Timestamp)] $Message"
}

try {
  Log "Deleting ALB Ingress (devops-academy-alb) in ns '$Namespace'"
  kubectl delete ingress devops-academy-alb -n $Namespace --ignore-not-found=true --wait=true | Out-Null
} catch { }

try {
  Log "Deleting nginx Ingress (devops-academy-ingress) in ns '$Namespace' if present"
  kubectl delete ingress devops-academy-ingress -n $Namespace --ignore-not-found=true --wait=true | Out-Null
} catch { }

try {
  Log "Deleting Deployment/Service with label app=devops-academy in ns '$Namespace'"
  kubectl delete deployment,service -l app=devops-academy -n $Namespace --ignore-not-found=true | Out-Null
  kubectl wait --for=delete deployment/devops-academy-nginx -n $Namespace --timeout=120s | Out-Null
} catch { }

try {
  Log "Deleting PVC pvc-gp3 in ns '$Namespace'"
  kubectl delete pvc pvc-gp3 -n $Namespace --ignore-not-found=true | Out-Null
  kubectl wait --for=delete pvc/pvc-gp3 -n $Namespace --timeout=180s | Out-Null
} catch { }

# If a PV still references pvc-gp3, wait for it to delete (dynamic EBS path)
try {
  $pvJson = kubectl get pv -o json | ConvertFrom-Json
  $pvName = $pvJson.items |
    Where-Object { $_.spec.claimRef -and $_.spec.claimRef.name -eq 'pvc-gp3' } |
    Select-Object -First 1 -ExpandProperty metadata |
    ForEach-Object { $_.name }
  if ($pvName) {
    Log "Waiting for PV '$pvName' to delete"
    kubectl wait --for=delete pv/$pvName --timeout=180s | Out-Null
  }
} catch { }

try {
  Log "Deleting StorageClass gp3 if unused"
  kubectl delete storageclass gp3 --ignore-not-found=true | Out-Null
} catch { }

Log "Cleaning up static demo resources (if present)"
try { kubectl delete pvc pvc-test -n $Namespace --ignore-not-found=true | Out-Null } catch { }
try { kubectl delete pv test-pv-volume --ignore-not-found=true | Out-Null } catch { }
try { kubectl delete storageclass manual --ignore-not-found=true | Out-Null } catch { }

Log "Done. Remaining objects in ns '$Namespace':"
try { kubectl get deploy,svc,ing,pvc -n $Namespace } catch { }
Log "Cluster PVs:"
try { kubectl get pv } catch { }

