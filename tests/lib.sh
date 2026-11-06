# shellcheck shell=bash
# Shared helpers for the GitOps test suites.
PASS=0
FAIL=0
DEV="${DEV:-kind-dev}"
PROD="${PROD:-kind-prod}"

pass() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }

expect_ok()   { local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }
expect_fail() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$d"; else pass "$d"; fi; }

# eventually <seconds> "description" command...  -> must succeed within the time limit
eventually() {
  local limit="$1" desc="$2"; shift 2
  local end=$((SECONDS + limit))
  while [ "$SECONDS" -lt "$end" ]; do
    if "$@" >/dev/null 2>&1; then pass "$desc"; return 0; fi
    sleep 5
  done
  fail "$desc (not within ${limit}s)"
  return 1
}

app_state() {  # app_state <app> -> "Synced Healthy"
  kubectl --context "$DEV" -n argocd get application "$1" \
    -o jsonpath='{.status.sync.status} {.status.health.status}'
}
app_is() { [ "$(app_state "$1")" = "$2" ]; }
sync_is() {  # sync_is <app> <Synced|OutOfSync>
  [ "$(kubectl --context "$DEV" -n argocd get application "$1" -o jsonpath='{.status.sync.status}')" = "$2" ]
}

replicas() {  # replicas <context> <deployment> -> spec.replicas
  kubectl --context "$1" -n task-platform get deployment "$2" -o jsonpath='{.spec.replicas}'
}
replicas_are() { [ "$(replicas "$1" "$2")" = "$3" ]; }

ready_are() {  # ready_are <context> <deployment> <n>
  [ "$(kubectl --context "$1" -n task-platform get deployment "$2" -o jsonpath='{.status.readyReplicas}')" = "$3" ]
}

sync_app() {  # trigger a manual sync, as a release manager would from the UI/CLI
  kubectl --context "$DEV" -n argocd patch application "$1" --type merge \
    -p '{"operation":{"initiatedBy":{"username":"release-manager"},"sync":{}}}'
}

summary() {
  echo
  echo "$1: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ]
}
