#!/usr/bin/env bash
# Dev deploys itself from Git; prod waits for a release manager.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
echo "== GitOps delivery =="

eventually 300 "dev app is Synced and Healthy without any manual step" app_is task-platform-dev "Synced Healthy"
expect_ok "dev runs 1 API replica with the dev image" sh -c \
  "kubectl --context $DEV -n task-platform get deploy api -o jsonpath='{.spec.replicas} {.spec.template.spec.containers[0].image}' | grep -qx '1 task-api:dev'"

eventually 120 "prod app is detected as OutOfSync (not applied automatically)" sync_is task-platform-prod OutOfSync
expect_fail "nothing was deployed to prod before approval" \
  kubectl --context "$PROD" -n task-platform get deployment api

echo "-- release manager syncs prod"
sync_app task-platform-prod >/dev/null
eventually 300 "prod app is Synced and Healthy after manual sync" app_is task-platform-prod "Synced Healthy"
expect_ok "prod runs 3 ready API replicas" ready_are "$PROD" api 3
expect_ok "prod runs the pinned release image" sh -c \
  "kubectl --context $PROD -n task-platform get deploy api -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -qx task-api:release-1"
expect_ok "prod has a PodDisruptionBudget (prod-only object)" \
  kubectl --context "$PROD" -n task-platform get pdb api

summary "Delivery"
