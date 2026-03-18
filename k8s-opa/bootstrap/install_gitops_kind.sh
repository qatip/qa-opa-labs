#!/bin/bash
set -euo pipefail

echo "=============================="
echo " GitOps Host Bootstrap Starting"
echo "=============================="

ARGO_ADMIN_PASSWORD="__ARGO_ADMIN_PASSWORD__"

log() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }

# ---------------------------------------
# Install prerequisites
# ---------------------------------------
log "Installing prerequisites..."
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release apache2-utils

# ---------------------------------------
# Install Docker (idempotent-ish)
# ---------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker..."
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io
  systemctl enable docker
  systemctl start docker
  usermod -aG docker ubuntu || true
else
  log "Docker already installed."
fi

# ---------------------------------------
# Install kubectl
# ---------------------------------------
if ! command -v kubectl >/dev/null 2>&1; then
  log "Installing kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl
  mv kubectl /usr/local/bin/kubectl
else
  log "kubectl already installed."
fi

# ---------------------------------------
# Install kind
# ---------------------------------------
if ! command -v kind >/dev/null 2>&1; then
  log "Installing kind..."
  curl -Lo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64
  chmod +x /usr/local/bin/kind
else
  log "kind already installed."
fi

# ---------------------------------------
# Create clusters (skip if exists)
# ---------------------------------------
CLUSTERS=(platform dev prod)
KIND_IMAGE="kindest/node:v1.31.0"

PLATFORM_CONFIG=/tmp/kind-platform-config.yaml
cat > "$PLATFORM_CONFIG" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30080
    hostPort: 30080
    protocol: TCP
  - containerPort: 30082
    hostPort: 30082
    protocol: TCP
EOF

ensure_cluster() {
  local name="$1"
  if sudo -u ubuntu kind get clusters | grep -qx "$name"; then
    log "Kind cluster '$name' already exists. Skipping create."
  else
    log "Creating kind cluster: $name"
    if [[ "$name" == "platform" ]]; then
      sudo -u ubuntu kind create cluster --name "$name" --image "$KIND_IMAGE" --config "$PLATFORM_CONFIG"
    else
      sudo -u ubuntu kind create cluster --name "$name" --image "$KIND_IMAGE"
    fi
  fi

  # Ensure kubeconfig merged
  mkdir -p /home/ubuntu/.kube
  sudo -u ubuntu kind export kubeconfig --name "$name" --kubeconfig "/home/ubuntu/.kube/config"
}

for c in "${CLUSTERS[@]}"; do
  ensure_cluster "$c"
done

chown ubuntu:ubuntu -R /home/ubuntu/.kube

# ---------------------------------------
# Install StorageClass (local-path) on platform
# ---------------------------------------
log "Ensuring local-path provisioner on platform..."
if ! sudo -u ubuntu kubectl get ns local-path-storage --context kind-platform >/dev/null 2>&1; then
  sudo -u ubuntu kubectl apply -f \
    https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml \
    --context kind-platform
else
  log "local-path provisioner already present."
fi

# Make it default (safe to re-run)
sudo -u ubuntu kubectl patch storageclass local-path \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' \
  --context kind-platform >/dev/null 2>&1 || true

# ---------------------------------------
# Install Argo CD in platform cluster
# ---------------------------------------
log "Ensuring Argo CD installed..."
sudo -u ubuntu kubectl create namespace argocd --context kind-platform >/dev/null 2>&1 || true

if ! sudo -u ubuntu kubectl get deploy argocd-server -n argocd --context kind-platform >/dev/null 2>&1; then
sudo -u ubuntu kubectl apply --server-side -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml \
  --context kind-platform
#  sudo -u ubuntu kubectl apply -n argocd \
#    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml \
#    --context kind-platform
else
  log "Argo CD already installed."
fi

# Expose Argo CD via NodePort 30080 (idempotent patch)
log "Ensuring Argo CD service is NodePort 30080..."
sudo -u ubuntu kubectl patch svc argocd-server \
  -n argocd \
  --context kind-platform \
  --type merge \
  -p '{
    "spec": {
      "type": "NodePort",
      "ports": [
        {
          "name": "http",
          "port": 80,
          "targetPort": 8080,
          "nodePort": 30080
        }
      ]
    }
  }' >/dev/null 2>&1 || true

