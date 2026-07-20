#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wrapper="$repo_root/script/dig-fame-burn-pool.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin" "$tmp_dir/broadcast/DigFameBurnPool.s.sol/8453"

cat >"$tmp_dir/bin/cast" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == "block-number" ]]
printf '%s\n' "$FAKE_RPC_BLOCK"
EOF

cat >"$tmp_dir/bin/forge" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FAKE_FORGE_CALLS"
if [[ " $* " == *" --sig check() "* ]]; then
  attempt=1
  if [[ -f "$FAKE_STATUS_ATTEMPTS" ]]; then
    attempt=$(( $(<"$FAKE_STATUS_ATTEMPTS") + 1 ))
  fi
  printf '%s\n' "$attempt" >"$FAKE_STATUS_ATTEMPTS"
  if [[ "${FAKE_STATUS_ERROR:-}" == "non-transient" ]]; then
    echo "Error: execution reverted" >&2
    exit 1
  fi
  if ((attempt <= ${FAKE_UNKNOWN_BLOCK_ATTEMPTS:-0})); then
    echo 'Error: HTTP error 400 with body: {"error":{"message":"Unknown block","code":26}}' >&2
    exit 1
  fi
  printf 'FAME_DIG_STATUS_BLOCK %s\n' "$FAKE_RPC_BLOCK"
  printf 'FAME_DIG_TARGET_ACQUIRED=false\n'
  printf 'FAME_DIG_RECOVERY_POSSIBLE=false\n'
  exit 0
fi
exit 99
EOF

cat >"$tmp_dir/bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "$tmp_dir/bin/cast" "$tmp_dir/bin/forge" "$tmp_dir/bin/sleep"

write_receipt() {
  local block_number="$1"
  printf '{"receipts":[{"blockNumber":"%s"}]}\n' "$block_number" \
    >"$tmp_dir/broadcast/DigFameBurnPool.s.sol/8453/run-latest.json"
}

run_wrapper() {
  local output_file="$1"
  (
    cd "$tmp_dir"
    PATH="$tmp_dir/bin:$PATH" \
      BASE_CHAIN_ID=8453 \
      BASE_FAME_ADDRESS=0xf307e242BfE1EC1fF01a4Cef2fdaa81b10A52418 \
      FAME_DIG_PRIMARY_PRIVATE_KEY=1 \
      FAME_DIG_SECONDARY_PRIVATE_KEY=2 \
      FAME_DIG_RECOVER_INTERRUPTED=true \
      FAKE_FORGE_CALLS="$tmp_dir/forge-calls" \
      FAKE_STATUS_ATTEMPTS="$tmp_dir/status-attempts" \
      "$wrapper" 587 0
  ) >"$output_file" 2>&1
}

# A lagging RPC head must use the newer successful return-receipt block.
write_receipt 0xc8
: >"$tmp_dir/forge-calls"
rm -f "$tmp_dir/status-attempts"
export FAKE_RPC_BLOCK=199
set +e
run_wrapper "$tmp_dir/lagging-output"
status=$?
set -e
[[ "$status" -eq 1 ]]
grep -q -- '--fork-block-number 200' "$tmp_dir/forge-calls"
[[ "$(wc -l <"$tmp_dir/forge-calls")" -eq 1 ]]
grep -q 'No interrupted turn exists at block 200; continuing normally.' "$tmp_dir/lagging-output"

# An old artifact is only a lower bound; the newer RPC head wins.
write_receipt 100
: >"$tmp_dir/forge-calls"
rm -f "$tmp_dir/status-attempts"
export FAKE_RPC_BLOCK=200
set +e
run_wrapper "$tmp_dir/old-output"
status=$?
set -e
[[ "$status" -eq 1 ]]
grep -q -- '--fork-block-number 200' "$tmp_dir/forge-calls"

# Existing malformed receipt data must fail closed before an unpinned check.
printf '{"receipts":[]}\n' >"$tmp_dir/broadcast/DigFameBurnPool.s.sol/8453/run-latest.json"
: >"$tmp_dir/forge-calls"
rm -f "$tmp_dir/status-attempts"
set +e
run_wrapper "$tmp_dir/malformed-output"
status=$?
set -e
[[ "$status" -eq 2 ]]
[[ ! -s "$tmp_dir/forge-calls" ]]
grep -q 'Cannot read the final receipt block' "$tmp_dir/malformed-output"

# A load-balanced provider may briefly reject the just-mined receipt block.
write_receipt 200
: >"$tmp_dir/forge-calls"
rm -f "$tmp_dir/status-attempts"
export FAKE_RPC_BLOCK=200
export FAKE_UNKNOWN_BLOCK_ATTEMPTS=2
set +e
run_wrapper "$tmp_dir/retry-output"
status=$?
set -e
unset FAKE_UNKNOWN_BLOCK_ATTEMPTS
[[ "$status" -eq 1 ]]
[[ "$(wc -l <"$tmp_dir/forge-calls")" -eq 3 ]]
grep -q 'No interrupted turn exists at block 200; continuing normally.' "$tmp_dir/retry-output"

# Unknown block retries remain bounded and fail closed on the thirtieth failure.
: >"$tmp_dir/forge-calls"
rm -f "$tmp_dir/status-attempts"
export FAKE_UNKNOWN_BLOCK_ATTEMPTS=30
set +e
run_wrapper "$tmp_dir/exhausted-output"
status=$?
set -e
unset FAKE_UNKNOWN_BLOCK_ATTEMPTS
[[ "$status" -eq 2 ]]
[[ "$(wc -l <"$tmp_dir/forge-calls")" -eq 30 ]]
grep -q 'Unknown block' "$tmp_dir/exhausted-output"

# Any other Forge failure exits immediately without retrying.
: >"$tmp_dir/forge-calls"
rm -f "$tmp_dir/status-attempts"
export FAKE_STATUS_ERROR=non-transient
set +e
run_wrapper "$tmp_dir/non-transient-output"
status=$?
set -e
unset FAKE_STATUS_ERROR
[[ "$status" -eq 2 ]]
[[ "$(wc -l <"$tmp_dir/forge-calls")" -eq 1 ]]
grep -q 'execution reverted' "$tmp_dir/non-transient-output"

echo "DigFameBurnPool wrapper tests passed."
