
# 🧪 EFS Test Guide (Kubernetes / EKS)

This guide validates an **Amazon EFS** PersistentVolumeClaim mounted **ReadWriteMany (RWX)** across multiple Pods. It uses the manifests already in this repo:

```

.
|-- clusterrole.yaml
|-- clusterrolebinding.yaml
|-- deployment.yaml
|-- namespace.yaml
|-- role.yaml
|-- rolebinding.yaml
|-- serviceaccount.yaml
|-- storageclass.yaml
`-- test
    `-- test-pvc.yaml

````

## What you’ll do

1. Create or confirm a test namespace and RBAC/SA for EFS access.
2. Install (or confirm) the **EFS StorageClass** (`storageclass.yaml`).
3. Create a **PVC** (`test/test-pvc.yaml`).
4. Deploy an **NGINX** workload (`deployment.yaml`) that mounts the PVC (with/without `subPath`).
5. Prove RWX multi-attach by writing from one Pod and reading from another.
6. Debug common pitfalls if anything doesn’t look right.
7. Optional cleanup.

---

## 0) Prerequisites

- A working Kubernetes cluster (EKS recommended) and `kubectl` configured.
- An **EFS File System** with mount targets in the same VPC/subnets as your worker nodes.
- The **AWS EFS CSI Driver** should be installed. (If not, install via Helm; not covered here.)
- Your `storageclass.yaml` points to the right `provisioner` and **EFS FileSystemId** (if using dynamic access points).

> **Note**: Open `storageclass.yaml` and check:
> - `provisioner: efs.csi.aws.com`
> - Any `parameters.fileSystemId: fs-xxxxxxxx` you expect
> - `volumeBindingMode` and `reclaimPolicy` values that match your intent (e.g., `Retain` for labs)

---

## 1) Create Namespace, ServiceAccount, and RBAC

> **Tip**: Inspect `namespace.yaml` to find the exact namespace name. The examples below assume it’s called `staging`. If yours is different, adjust the `-n` flags accordingly.

```bash
kubectl apply -f namespace.yaml
kubectl apply -f serviceaccount.yaml
kubectl apply -f role.yaml
kubectl apply -f rolebinding.yaml
kubectl apply -f clusterrole.yaml
kubectl apply -f clusterrolebinding.yaml

# Confirm
kubectl get sa,role,rolebinding -n staging
kubectl get clusterrole,clusterrolebinding | grep -i efs -n || true
````

---

## 2) Create the StorageClass

```bash
kubectl apply -f storageclass.yaml

# Verify
kubectl get storageclass
kubectl describe storageclass <your-sc-name>
```

Confirm the `provisioner` is `efs.csi.aws.com`. If it’s a custom name (e.g., `efs-storage`), make sure that’s **actually** the driver deployed in your cluster.

---

## 3) Create the PVC

Your PVC manifest lives at `test/test-pvc.yaml`. Open it and verify:

* `metadata.namespace` matches your namespace (e.g., `staging`)
* `accessModes: [ReadWriteMany]`
* `storageClassName` points to the SC you created above

```bash
kubectl apply -f test/test-pvc.yaml

# Verify
kubectl get pvc -n staging
kubectl describe pvc -n staging <pvc-name>
```

You should see `STATUS: Bound`. If it’s stuck in `Pending`, skip to the **Debug** section.

---

## 4) Deploy Workload(s)

Your `deployment.yaml` should mount the **same PVC** created above. If you want to test **both** shared-root and isolated paths, you can:

* Use **one Deployment** with `replicas: 2` (both mount the PVC root, no `subPath`)
* Or **two Deployments**: one with root mount (no `subPath`), and another using a `subPath: app2` to show isolation

Apply your deployment(s):

```bash
kubectl apply -f deployment.yaml
kubectl -n staging rollout status deploy/<your-deployment-name>
kubectl -n staging get pods -o wide
```

If you have two Deployments (e.g., `devops-academy-nginx` and `devops-academy-nginx-2`), verify both are **Running**.

---

## 5) Validate EFS Multi-Attach and Sync

### 5.1 Confirm the mounts inside each Pod

```bash
# Example pod names — swap for your actual ones
POD_A=$(kubectl -n staging get pod -l app=devops-academy -o jsonpath='{.items[0].metadata.name}')
POD_B=$(kubectl -n staging get pod -l app=devops-academy-2 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

kubectl -n staging exec -it "$POD_A" -- sh -lc 'mount | grep -E "/usr/share/nginx/html|nfs4"'
[ -n "$POD_B" ] && kubectl -n staging exec -it "$POD_B" -- sh -lc 'mount | grep -E "/usr/share/nginx/html|nfs4"' || true
```

You should see an **NFSv4** mount at `/usr/share/nginx/html`.

### 5.2 Write a marker file and read it from another Pod

If both Pods mount the **PVC root (no subPath)**:

```bash
kubectl -n staging exec -it "$POD_A" -- sh -lc 'echo "hello from A $(date)" > /usr/share/nginx/html/marker.txt && ls -l /usr/share/nginx/html/marker.txt'
kubectl -n staging exec -it "$POD_B" -- sh -lc 'ls -l /usr/share/nginx/html/marker.txt && cat /usr/share/nginx/html/marker.txt'
```

If **Pod B** uses `subPath: app2`, the file written at the root won’t appear in B’s docroot. Instead:

