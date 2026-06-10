#!/bin/bash
# observe.sh — snapshot Claude Code Keychain credentials and per-profile
# .claude.json identity without making any API calls. Safe to run between
# logout/login steps during the keychain isolation experiment.
#
# Usage:   ./observe.sh <label>
# Output:  prints to stdout and saves to $HOME/claudewho-experiment/<HHMMSS>-<label>.txt

set -euo pipefail

label="${1:-snapshot}"
out_dir="${HOME}/claudewho-experiment"
mkdir -p "$out_dir"
out="$out_dir/$(date +%H%M%S)-${label}.txt"

{
  echo "============================================"
  echo "OBSERVATION: $label"
  date
  echo "============================================"
  echo ""

  echo "## Keychain: Claude Code-credentials* entries"
  security dump-keychain ~/Library/Keychains/login.keychain-db 2>/dev/null \
    | python3 -c '
import re, sys
text = sys.stdin.read()
blocks = re.split(r"^keychain:", text, flags=re.MULTILINE)
found = False
for b in blocks:
    m = re.search(r"\"svce\"<blob>=\"(Claude Code-credentials[^\"]*)\"", b)
    if not m:
        continue
    found = True
    acct = re.search(r"\"acct\"<blob>=\"([^\"]+)\"", b)
    cdat = re.search(r"\"cdat\"<timedate>=0x[0-9A-F]+\s+\"([0-9Z]+)", b)
    mdat = re.search(r"\"mdat\"<timedate>=0x[0-9A-F]+\s+\"([0-9Z]+)", b)
    print(f"  {m.group(1)}")
    na = "-"
    print(f"    acct={acct.group(1) if acct else na}  cdat={cdat.group(1) if cdat else na}  mdat={mdat.group(1) if mdat else na}")
if not found:
    print("  (none)")
'
  echo ""

  echo "## Identity per profile (.claude.json oauthAccount)"
  for dir in ~/.claudewho-*; do
    [[ -d "$dir" ]] || continue
    name=$(basename "$dir" | sed 's/^\.claudewho-//')
    cj="$dir/.claude.json"
    if [[ -f "$cj" ]]; then
      email=$(jq -r '.oauthAccount.emailAddress // "(none)"' "$cj" 2>/dev/null)
      uuid=$(jq -r '.oauthAccount.accountUuid // "(none)"' "$cj" 2>/dev/null)
      org=$(jq -r '.oauthAccount.organizationName // "(none)"' "$cj" 2>/dev/null)
      mtime=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$cj" 2>/dev/null)
      echo "  $name: email=$email  uuid=${uuid:0:8}  org=\"$org\""
      echo "    .claude.json mtime: $mtime"
    else
      echo "  $name: (no .claude.json)"
    fi
  done
  echo ""

  echo "## claudewho current account"
  cat ~/.claudewho-current-account 2>/dev/null || echo "  (none)"
  echo ""
} | tee "$out"

echo ""
echo "Saved to: $out"