# Set Argo admin password (safe to re-run)
log "Setting Argo CD admin password..."
ARGO_ADMIN_HASH=$(htpasswd -nbBC 10 "" "${ARGO_ADMIN_PASSWORD}" | tr -d ':\n')
sudo -u ubuntu kubectl -n argocd patch secret argocd-secret \
  --type merge \
  -p "{\"stringData\": {\"admin.password\": \"${ARGO_ADMIN_HASH}\", \"admin.passwordMtime\": \"$(date +%FT%T%Z)\"}}" \
  --context kind-platform >/dev/null 2>&1 || true

echo "Argo CD admin password: ${ARGO_ADMIN_PASSWORD}" > /home/ubuntu/argo-password.txt
chown ubuntu:ubuntu /home/ubuntu/argo-password.txt
chmod 600 /home/ubuntu/argo-password.txt

# ---------------------------------------
# Install AWX Operator + AWX (platform cluster)
# ---------------------------------------
log "Ensuring AWX Operator + AWX..."
sudo -u ubuntu kubectl create namespace awx --context kind-platform >/dev/null 2>&1 || true

# Install operator only if CRD not present
if ! sudo -u ubuntu kubectl get crd awxs.awx.ansible.com --context kind-platform >/dev/null 2>&1; then
  log "Installing AWX Operator..."
  sudo -u ubuntu kubectl apply -k \
    "github.com/ansible/awx-operator/config/default?ref=2.19.1" \
    -n awx \
    --context kind-platform

  log "Pinning AWX Operator images..."
  sudo -u ubuntu kubectl --context kind-platform -n awx set image deployment/awx-operator-controller-manager \
    awx-manager=quay.io/ansible/awx-operator:2.19.1 \
    kube-rbac-proxy=quay.io/brancz/kube-rbac-proxy:v0.15.0

  log "Waiting for AWX Operator rollout..."
  sudo -u ubuntu kubectl --context kind-platform -n awx rollout status deployment/awx-operator-controller-manager --timeout=180s || true
else
  log "AWX Operator CRD already present."
fi

# Create AWX instance only if not present
if ! sudo -u ubuntu kubectl get awx awx -n awx --context kind-platform >/dev/null 2>&1; then
  log "Creating AWX instance (NodePort 30082)..."
  sudo -u ubuntu kubectl apply -n awx --context kind-platform -f - <<'EOF'
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx
spec:
  service_type: NodePort
  nodeport_port: 30082
EOF
else
  log "AWX instance already exists."
fi

# Wait for admin password secret
log "Waiting for AWX admin password secret (can take a while)..."
for i in {1..90}; do
  if sudo -u ubuntu kubectl get secret awx-admin-password -n awx --context kind-platform >/dev/null 2>&1; then
    log "awx-admin-password secret found."
    break
  fi
  echo "  ...not yet, sleeping 10s"
  sleep 10
done

# Save password (if available)
if sudo -u ubuntu kubectl get secret awx-admin-password -n awx --context kind-platform >/dev/null 2>&1; then
  AWX_ADMIN_PASSWORD=$(
    sudo -u ubuntu kubectl get secret awx-admin-password -n awx --context kind-platform \
      -o jsonpath='{.data.password}' | base64 -d
  )
  echo "AWX admin password: ${AWX_ADMIN_PASSWORD}" > /home/ubuntu/awx-password.txt
  chown ubuntu:ubuntu /home/ubuntu/awx-password.txt
  chmod 600 /home/ubuntu/awx-password.txt
  log "AWX password saved to /home/ubuntu/awx-password.txt"
else
  warn "AWX admin password secret not found yet. Check: kubectl --context kind-platform get pods -n awx"
fi

# ---------------------------------------
# Print summary
# ---------------------------------------
echo "==============================================="
echo " GitOps Host Bootstrap Complete!"
echo "==============================================="
echo "Clusters installed: platform, dev, prod"
echo "Kubeconfig: /home/ubuntu/.kube/config"
echo "Argo CD UI: http://<gitops_host_public_ip>:30080"
echo "Argo password: /home/ubuntu/argo-password.txt"
echo "AWX UI:  http://<gitops_host_public_ip>:30082"
echo "AWX password: /home/ubuntu/awx-password.txt (when ready)"
echo "==============================================="