```bash
# Write in B's subPath (app2/)
kubectl -n staging exec -it "$POD_B" -- sh -lc 'echo "hello from B $(date)" > /usr/share/nginx/html/app2.txt && ls -l /usr/share/nginx/html/app2.txt'

# From A (root mount), read the file under /app2/
kubectl -n staging exec -it "$POD_A" -- sh -lc 'ls -l /usr/share/nginx/html/app2/ && cat /usr/share/nginx/html/app2/app2.txt'
```

### 5.3 Prove persistence across restarts

```bash
# Scale down and up
kubectl -n staging scale deploy/<YOUR_DEPLOYMENT> --replicas=0
kubectl -n staging rollout status deploy/<YOUR_DEPLOYMENT>
kubectl -n staging scale deploy/<YOUR_DEPLOYMENT> --replicas=1
kubectl -n staging rollout status deploy/<YOUR_DEPLOYMENT>

# Re-check the marker file
NEW_POD=$(kubectl -n staging get pod -l app=<YOUR-APP-LABEL> -o jsonpath='{.items[0].metadata.name}')
kubectl -n staging exec -it "$NEW_POD" -- sh -lc 'cat /usr/share/nginx/html/marker.txt || ls -l /usr/share/nginx/html/app2/app2.txt || true'
```

---

## 6) Debugging (common issues)

**PVC stuck `Pending`**

* `kubectl describe pvc -n staging <name>` → look for events: “waiting for a volume to be created”
* Ensure **EFS CSI Controller/Node** Pods are healthy:

  ```bash
  kubectl get pods -n kube-system -l app=efs-csi-controller
  kubectl get ds -n kube-system | grep efs
  ```
* Your `storageclass.yaml` `provisioner` must match the installed driver (usually `efs.csi.aws.com`).
* EFS mount targets’ Security Groups must allow **NFS (TCP/2049)** from worker node SGs.

**Pods Running but data not “synchronising”**

* The two Pods might be writing to **different paths**:

  * Compare `mountPath` and `subPath` in each Pod (`kubectl get pod -o jsonpath='{.spec.containers[*].volumeMounts}'`).
  * If one uses `subPath: app2` and the other doesn’t, they won’t see the same files unless you look under `/app2/` from the root-mounted Pod.
* Using a **minimal/distroless image**? There might be no shell.

  * Use an **ephemeral debug** session:

    ```bash
    kubectl debug -it -n staging <pod> --image=busybox:1.36 --target=<container-name> -- sh
    ```
* **Permissions** on EFS:

  * Add a Pod `securityContext` with `fsGroup: 101` (nginx Alpine’s group) and `fsGroupChangePolicy: OnRootMismatch`.
  * Or `chmod 0775` the mounted directory in an `initContainer`.

**Content disappears after mounting**

* Mounting a volume over `/usr/share/nginx/html` hides the image’s baked-in files at that path.
* To seed content, use an **initContainer** that writes into the mounted path if empty (check for a sentinel file like `.bootstrapped`).

**Verifying the actual mount**

```bash
kubectl -n staging exec -it "$POD_A" -- sh -lc 'df -hT | grep -E "nfs|html"'
kubectl -n staging exec -it "$POD_A" -- sh -lc 'stat -f -c %T /usr/share/nginx/html || true'
```

You should see an NFS filesystem type.

---

## 7) Operational Tips

* Keep `subPath` usage **consistent** across Pods if they should share the same directory.
* If your learning goal is “same content everywhere”, **do not** set `subPath` at all.
* If your goal is **isolation on the same PVC**, set the **same `subPath` value** for all Pods that should share that isolated folder.
* Prefer a **single Deployment with replicas** for identical behavior across Pods.

---

## 8) Cleanup

```bash
# Remove app(s)
kubectl delete -f deployment.yaml

# Remove PVC (only if you no longer need data)
kubectl delete -f test/test-pvc.yaml

# Optionally remove the StorageClass and RBAC
kubectl delete -f storageclass.yaml
kubectl delete -f rolebinding.yaml -f role.yaml -f clusterrolebinding.yaml -f clusterrole.yaml
kubectl delete -f serviceaccount.yaml

# Remove namespace last (if it was created only for this test)
kubectl delete -f namespace.yaml
```

> **Heads-up**: If your `StorageClass.reclaimPolicy` is `Retain`, deleting the PVC leaves the backing EFS directory (and data) in place. That’s usually what you want for labs.

---

## 9) Appendix: Quick Commands

```bash
# Pods and events
kubectl get pods -n staging -o wide
kubectl describe pod -n staging <pod>

# PVC/PV details
kubectl get pvc -n staging
kubectl describe pvc -n staging <pvc>
kubectl get pv | grep -i efs

# Check mounts inside pods
kubectl exec -it -n staging <pod> -- sh -lc 'mount | grep nginx/html'
kubectl exec -it -n staging <pod> -- sh -lc 'ls -la /usr/share/nginx/html'

# One-liner marker test (root mount)
kubectl -n staging exec -it <podA> -- sh -lc 'echo "hi $(date)" > /usr/share/nginx/html/marker.txt'
kubectl -n staging exec -it <podB> -- sh -lc 'cat /usr/share/nginx/html/marker.txt || true'
```

Happy testing! If you want me to align `deployment.yaml` to either **shared root** or **isolated subPath** patterns, drop the file here and I’ll adjust it line-by-line.


