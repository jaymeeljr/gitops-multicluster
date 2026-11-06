#!/usr/bin/env bash
# Builds the whole environment from nothing:
#   dev  cluster  - runs Argo CD (management) and the dev workloads
#   prod cluster  - runs prod workloads; Argo CD reaches it with a
#                   namespace-scoped identity, not cluster-admin
#
# Usage: scripts/bootstrap.sh <path-to-secure-cicd-pipeline> [git-revision]
# Requires: docker, kind, kubectl.
set -euo pipefail
cd "$(dirname "$0")/.."

API_SRC="${1:?path to the secure-cicd-pipeline checkout}"
REVISION="${2:-main}"
ARGOCD_VERSION=v3.6.1
DEV=kind-dev
PROD=kind-prod

echo "==> Clusters"
kind get clusters | grep -qx dev  || kind create cluster --name dev
kind get clusters | grep -qx prod || kind create cluster --name prod

echo "==> Application image (dev tracks builds, prod runs a pinned release)"
docker build -t task-api:dev "$API_SRC"
docker tag task-api:dev task-api:release-1
kind load docker-image task-api:dev --name dev
kind load docker-image task-api:release-1 --name prod

echo "==> Platform-owned namespace, quota and limits on both clusters"
kubectl --context "$DEV"  apply -f bootstrap/namespace.yaml
kubectl --context "$PROD" apply -f bootstrap/namespace.yaml
kubectl --context "$PROD" apply -f bootstrap/prod-argocd-access.yaml

echo "==> Argo CD ${ARGOCD_VERSION} on the dev (management) cluster"
kubectl --context "$DEV" create namespace argocd --dry-run=client -o yaml | kubectl --context "$DEV" apply -f -
kubectl --context "$DEV" apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
kubectl --context "$DEV" apply --server-side --force-conflicts -f argocd/rbac-cm.yaml -f argocd/argocd-cm.yaml
for d in argocd-server argocd-repo-server argocd-applicationset-controller; do
  kubectl --context "$DEV" -n argocd rollout status "deployment/$d" --timeout=300s
done
kubectl --context "$DEV" -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

echo "==> Register prod with a namespace-scoped token (generated, never committed)"
for _ in $(seq 1 30); do
  TOKEN="$(kubectl --context "$PROD" -n argocd-access get secret argocd-manager-token -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || true)"
  [ -n "$TOKEN" ] && break
  sleep 2
done
CA="$(kubectl --context "$PROD" -n argocd-access get secret argocd-manager-token -o jsonpath='{.data.ca\.crt}')"
CONFIG="$(printf '{"bearerToken":"%s","tlsClientConfig":{"insecure":false,"caData":"%s"}}' "$TOKEN" "$CA")"

kubectl --context "$DEV" -n argocd delete secret cluster-prod --ignore-not-found
kubectl --context "$DEV" -n argocd create secret generic cluster-prod \
  --from-literal=name=prod \
  --from-literal=server=https://prod-control-plane:6443 \
  --from-literal=namespaces=task-platform \
  --from-literal=clusterResources=false \
  --from-literal=config="$CONFIG"
kubectl --context "$DEV" -n argocd label secret cluster-prod argocd.argoproj.io/secret-type=cluster

echo "==> Project guardrails and the ApplicationSet (revision: ${REVISION})"
kubectl --context "$DEV" apply -f argocd/project.yaml
sed "s/revision: main/revision: ${REVISION}/" argocd/applicationset.yaml | kubectl --context "$DEV" apply -f -

echo "Bootstrap complete."
