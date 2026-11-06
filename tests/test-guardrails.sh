#!/usr/bin/env bash
# Tries to misuse the "platform" project. Argo CD must refuse each attempt.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
echo "== AppProject guardrails =="
REVISION="${REVISION:-main}"

rogue_app() {  # rogue_app <name> <repoURL> <path> <namespace>
  kubectl --context "$DEV" apply -f - >/dev/null <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $1
  namespace: argocd
spec:
  project: platform
  source:
    repoURL: $2
    targetRevision: $REVISION
    path: $3
  destination:
    name: in-cluster
    namespace: $4
EOF
}

refused() {  # the app carries an error from the project's rules
  kubectl --context "$DEV" -n argocd get application "$1" -o yaml \
    | grep -Eiq "not permitted|do not match|not allowed"
}

REPO=https://github.com/jaymeeljr/gitops-multicluster.git

rogue_app rogue-namespace "$REPO" apps/task-platform/overlays/dev kube-system
eventually 120 "deploying into kube-system is refused" refused rogue-namespace

rogue_app rogue-repo https://github.com/example/untrusted.git apps manifests task-platform
eventually 120 "deploying from an unapproved repository is refused" refused rogue-repo

rogue_app rogue-kinds "$REPO" tests/fixtures/forbidden task-platform
sync_app rogue-kinds >/dev/null 2>&1
eventually 120 "ClusterRole and Secret in the app are refused" refused rogue-kinds
expect_fail "no ClusterRole was created" kubectl --context "$DEV" get clusterrole guardrail-escalation
expect_fail "no Secret was created"      kubectl --context "$DEV" -n task-platform get secret guardrail-secret

kubectl --context "$DEV" -n argocd delete application rogue-namespace rogue-repo rogue-kinds --wait=false >/dev/null
summary "Guardrails"
