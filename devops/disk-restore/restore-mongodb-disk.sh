#!/usr/bin/env bash
# restore-mongodb-disk.sh
#
# Clones a GCE disk, creates the static PV/PVC in Kubernetes, and runs a
# one-time fix job (chown + lock removal) so MongoDB can start cleanly.
#
# Run this BEFORE deploying the MongoDB chart (ArgoCD or helmfile).
#
# Usage:
#   ./restore-mongodb-disk.sh <source-disk-link> [target-disk-name] [namespace]
#
# Arguments:
#   source-disk-link   Full GCE disk resource path:
#                      projects/PROJECT/zones/ZONE/disks/DISK_NAME
#   target-disk-name   Name for the new cloned disk (default: <source>-restored)
#   namespace          Kubernetes namespace for MongoDB (default: mongodb)
#
# Example:
#   ./restore-mongodb-disk.sh projects/countly-dev-313620/zones/europe-west1-b/disks/stats-mongodb-data

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <source-disk-link> [target-disk-name] [namespace]"
  echo ""
  echo "  source-disk-link format: projects/PROJECT/zones/ZONE/disks/DISK_NAME"
  exit 1
fi

SOURCE_LINK="$1"

# Parse components from the resource path
PROJECT=$(echo "$SOURCE_LINK"  | sed 's|projects/\([^/]*\)/.*|\1|')
ZONE=$(echo "$SOURCE_LINK"     | sed 's|.*/zones/\([^/]*\)/.*|\1|')
SOURCE_DISK=$(echo "$SOURCE_LINK" | sed 's|.*/disks/\([^/]*\)|\1|')

TARGET_DISK="${2:-${SOURCE_DISK}-restored}"
NAMESPACE="${3:-mongodb}"

PV_NAME="${TARGET_DISK}-pv"
PVC_NAME="data-volume-countly-mongodb-0"
JOB_NAME="mongodb-fix-disk-permissions"

# Get disk size from source disk and convert GB → Gi
SIZE_GB=$(gcloud compute disks describe "${SOURCE_DISK}" \
  --zone="${ZONE}" --project="${PROJECT}" \
  --format="value(sizeGb)")
DISK_SIZE="${SIZE_GB}Gi"

echo "=================================================="
echo " MongoDB Disk Restore"
echo "=================================================="
echo " Source disk  : ${SOURCE_LINK}"
echo " Target disk  : ${TARGET_DISK} (${DISK_SIZE}, ${ZONE})"
echo " PV           : ${PV_NAME}"
echo " PVC          : ${PVC_NAME} (namespace: ${NAMESPACE})"
echo "=================================================="
echo ""

# --------------------------------------------------------------------------- #
# Step 1 — Clone GCE disk
# --------------------------------------------------------------------------- #
echo "[1/5] Cloning GCE disk..."

if gcloud compute disks describe "${TARGET_DISK}" --zone="${ZONE}" --project="${PROJECT}" &>/dev/null; then
  echo "      Disk '${TARGET_DISK}' already exists, skipping clone."
else
  gcloud compute disks create "${TARGET_DISK}" \
    --source-disk="${SOURCE_DISK}" \
    --source-disk-zone="${ZONE}" \
    --zone="${ZONE}" \
    --project="${PROJECT}"
  echo "      Disk cloned."
fi

# --------------------------------------------------------------------------- #
# Step 2 — Apply static PV
# --------------------------------------------------------------------------- #
echo "[2/5] Applying PersistentVolume..."

kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${PV_NAME}
spec:
  capacity:
    storage: ${DISK_SIZE}
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  claimRef:
    namespace: ${NAMESPACE}
    name: ${PVC_NAME}
  csi:
    driver: pd.csi.storage.gke.io
    volumeHandle: projects/${PROJECT}/zones/${ZONE}/disks/${TARGET_DISK}
    fsType: ext4
EOF

# --------------------------------------------------------------------------- #
# Step 3 — Apply PVC
# --------------------------------------------------------------------------- #
echo "[3/5] Applying PersistentVolumeClaim..."

kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
  namespace: ${NAMESPACE}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ""
  volumeName: ${PV_NAME}
  resources:
    requests:
      storage: ${DISK_SIZE}
EOF

echo "      Waiting for PVC to bind..."
kubectl wait pvc "${PVC_NAME}" \
  -n "${NAMESPACE}" \
  --for=jsonpath='{.status.phase}'=Bound \
  --timeout=60s
echo "      PVC bound."

# --------------------------------------------------------------------------- #
# Step 4 — Run fix Job (chown + remove stale locks)
# --------------------------------------------------------------------------- #
echo "[4/5] Running disk fix job..."

if kubectl get job "${JOB_NAME}" -n "${NAMESPACE}" &>/dev/null; then
  echo "      Deleting previous fix job..."
  kubectl delete job "${JOB_NAME}" -n "${NAMESPACE}" --wait=true
fi

kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${NAMESPACE}
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      securityContext:
        runAsUser: 0
      containers:
        - name: fix
          image: busybox
          command:
            - sh
            - -c
            - |
              echo "Fixing ownership..."
              chown -R 2000:2000 /data
              echo "Removing stale lock files..."
              rm -f /data/mongo.lock /data/WiredTiger.lock
              echo "Done."
          volumeMounts:
            - name: data
              mountPath: /data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: ${PVC_NAME}
EOF

echo "      Waiting for fix job to complete..."
kubectl wait job "${JOB_NAME}" \
  -n "${NAMESPACE}" \
  --for=condition=complete \
  --timeout=300s
echo "      Fix job completed."

# --------------------------------------------------------------------------- #
# Step 5 — Done
# --------------------------------------------------------------------------- #
echo ""
echo "[5/5] Disk is ready."
echo ""
echo "Next step: deploy MongoDB (ArgoCD sync or helmfile)."
echo "  helmfile -e <env> -l name=countly-mongodb sync"
echo ""
