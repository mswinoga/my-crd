#!/usr/bin/env bash
#
# Fallback assertions for diagnostics that are rendered as YAML *comments*
# (prefixed exactly "# ERROR:" / "# WARNING:") rather than structured
# fields. helm-unittest parses rendered manifests as YAML documents,
# which strips comments before any `asserts:` runs against them — so
# comment presence/absence can't be expressed there. This script greps
# raw `helm template` output instead. See README.md.
#
# Coverage of the diagnostics catalogue (opis-zmian.md section 5): every
# row reachable end to end has a `check` below. Rows that cannot be
# provoked through mycrd.render are covered by probes in helm-unittest
# instead (the probe output exposes `diag` as structured data):
#  - "tries to narrow library targetContainer" / "tries to change library
#    annotation": tests/annotation_policy_test.yaml (library tokens carry
#    no annotations today).
#  - "exported but has no service" / "belongs to service ... not
#    declared": tests/service_output_test.yaml (needs a token added via
#    crdkit.token.add without `service`).
#  - crdkit's annotation-name collision and non-dict annotations: not
#    reachable (this library's annotation names are fixed; it never calls
#    crdkit.token.add with a non-dict).
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0

# check DESC FIXTURE PATTERN present|absent
check() {
  local desc="$1" fixture="$2" pattern="$3" expect="$4"
  local out found
  out=$(helm template harness -f "harness/ci/test-values/${fixture}" 2>&1)
  if echo "$out" | grep -qE "$pattern"; then
    found="present"
  else
    found="absent"
  fi
  if [ "$found" != "$expect" ]; then
    echo "FAIL: $desc (expected pattern '$pattern' to be $expect, was $found)"
    fail=1
  else
    echo "ok: $desc"
  fi
}

check "full-featured.yaml: ERROR for the no-default/no-matching-env token" \
  full-featured.yaml '^# ERROR:' present

check "full-featured.yaml: WARNING for the unresolved-typo reference" \
  full-featured.yaml '^# WARNING:.*possible typo' present

check "locked-token-collision.yaml: WARNING for the reserved token" \
  locked-token-collision.yaml '^# WARNING:' present

check "cyclic-tokens.yaml: ERROR mentioning a cycle" \
  cyclic-tokens.yaml '^# ERROR:.*cycle' present

check "minimal.yaml: no diagnostics" \
  minimal.yaml '^# (ERROR|WARNING):' absent

check "env-fallback.yaml: no diagnostics" \
  env-fallback.yaml '^# (ERROR|WARNING):' absent

check "missing-target.yaml: ERROR once something actually resolves against the empty target (no proactive check anymore)" \
  missing-target.yaml "^# ERROR:.*target chain exhausted" present

check "plain-env-target.yaml: no diagnostics for a target with no sequence suffix" \
  plain-env-target.yaml '^# (ERROR|WARNING):' absent

check "services-basic.yaml: no diagnostics" \
  services-basic.yaml '^# (ERROR|WARNING):' absent

check "service-collision.yaml: ERROR naming both services, first one kept" \
  service-collision.yaml "^# ERROR: variable 'SHARED' is declared by services 'alpha' and 'beta' — keeping 'alpha'" present

check "unknown-service-type.yaml: WARNING that the service is skipped" \
  unknown-service-type.yaml "^# WARNING: service 'mystery' has unknown type 'no-such-type' — service skipped" present

check "invalid-target-container.yaml: ERROR for a targetContainer outside the accepted set" \
  invalid-target-container.yaml "^# ERROR: invalid targetContainer 'sidecar-typo' for 'BAD_CONTAINER'" present

check "explicit-service-key.yaml: WARNING that an explicit 'service' is ignored" \
  explicit-service-key.yaml "^# WARNING: variable 'OWNED' in service 'app' sets 'service' explicitly — ignored" present

check "legacy-tokens-key.yaml: WARNING that root 'tokens' is not read" \
  legacy-tokens-key.yaml "^# WARNING: values key 'tokens' is not read — declare variables under services.<ID>.environment" present

check "minimal.yaml (empty services): no 'tokens' warning" \
  minimal.yaml "values key 'tokens'" absent

check "library-token-export.yaml: WARNING that only annotations were applied to a system token" \
  library-token-export.yaml "^# WARNING: token 'ENV' is reserved by the library — only annotations were applied" present

check "library-token-export.yaml: widening a default's targetContainer (LOG_LEVEL) is silent" \
  library-token-export.yaml "^# (ERROR|WARNING):.*LOG_LEVEL" absent

check "locked-token-collision.yaml: WARNING from the annotation step, not only crdkit's" \
  locked-token-collision.yaml "^# WARNING: token 'API_GROUP' is reserved by the library — only annotations were applied" present

check "demo-service.yaml: no diagnostics" \
  demo-service.yaml '^# (ERROR|WARNING):' absent

check "generated-owner-conflict.yaml: ERROR that the generated variable is owned by another service" \
  generated-owner-conflict.yaml "^# ERROR: service 'greeter' generates variable 'GREETER_GREETING', already owned by service 'alpha' — generated value ignored" present

check "internal-key.yaml: WARNING that a crdkit-internal key was removed" \
  internal-key.yaml "^# WARNING: token 'LEAKY' declares crdkit-internal key '_generated'; it was removed" present

check "full-featured.yaml: exporting variables from several services adds no diagnostics about services" \
  full-featured.yaml "^# (ERROR|WARNING):.*(service|targetContainer)" absent

# check_fails DESC FIXTURE_PATH PATTERN
# Separate from `check` above: this asserts the render itself FAILS
# (non-zero exit), unlike everything else in this library, which always
# renders and reports problems as comments. See
# harness/ci/failure-cases/malformed-match-regex.yaml for why this one
# case is expected to abort instead of producing a diagnostic.
check_fails() {
  local desc="$1" fixture_path="$2" pattern="$3"
  local out status
  set +e
  out=$(helm template harness -f "$fixture_path" 2>&1)
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    echo "FAIL: $desc (expected non-zero exit, got 0)"
    fail=1
  elif ! echo "$out" | grep -qE "$pattern"; then
    echo "FAIL: $desc (exited non-zero as expected, but output didn't match pattern '$pattern')"
    fail=1
  else
    echo "ok: $desc"
  fi
}

check_fails "malformed-match-regex.yaml: render aborts on invalid regex, doesn't hang or silently swallow it" \
  harness/ci/failure-cases/malformed-match-regex.yaml "error parsing regexp"

exit $fail
