#!/usr/bin/env bash
# =============================================================================
# Rebuild the whole Phase 3 environment from zero (inside WSL Ubuntu):
#   kind cluster → Envoy Gateway → metrics-server → platform objects → app via Helm
#
#   bash scripts/k8s-up.sh            # cluster + platform + dev release
#   bash scripts/k8s-up.sh prod       # ... + the prod release too
#   kind delete cluster --name devops-lab     # throw everything away
#
# Every step is explained in docs/03-kubernetes-helm.md. This script only chains them.
# Safe to re-run: each step skips or upgrades what already exists.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

CLUSTER=devops-lab
ENVOY_GATEWAY_VERSION=v1.10.0
METRICS_SERVER_CHART_VERSION=3.14.0

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

step "1/5 kind cluster '$CLUSTER'"
if kind get clusters | grep -qx "$CLUSTER"; then
  echo "already exists"
else
  kind create cluster --config k8s/kind-cluster.yaml
fi
kubectl config use-context "kind-$CLUSTER" >/dev/null
kubectl wait --for=condition=Ready node --all --timeout=120s

step "2/5 Envoy Gateway $ENVOY_GATEWAY_VERSION (Gateway API implementation)"
helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm --version "$ENVOY_GATEWAY_VERSION" \
  -n envoy-gateway-system --create-namespace --wait --timeout 5m

step "3/5 metrics-server (for kubectl top + HPA)"
helm upgrade --install metrics-server metrics-server --repo https://kubernetes-sigs.github.io/metrics-server/ \
  --version "$METRICS_SERVER_CHART_VERSION" -n kube-system --set "args={--kubelet-insecure-tls}" --wait --timeout 3m

step "4/5 platform: Gateway + namespaces"
kubectl apply -f k8s/platform/gateway.yaml
kubectl apply -f k8s/platform/namespaces.yaml
kubectl -n envoy-gateway-system wait --for=condition=Programmed gateway/main --timeout=180s

step "5/5 app: Helm release(s)"
helm upgrade --install taskapi helm/taskapi -n taskapi-dev -f helm/taskapi/values-dev.yaml --wait --timeout 5m
if [ "${1:-}" = "prod" ]; then
  helm upgrade --install taskapi helm/taskapi -n taskapi-prod -f helm/taskapi/values-prod.yaml --wait --timeout 6m
fi

step "done"
helm list -A
echo
echo "dev:  curl http://taskapi-dev.localhost:8090/health"
[ "${1:-}" = "prod" ] && echo "prod: curl http://taskapi.localhost:8090/health"
exit 0
