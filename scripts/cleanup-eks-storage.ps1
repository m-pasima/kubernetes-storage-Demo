# Cleanup script for DevOps Academy storage demos on EKS (EBS/EFS)
# - Deletes ALB Ingress(es), app Deployments/Services, PVCs, and demo StorageClasses
# - Cleans up both App 1 (devops-academy-nginx) and App 2 (devops-academy-nginx-2)
# - Also removes EFS dynamic provisioner stack (namespace 'storage') if present
# - Attempts to clean up earlier static demo resources (manual PV/PVC/SC)
# Usage: powershell -ExecutionPolicy Bypass -File .\scripts\cleanup-eks-storage.ps1 -Namespace staging

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
    Log "Deleting ALB Ingress for App 2 (devops-academy-alb-2) in ns '$Namespace'"
    kubectl delete ingress devops-academy-alb-2 -n $Namespace --ignore-not-found=true --wait=true | Out-Null
  } catch { }

  try {
    Log "Deleting Deployment/Service with label app=devops-academy in ns '$Namespace'"
    kubectl delete deployment,service -l app=devops-academy -n $Namespace --ignore-not-found=true | Out-Null
    kubectl wait --for=delete deployment/devops-academy-nginx -n $Namespace --timeout=120s | Out-Null
  } catch { }

  try {
    Log "Deleting Deployment/Service with label app=devops-academy-2 in ns '$Namespace'"
    kubectl delete deployment,service -l app=devops-academy-2 -n $Namespace --ignore-not-found=true | Out-Null
    kubectl wait --for=delete deployment/devops-academy-nginx-2 -n $Namespace --timeout=120s | Out-Null
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

  try {
    Log "Deleting PVC test-claim (EFS demo) in ns '$Namespace'"
    kubectl delete pvc test-claim -n $Namespace --ignore-not-found=true | Out-Null
    kubectl wait --for=delete pvc/test-claim -n $Namespace --timeout=180s | Out-Null
  } catch { }

  # If a PV still references test-claim, wait for it to delete (dynamic EFS path)
  try {
    $pvJson = kubectl get pv -o json | ConvertFrom-Json
    $pvName2 = $pvJson.items |
      Where-Object { $_.spec.claimRef -and $_.spec.claimRef.name -eq 'test-claim' } |
      Select-Object -First 1 -ExpandProperty metadata |
      ForEach-Object { $_.name }
    if ($pvName2) {
      Log "Waiting for PV '$pvName2' to delete"
      kubectl wait --for=delete pv/$pvName2 --timeout=180s | Out-Null
    }
  } catch { }

  try {
    Log "Deleting StorageClass efs if unused"
    kubectl delete storageclass efs --ignore-not-found=true | Out-Null
  } catch { }

  Log "Cleaning up static demo resources (if present)"
  try { kubectl delete pvc pvc-test -n $Namespace --ignore-not-found=true | Out-Null } catch { }
  try { kubectl delete pv test-pv-volume --ignore-not-found=true | Out-Null } catch { }
  try { kubectl delete storageclass manual --ignore-not-found=true | Out-Null } catch { }

  Log "Cleaning up EFS provisioner stack (namespace 'storage') if present"
  try { kubectl delete deployment nfs-client-provisioner -n storage --ignore-not-found=true --wait=true | Out-Null } catch { }
  try { kubectl delete serviceaccount nfs-client-provisioner -n storage --ignore-not-found=true | Out-Null } catch { }
  try { kubectl delete role leader-locking-nfs-client-provisioner -n storage --ignore-not-found=true | Out-Null } catch { }
  try { kubectl delete rolebinding leader-locking-nfs-client-provisioner -n storage --ignore-not-found=true | Out-Null } catch { }
  try { kubectl delete clusterrole nfs-client-provisioner-runner --ignore-not-found=true | Out-Null } catch { }
  try { kubectl delete clusterrolebinding nfs-client-provisioner --ignore-not-found=true | Out-Null } catch { }
  try { kubectl delete namespace storage --ignore-not-found=true | Out-Null } catch { }

  Log "Done. Remaining objects in ns '$Namespace':"
  try { kubectl get deploy,svc,ing,pvc -n $Namespace } catch { }
  Log "Cluster PVs:"
  try { kubectl get pv } catch { }
