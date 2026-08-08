#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <token-id> <max-turns>" >&2
  exit 64
fi

token_id="$1"
max_turns="$2"

if [[ ! "$token_id" =~ ^[1-9][0-9]*$ ]]; then
  echo "token-id must be a positive integer" >&2
  exit 64
fi

if [[ ! "$max_turns" =~ ^[0-9]+$ ]]; then
  echo "max-turns must be a non-negative integer" >&2
  exit 64
fi

required_vars=(
  BASE_CHAIN_ID
  BASE_FAME_ADDRESS
  FAME_DIG_PRIMARY_PRIVATE_KEY
  FAME_DIG_SECONDARY_PRIVATE_KEY
)

for variable in "${required_vars[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    echo "Missing required environment variable: $variable" >&2
    exit 64
  fi
done

for command_name in cast forge jq; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 64
  fi
done

export FAME_DIG_TOKEN_ID="$token_id"
solidity_script="script/DigFameBurnPool.s.sol:DigFameBurnPool"
broadcast_file="broadcast/DigFameBurnPool.s.sol/${BASE_CHAIN_ID}/run-latest.json"

read_status() {
  local status_block="$1"
  local -a command=(
    forge script "$solidity_script"
    --sig "check()"
    --rpc-url base
    --fork-block-number "$status_block"
  )

  local attempt output
  for ((attempt = 1; attempt <= 30; attempt++)); do
    if output="$("${command[@]}" 2>&1)"; then
      printf '%s\n' "$output"
      return
    fi
    if [[ "$output" == *"Unknown block"* && "$attempt" -lt 30 ]]; then
      sleep 1
      continue
    fi
    echo "$output" >&2
    return 2
  done
}

latest_receipt_block() {
  [[ -f "$broadcast_file" ]] || return 1

  local block_hex
  if ! block_hex="$(jq -er '.receipts[-1].blockNumber | select(type == "string" and test("^(0x[0-9a-fA-F]+|[0-9]+)$"))' "$broadcast_file")"; then
    echo "Cannot read the final receipt block from $broadcast_file" >&2
    return 2
  fi
  printf '%d\n' "$((block_hex))"
}

canonical_status_block() {
  local rpc_block
  if ! rpc_block="$(cast block-number --rpc-url base)"; then
    echo "Cannot read the current Base block number." >&2
    return 2
  fi

  local receipt_block
  if [[ -f "$broadcast_file" ]]; then
    receipt_block="$(latest_receipt_block)" || return 2
    if ((receipt_block > rpc_block)); then
      printf '%s\n' "$receipt_block"
      return
    fi
  fi

  printf '%s\n' "$rpc_block"
}

status_block="$(canonical_status_block)"
status_output="$(read_status "$status_block")"

if [[ "${FAME_DIG_RECOVER_INTERRUPTED:-false}" == "true" ]]; then
  if [[ "$status_output" == *"FAME_DIG_RECOVERY_POSSIBLE=true"* ]]; then
    echo "Recovering an explicitly confirmed interrupted turn."
    if ! forge script "$solidity_script" --rpc-url base --broadcast --slow; then
      echo "Interrupted-turn recovery failed; no new turn was attempted." >&2
      exit 2
    fi
    export FAME_DIG_RECOVER_INTERRUPTED=false
    status_block="$(canonical_status_block)"
    status_output="$(read_status "$status_block")"
  else
    echo "No interrupted turn exists at block $status_block; continuing normally."
    export FAME_DIG_RECOVER_INTERRUPTED=false
  fi
fi

if [[ "$status_output" == *"FAME_DIG_RECOVERY_POSSIBLE=true"* ]]; then
  echo "The secondary wallet holds unit() - 1 FAME; an interrupted turn may need recovery." >&2
  echo "Confirm that balance came from this script, then run:" >&2
  echo "doppler run -- env FAME_DIG_RECOVER_INTERRUPTED=true \"$0\" \"$token_id\" \"$max_turns\"" >&2
  exit 2
fi

if [[ "$status_output" == *"FAME_DIG_TARGET_ACQUIRED=true"* ]]; then
  echo "Token $token_id is already owned by the primary wallet."
  exit 0
fi

for ((turn = 1; turn <= max_turns; turn++)); do
  echo "Burn-pool turn $turn of $max_turns"
  if ! forge script "$solidity_script" --rpc-url base --broadcast --slow; then
    echo "A turn failed and may have completed only its outbound transaction." >&2
    echo "Inspect both wallet balances. If the secondary holds unit() - 1 FAME, run:" >&2
    echo "doppler run -- env FAME_DIG_RECOVER_INTERRUPTED=true \"$0\" \"$token_id\" \"$((max_turns - turn))\"" >&2
    exit 2
  fi

  status_block="$(canonical_status_block)"
  status_output="$(read_status "$status_block")"
  if [[ "$status_output" == *"FAME_DIG_RECOVERY_POSSIBLE=true"* ]]; then
    echo "A turn ended with recovery still required. Run:" >&2
    echo "doppler run -- env FAME_DIG_RECOVER_INTERRUPTED=true \"$0\" \"$token_id\" \"$((max_turns - turn))\"" >&2
    exit 2
  fi
  if [[ "$status_output" == *"FAME_DIG_TARGET_ACQUIRED=true"* ]]; then
    echo "Acquired token $token_id after $turn turn(s)."
    exit 0
  fi
done

echo "Token $token_id was not acquired after $max_turns turn(s)." >&2
exit 1
