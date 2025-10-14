<p align="center">
  <img alt="Kubernetes" src="https://raw.githubusercontent.com/cncf/artwork/master/projects/kubernetes/horizontal/color/kubernetes-horizontal-color.png" height="60" />
  &nbsp;&nbsp;&nbsp;
  <img alt="AWS" src="https://d1.awsstatic.com/webteam/brand-assets/AWS_logo_RGB.8a1c3337c1b662bde6da3159d6c8ebca126d2b08.png" height="48" />
</p>

# Kubernetes Storage Demo — DevOps Academy

Colorful, sleek NGINX app backed by PersistentVolumes. Learn how pods use PersistentVolumeClaims, how StorageClasses control provisioning, and how to expose the app via Ingress (ALB on EKS). Aimed at anyone learning Kubernetes storage and DevOps Academy students.

## Landing Page Preview
- Local preview: open `docs/index.html` in your browser.
- In cluster: the page is written once by the initContainer into your PVC and served by NGINX at `/`.
- Customize: edit `docs/index.html` and `docs/assets/style.css`; to use those exact files in‑cluster, update the initContainer content accordingly (or copy them into the PVC via `kubectl exec`).

## What You Deploy
- NGINX `Deployment` serving static content from a PVC
- `PersistentVolumeClaim` backed by either:
  - Static hostPath PV (manual provisioning)
  - Dynamic EBS gp3 (EKS via CSI)
- `Service` (ClusterIP) + `Ingress` (AWS Load Balancer Controller / ALB) on EKS

## Repo Layout
- `devops-academy-nginx.yml` — Deployment + Service. Seeds a PVC with a colorful landing page and serves it from NGINX.
- `ingress-alb.yml` — ALB Ingress (EKS) that routes `/` to the Service.
- `gp3-storageclass.yml` — StorageClass for dynamic EBS gp3 (EKS).
- `pvc-gp3.yml` — PVC that requests the `gp3` StorageClass.
- `storageClass.yml` — Static “manual” StorageClass (no provisioner).
- `pv.yml` — Static PersistentVolume (hostPath example).
- `pvc.yml` — Static PersistentVolumeClaim (binds to the static PV).
- `scripts/cleanup-eks-storage.sh|ps1` — Cleanup scripts for Unix/Windows.

## Quickstart on EKS (Dynamic EBS gp3)
Use the EBS CSI driver to provision storage automatically.

1) Apply storage class and claim
```
kubectl apply -f gp3-storageclass.yml
kubectl apply -f pvc-gp3.yml
kubectl get pvc pvc-gp3 -w   # wait for Bound
```

2) Deploy app and ALB ingress
```
kubectl apply -f devops-academy-nginx.yml
kubectl apply -f ingress-alb.yml
```

3) Open the app
```
kubectl get ingress devops-academy-alb
# Copy ADDRESS (ALB DNS) and open http://<ALB-DNS>
```

Cleanup (dynamic path)
```
./scripts/cleanup-eks-storage.sh default
# or on Windows
powershell -ExecutionPolicy Bypass -File .\scripts\cleanup-eks-storage.ps1 -Namespace default
```

## Quickstart (Static hostPath — local/demo)
Manually precreate a PV; the PVC binds to it. Useful for single-node demos.

1) Apply manual class, PV, and PVC
```
kubectl apply -f storageClass.yml -f pv.yml -f pvc.yml
kubectl get pv,pvc
```

2) Point the app to the static PVC name `pvc-test` (one-liner patch)
```
kubectl patch deployment devops-academy-nginx \
  --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/volumes/0/persistentVolumeClaim/claimName","value":"pvc-test"}]'
```

3) Serve (ClusterIP) and use a local Ingress controller, or port-forward
```
kubectl port-forward svc/devops-academy-nginx 8080:80
open http://localhost:8080
```

Note: hostPath is node-local; schedule the pod on the same node or use an Ingress/port-forward that reaches that node. For multi-node or production, use network storage or CSI drivers (EBS/EFS).

## Storage: Pods, PVCs, PVs, and Classes — The Flow
So step by step: pods don’t talk to disks; they mount a PVC. The PVC describes what it needs (size, access mode, volume mode, class). The binder then finds or creates a PV that satisfies the claim. The PV points at real storage — local path, NFS share, or a cloud disk via a CSI driver. Once bound, the pod mounts the PVC and your app reads/writes to the same backend across restarts.

### Manual vs. Dynamic Provisioning
- Manual (static)
  - You precreate the PV (e.g., `pv.yml`) and set `storageClassName: manual` on both PV and PVC.
  - Binding requires a matching class and compatible size/modes.
  - Reclaim policy often `Retain` to avoid data loss; cleanup is manual.
- Dynamic (EBS gp3 on EKS)
  - PVC names `gp3`; the EBS CSI driver creates the EBS volume and PV automatically, in the right AZ.
  - `reclaimPolicy: Delete` cleans up the disk when the PVC is deleted.
  - `allowVolumeExpansion: true` enables resizing by updating the PVC request.

### Key Specs (mapping what matters)
- `spec.resources.requests.storage` (PVC): how much space you need.
- `spec.accessModes` (PVC/PV): RWO/ROX/RWX; EBS supports RWO.
- `spec.volumeMode` (PVC/PV): Filesystem (default) or Block.
- `spec.storageClassName` (PVC/PV): the “how.”
  - `manual` → static PVs (no provisioner).
  - `gp3` → EBS CSI driver provisions gp3 volumes.
- Reclaim policy (PV): Retain vs Delete (Recycle deprecated).

## Troubleshooting
- PVC Pending on EKS
  - Ensure `gp3-storageclass.yml` is applied and the EBS CSI driver is installed.
  - Keep `volumeBindingMode: WaitForFirstConsumer` to align AZs.
- Pod can’t mount hostPath PV
  - It’s node-local; ensure the pod schedules on that node (and the path exists).
- ALB Ingress shows no ADDRESS
  - Confirm AWS Load Balancer Controller is running and has IAM permissions.
- 404s through ALB
  - Check Service selector matches Deployment labels; readiness probe passing.

## Credits & Trademarks
- Kubernetes word mark and logo are trademarks of The Linux Foundation®.
- AWS and the "smile" logo are trademarks of Amazon.com, Inc. or its affiliates.
- This repo is for educational purposes (DevOps Academy). Logos are shown here for identification.
