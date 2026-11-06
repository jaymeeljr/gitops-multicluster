#!/usr/bin/env bash
# Someone changes the cluster by hand instead of through Git.
#   dev  -> Argo CD reverts it automatically (self-heal)
#   prod -> Argo CD flags it as drift, leaves it for a human to decide
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
echo "== Drift detection and self-heal =="

echo "-- dev: manual changes are reverted"
kubectl --context "$DEV" -n task-platform scale deployment api --replicas=4 >/dev/null
eventually 120 "manual scale to 4 replicas is reverted to 1" replicas_are "$DEV" api 1

kubectl --context "$DEV" -n task-platform delete networkpolicy default-deny-all >/dev/null
eventually 120 "deleted default-deny NetworkPolicy is recreated" \
  kubectl --context "$DEV" -n task-platform get networkpolicy default-deny-all

echo "-- prod: drift is reported, not silently overwritten"
kubectl --context "$PROD" -n task-platform scale deployment api --replicas=1 >/dev/null
eventually 120 "prod app reports OutOfSync after a manual change" sync_is task-platform-prod OutOfSync
sleep 20
expect_ok "prod change is not auto-reverted (needs approval)" replicas_are "$PROD" api 1

sync_app task-platform-prod >/dev/null
eventually 180 "re-sync restores prod to 3 replicas from Git" replicas_are "$PROD" api 3

summary "Drift"
