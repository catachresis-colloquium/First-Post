#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Run: bash tests/proofs/check_proofs_test.sh
# The checker executes on load, so exercise its Agda branch as a subprocess.
# A fake prover verifies the invocation contract without installing Agda or
# claiming that the actual proof modules type-check.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
FIXTURE="$TEST_DIR/repo with spaces"
mkdir -p "$FIXTURE/scripts" "$FIXTURE/verification/proofs/agda" "$TEST_DIR/bin"
cp "$REPO_ROOT/scripts/check-proofs.sh" "$FIXTURE/scripts/"
export AGDA_TEST_LOG="$TEST_DIR/agda.log"
export AGDA_TEST_EXIT=0
export PATH="$TEST_DIR/bin:$PATH"

cat > "$TEST_DIR/bin/agda" <<'AGDA'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == --version ]]; then
    echo 'Agda version test-double'
    exit 0
fi
{
    printf 'cwd=%s\n' "$PWD"
    printf 'arg=%s\n' "$@"
} >> "$AGDA_TEST_LOG"
# Fail loudly if a strict flag is dropped, an extra option is introduced, or
# the module path is split at whitespace. Option order is immaterial.
[[ $# -eq 4 ]] || exit 90
for flag in --safe --without-K --cubical-compatible; do
    found=false
    for arg in "$@"; do
        [[ "$arg" != "$flag" ]] || found=true
    done
    "$found" || exit 91
done
[[ -f "${4}" ]] || exit 92
if [[ "$AGDA_TEST_EXIT" != 0 ]]; then
    echo 'strict Agda check rejected module' >&2
fi
exit "$AGDA_TEST_EXIT"
AGDA
chmod +x "$TEST_DIR/bin/agda"

fail() { printf 'FAIL: %s\n%s\n' "$1" "${OUTPUT:-}" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$1"; }
assert_output() { [[ "$OUTPUT" == *"$1"* ]] || fail "missing diagnostic: $1"; }
run_check() {
    local expected="$1" actual=0
    : > "$AGDA_TEST_LOG"
    # Run from outside the fixture: source roots must be resolved by the checker.
    OUTPUT="$(cd "$TEST_DIR" && bash "$FIXTURE/scripts/check-proofs.sh" agda 2>&1)" || actual=$?
    [[ "$actual" -eq "$expected" ]] || fail "expected exit $expected, got $actual"
}

# Use the real manifest to ensure its gated entry receives all strict flags.
cp "$REPO_ROOT/verification/proofs/agda/MANIFEST" "$FIXTURE/verification/proofs/agda/MANIFEST"
: > "$FIXTURE/verification/proofs/agda/Properties.agda"
run_check 0
assert_output 'RESULT: PASS'
[[ "$(cat "$AGDA_TEST_LOG")" == "cwd=$FIXTURE/verification/proofs/agda"$'\narg=--safe\narg=--without-K\narg=--cubical-compatible\narg=Properties.agda' ]] || fail 'wrong Agda source root or arguments'
pass 'real manifest invokes Agda with strict flags and a relative module path'

AGDA_TEST_EXIT=42
run_check 1
assert_output 'strict Agda check rejected module'
assert_output 'RESULT: FAIL (1 failure(s), 0 unexpected pass(es))'
pass 'strict-check failure fails a gated module and preserves diagnostics'

# Quarantine must retain its fail-until-promoted semantics with strict flags.
printf '%s\n' 'verification/proofs/agda|Properties.agda|quarantine|known strict-check failure' > "$FIXTURE/verification/proofs/agda/MANIFEST"
run_check 0
assert_output 'fail (quarantined, expected)'
assert_output 'reason:known strict-check failure'
assert_output 'RESULT: PASS'
pass 'strict-check failure is expected for a quarantined module'

AGDA_TEST_EXIT=0
run_check 1
assert_output 'Promote'
assert_output 'RESULT: FAIL (0 failure(s), 1 unexpected pass(es))'
pass 'a quarantined module compiling with strict flags requires promotion'

# Every module must receive the flags, including paths containing whitespace.
mkdir -p "$FIXTURE/verification/proofs/agda/nested root"
: > "$FIXTURE/verification/proofs/agda/nested root/Second module.agda"
printf '%s\n' \
    'verification/proofs/agda|Properties.agda|gated|' \
    'verification/proofs/agda/nested root|Second module.agda|gated|' \
    > "$FIXTURE/verification/proofs/agda/MANIFEST"
run_check 0
assert_output 'RESULT: PASS'
[[ "$(grep -c '^arg=--without-K$' "$AGDA_TEST_LOG")" -eq 2 ]] || fail 'strict flags did not reach every module'
[[ "$(tail -5 "$AGDA_TEST_LOG")" == "cwd=$FIXTURE/verification/proofs/agda/nested root"$'\narg=--safe\narg=--without-K\narg=--cubical-compatible\narg=Second module.agda' ]] || fail 'module or source root containing spaces was split'
pass 'multiple modules and whitespace paths retain strict invocation'

# Counts are derived from the table rather than hardcoded to the current census.
# This also handles a future empty census without dividing by zero.
awk -F '|' '
    /^\| \*Total\*/ {
        total=$3; done=$4
        gsub(/[*[:space:]]/, "", total)
        gsub(/[*[:space:]]/, "", done)
        totals++
    }
    /^\*Overall\*:/ { overall=$0; summaries++ }
    END {
        expected="*Overall*: " done " of " total " obligations proven"
        if (totals != 1 || summaries != 1 || total !~ /^[0-9]+$/ ||
            done !~ /^[0-9]+$/ || done+0 > total+0 || overall != expected) exit 1
    }
' "$REPO_ROOT/docs/status/PROOF-STATUS.adoc" || fail 'overall proof census must report counts matching Total and Done'
pass 'proof census reports counts consistent with the summary table'
