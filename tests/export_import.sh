#!/bin/bash
# Tests for `claudewho export` / `claudewho import`. Runs only under temp HOMEs.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/bin/claudewho"
unset CLAUDEWHO_CONFIG

fail() { echo "FAIL: $*" >&2; exit 1; }

H1=$(mktemp -d)
H2=$(mktemp -d)
OUT=$(mktemp -d)
trap 'rm -rf "$H1" "$H2" "$OUT"' EXIT

HOME="$H1" "$BIN" add a >/dev/null
HOME="$H1" "$BIN" add b >/dev/null
HOME="$H1" "$BIN" export > "$OUT/export.json" || fail "export failed"
jq -e '.accounts == ["a","b"] and .version == 1 and .current == null' "$OUT/export.json" >/dev/null \
    || fail "export JSON wrong: $(cat "$OUT/export.json")"

HOME="$H2" "$BIN" import "$OUT/export.json" > "$OUT/import1.txt" || fail "import failed"
[[ "$(cat "$H2/.claudewho.conf")" == $'a\nb' ]] || fail "config content wrong"
[[ -d "$H2/.claudewho-a" ]] || fail "~/.claudewho-a missing"
[[ -x "$H2/.local/bin/claudewho-a" ]] || fail "wrapper claudewho-a not executable"
[[ -x "$H2/.local/bin/claudewho-ide-b" ]] || fail "ide wrapper b not executable"
grep -q "Log in to each new account" "$OUT/import1.txt" || fail "missing login hint"

HOME="$H2" "$BIN" import - < "$OUT/export.json" > "$OUT/import2.txt" || fail "second import failed"
[[ "$(grep -c exists "$OUT/import2.txt")" == 2 ]] || fail "expected 2 'exists' lines"
[[ "$(wc -l < "$H2/.claudewho.conf" | tr -d ' ')" == 2 ]] || fail "config should have 2 lines"

echo '{"version":1,"accounts":["Bad_Name"],"current":null}' > "$OUT/bad.json"
rc=0; HOME="$H2" "$BIN" import "$OUT/bad.json" >/dev/null 2>&1 || rc=$?
[[ $rc == 1 ]] || fail "Bad_Name import should exit 1, got $rc"
echo 'not json' > "$OUT/junk.json"
rc=0; HOME="$H2" "$BIN" import "$OUT/junk.json" >/dev/null 2>&1 || rc=$?
[[ $rc == 1 ]] || fail "invalid JSON import should exit 1, got $rc"
[[ "$(wc -l < "$H2/.claudewho.conf" | tr -d ' ')" == 2 ]] || fail "bad import changed config"

echo OK
