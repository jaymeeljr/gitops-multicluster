#!/usr/bin/env bash
# Evaluates the Argo CD RBAC policy offline: no cluster needed, so it also
# runs in the static CI job.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.." || exit 1
echo "== Argo CD RBAC policy =="

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
python3 -c "import yaml,sys; print(yaml.safe_load(open('argocd/rbac-cm.yaml'))['data']['policy.csv'])" > "$tmp/policy.csv"
# The CLI insists on a kubeconfig even in offline mode; give it a dummy one.
cat > "$tmp/kubeconfig" <<'EOF'
apiVersion: v1
kind: Config
clusters: [{name: offline, cluster: {server: "https://127.0.0.1:1"}}]
users: [{name: offline, user: {token: offline}}]
contexts: [{name: offline, context: {cluster: offline, user: offline, namespace: argocd}}]
current-context: offline
EOF

can() {
  [ "$(KUBECONFIG="$tmp/kubeconfig" argocd admin settings rbac can "$@" \
        --policy-file "$tmp/policy.csv" --default-role role:readonly 2>/dev/null | tail -1)" = "Yes" ]
}

expect_ok   "developer can sync dev"                 can platform-developers sync applications platform/task-platform-dev
expect_fail "developer cannot sync prod"             can platform-developers sync applications platform/task-platform-prod
expect_ok   "release manager can sync prod"          can release-managers sync applications platform/task-platform-prod
expect_fail "release manager cannot delete prod app" can release-managers delete applications platform/task-platform-prod
expect_fail "release manager cannot exec into pods"  can release-managers create exec platform/task-platform-prod
expect_fail "release manager cannot edit projects"   can release-managers update projects platform
expect_ok   "anyone signed in can view apps"         can someone-else get applications platform/task-platform-dev
expect_fail "anyone signed in cannot sync"           can someone-else sync applications platform/task-platform-dev

summary "RBAC policy"
