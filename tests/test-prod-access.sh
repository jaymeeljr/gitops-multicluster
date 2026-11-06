#!/usr/bin/env bash
# Proves Argo CD's credentials for prod are namespace-scoped, not cluster-admin.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
echo "== Argo CD access to prod (least privilege) =="

as_argo() { kubectl --context "$PROD" auth can-i "$@" --as=system:serviceaccount:argocd-access:argocd-manager; }

expect_ok   "can manage deployments in task-platform" as_argo update deployments -n task-platform
expect_fail "cannot read secrets in task-platform"    as_argo get secrets -n task-platform
expect_fail "cannot touch kube-system"                as_argo get pods -n kube-system
expect_fail "cannot create ClusterRoleBindings"       as_argo create clusterrolebindings
expect_fail "cannot delete namespaces"                as_argo delete namespaces
expect_fail "cannot exec into pods"                   as_argo create pods/exec -n task-platform
expect_fail "cannot change its own quota"             as_argo update resourcequotas -n task-platform

summary "Prod access"
