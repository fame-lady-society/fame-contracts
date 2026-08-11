---
chain: base-fork
status: ready-for-final-predeployment-run
contracts: UniversalPoolArtMarketplace + FameMarketplaceCheckout
---

# Final predeployment Base fork run

This is the last disposable fork rehearsal before the production procedure in
[`base-universal-pool-art-marketplace-production-implementation.md`](../handoffs/base-universal-pool-art-marketplace-production-implementation.md).
It has three jobs:

1. run the complete automated latest-Base end-to-end contract campaign;
2. deploy the receipt-aware marketplace and checkout stack on a fresh Base fork
   and leave the marketplace active under the deployer; and
3. provide that temporary stack to `fls-www` for human browser testing.

Provider, staking, unstaking, checkout, redemption, and other product testing
are intentionally not scripted here. Exercise those flows through the browser.
This document only prepares the fork, proves the automated contract coverage,
and exposes two Anvil helpers useful during browser testing.

Every transaction in this rehearsal must target the literal loopback RPC
`http://127.0.0.1:8545`. Never substitute a Base RPC, load a production signing
key, publish the temporary addresses, or preserve Foundry `broadcast/` output.
The fork deployment remains deployer-owned; no Society Safe handoff is part of
this run.

## 1. Record the candidate revisions

Run from `fame-contracts`. Fail closed if either candidate checkout is dirty;
only then record both revisions in the evidence table:

```sh
(
  assert_clean() {
    local repo="$1"
    if test -n "$(git -C "$repo" status --porcelain)"; then
      git -C "$repo" status --short
      echo "Refusing to record a dirty candidate revision: $repo" >&2
      return 1
    fi
  }

  assert_clean /Users/user/Development/fame-contracts || exit 1
  assert_clean /Users/user/Development/fls-www || exit 1

  printf 'fame-contracts revision: '
  git -C /Users/user/Development/fame-contracts rev-parse HEAD
  printf 'fls-www revision: '
  git -C /Users/user/Development/fls-www rev-parse HEAD
)
```

Use a reviewed `fame-contracts` commit. The production deployment state machine
pins that source and the exact release-profile artifacts, so do not change
contract sources, deployment code, public configuration, or compiler settings
between this rehearsal and the final deployment without rerunning the relevant
gates.

## 2. Run automated end-to-end fork coverage

First prove the receipt/recovery state machine locally:

```sh
yarn marketplace:deployment:test
```

Then run the complete environment-backed latest-Base campaign:

```sh
set -a
source config/fame-public.env
set +a

printf 'Configured checkout gas budget: %s\n' \
  "$BASE_UNIVERSAL_MARKETPLACE_CHECKOUT_GAS_BUDGET"

doppler run --config prd --only-secrets=RPC_URL -- sh -c '
  BASE_RPC="$RPC_URL" FOUNDRY_PROFILE=universal_marketplace \
    forge test --isolate \
      --match-contract "^(UniversalPoolArtMarketplaceForkBaseTest|FameMarketplaceCheckoutForkBaseTest|UniversalPoolArtMarketplaceContentionBaseTest)$" \
      --summary -vv
'
```

This campaign currently covers:

- latest-Base held, mint-pool, burn-pool, and rejected art-pool settlement;
- paused, stale-artwork, changed-premium, expired-quote, unavailable-shell, and
  competing-buyer rejection paths;
- a fresh paused marketplace plus checkout deployment, exact authorization,
  independent validation, deployer activation, an empty-market rejection, an
  eight-token provider batch, and the first configured routed checkout;
- the 88-provider worst-case payout campaign where each payout causes a DN404
  mint;
- ETH, WETH, and USDC checkout paths with complete settlement receipts, fee
  routing, refund behavior, and zero checkout residue/allowances;
- one-, multi-, and 32-Society redemption, direct-donation bonus consumption,
  and rollback of a failed redemption;
- immediate nonzero-premium and 24-hour zero-premium selected provider exits
  against the canonical forked FAME and Society contracts; and
- ordered and same-block contention with exactly one settlement.

The release-profile local provider, fuzz, and invariant suites retain the
boundary-level timestamp-decay coverage. A skipped, RPC-less, or partially
selected fork run is `not executed`, never green.

## 3. Start a fresh latest-state Base fork

In the first terminal:

```sh
set -a
source config/fame-public.env
set +a

doppler run --config prd --only-secrets=RPC_URL -- zsh -c '
  export BASE_RPC="$RPC_URL"
  FOUNDRY_PROFILE=universal_marketplace exec anvil --fork-url base --host 127.0.0.1 --port 8545 --chain-id "$BASE_CHAIN_ID" --quiet
'
```

Leave Anvil running. In a second `fame-contracts` terminal:

```sh
set -a
source config/fame-public.env
set +a

export LOCAL_BASE_RPC=http://127.0.0.1:8545
export RPC_URL="$LOCAL_BASE_RPC"
export MARKETPLACE_DEPLOYMENT_MODE=fork-rehearsal
export BASE_UNIVERSAL_MARKETPLACE_OWNER="$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER"

export FORK_BLOCK_NUMBER="$(cast block-number --rpc-url "$LOCAL_BASE_RPC")"
export FORK_BLOCK_HASH="$(cast block "$FORK_BLOCK_NUMBER" --field hash --rpc-url "$LOCAL_BASE_RPC")"
echo "Fork block: $FORK_BLOCK_NUMBER"
echo "Fork hash:  $FORK_BLOCK_HASH"
```

Record the block number and hash before mutating the fork.

## 4. Browser-testing Anvil helpers

Set any address to exactly 10 ETH:

```sh
cast rpc anvil_setBalance "<address>" 0x8AC7230489E80000 --rpc-url "$LOCAL_BASE_RPC"
```

Advance the fork by 24 hours and mine the new timestamp into one block:

```sh
cast rpc anvil_mine 0x1 0x15180 --rpc-url "$LOCAL_BASE_RPC"
```

The time-warp command is useful for mature provider exits and any other
timestamp-sensitive browser state. It advances the chain, not the operator's
wall clock. Repeat either one-liner with a different address or at another
point in the browser campaign as needed.

## 5. Deploy the paused marketplace and checkout

Give the configured deployer disposable fork gas and unlock it only on Anvil:

```sh
cast rpc anvil_setBalance "$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" 0x8AC7230489E80000 --rpc-url "$LOCAL_BASE_RPC"
cast rpc anvil_impersonateAccount "$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" --rpc-url "$LOCAL_BASE_RPC"
```

Build the exact release profile, then choose a new manifest path for this run.
Do not reuse a manifest from another Anvil process:

```sh
FOUNDRY_PROFILE=universal_marketplace forge build

export MARKETPLACE_DEPLOYMENT_RUN_DIR="$(
  mktemp -d "${TMPDIR:-/tmp}/base-universal-pool-art-marketplace-fork.XXXXXX"
)"
export MARKETPLACE_DEPLOYMENT_MANIFEST="$MARKETPLACE_DEPLOYMENT_RUN_DIR/manifest.json"
echo "Manifest path: $MARKETPLACE_DEPLOYMENT_MANIFEST"

FOUNDRY_PROFILE=universal_marketplace yarn marketplace:deployment prepare \
  "$MARKETPLACE_DEPLOYMENT_MANIFEST"

export BASE_UNIVERSAL_MARKETPLACE_ADDRESS="$(
  jq -er '.intent.marketplace' "$MARKETPLACE_DEPLOYMENT_MANIFEST"
)"
export BASE_FAME_MARKETPLACE_CHECKOUT_ADDRESS="$(
  jq -er '.intent.checkout' "$MARKETPLACE_DEPLOYMENT_MANIFEST"
)"
```

Review the two predicted addresses and the pinned source/compiler/artifact
facts. Advance exactly one nonce-pinned transaction per command, reconciling
from canonical receipts after each process boundary:

```sh
FOUNDRY_PROFILE=universal_marketplace yarn marketplace:deployment advance \
  "$MARKETPLACE_DEPLOYMENT_MANIFEST"
FOUNDRY_PROFILE=universal_marketplace yarn marketplace:deployment reconcile \
  "$MARKETPLACE_DEPLOYMENT_MANIFEST"

FOUNDRY_PROFILE=universal_marketplace yarn marketplace:deployment advance \
  "$MARKETPLACE_DEPLOYMENT_MANIFEST"
FOUNDRY_PROFILE=universal_marketplace yarn marketplace:deployment reconcile \
  "$MARKETPLACE_DEPLOYMENT_MANIFEST"

FOUNDRY_PROFILE=universal_marketplace yarn marketplace:deployment advance \
  "$MARKETPLACE_DEPLOYMENT_MANIFEST"
FOUNDRY_PROFILE=universal_marketplace yarn marketplace:deployment reconcile \
  "$MARKETPLACE_DEPLOYMENT_MANIFEST"

FOUNDRY_PROFILE=universal_marketplace yarn marketplace:deployment status \
  "$MARKETPLACE_DEPLOYMENT_MANIFEST"
```

The confirmed prefixes are marketplace deployed, checkout deployed, and
checkout authorized. Stop on any uncertain, replaced, reverted, or missing
receipt and reconcile the recorded sender plus nonce; never replay a confirmed
prefix.

Grant the marketplace its only CreatorMagic role, then validate the complete
paused stack independently:

```sh
cast send "$BASE_CREATOR_ARTIST_MAGIC_ADDRESS" \
  "grantRoles(address,uint256)" \
  "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" 4 \
  --from "$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" \
  --unlocked \
  --rpc-url "$LOCAL_BASE_RPC"

BASE_UNIVERSAL_MARKETPLACE_EXPECTED_PAUSED=true \
FOUNDRY_PROFILE=universal_marketplace forge script \
  script/ValidateBaseUniversalPoolArtMarketplace.s.sol:ValidateBaseUniversalPoolArtMarketplace \
  --rpc-url "$LOCAL_BASE_RPC"
```

## 6. Activate and prove the browser stack

Prepare and submit the separately receipt-bound deployer activation:

```sh
FOUNDRY_PROFILE=universal_marketplace yarn marketplace:deployment prepare-operation \
  "$MARKETPLACE_DEPLOYMENT_MANIFEST" deployer-activation

export ACTIVATION_OPERATION_ID="$(
  jq -er '.operations[-1].id' "$MARKETPLACE_DEPLOYMENT_MANIFEST"
)"

FOUNDRY_PROFILE=universal_marketplace yarn marketplace:deployment advance-operation \
  "$MARKETPLACE_DEPLOYMENT_MANIFEST" "$ACTIVATION_OPERATION_ID"

FOUNDRY_PROFILE=universal_marketplace yarn marketplace:deployment reconcile-operation \
  "$MARKETPLACE_DEPLOYMENT_MANIFEST" "$ACTIVATION_OPERATION_ID"
```

Validate the active deployer-owned stack and read back the minimum browser
preconditions:

```sh
BASE_UNIVERSAL_MARKETPLACE_EXPECTED_PAUSED=false \
FOUNDRY_PROFILE=universal_marketplace forge script \
  script/ValidateBaseUniversalPoolArtMarketplace.s.sol:ValidateBaseUniversalPoolArtMarketplace \
  --rpc-url "$LOCAL_BASE_RPC"

cast call "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" "paused()(bool)" --rpc-url "$LOCAL_BASE_RPC"
cast call "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" "owner()(address)" --rpc-url "$LOCAL_BASE_RPC"
cast call "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" "authorizedCheckout()(address)" --rpc-url "$LOCAL_BASE_RPC"
cast code "$BASE_FAME_MARKETPLACE_CHECKOUT_ADDRESS" --rpc-url "$LOCAL_BASE_RPC"
```

`paused()` must be `false`, the owner must remain the configured deployer, the
authorized checkout must equal the manifest checkout, and checkout code must be
nonempty. `FameMarketplaceCheckout` has no independent pause switch; an active
authorized marketplace is what makes the deployed checkout usable.

## 7. Start `fls-www` and test in the browser

In a `fls-www` terminal, pass the loopback RPC and both temporary addresses
through to server and browser code:

```sh
cd /Users/user/Development/fls-www

export LOCAL_BASE_RPC=http://127.0.0.1:8545
export BASE_RPC_URL="$LOCAL_BASE_RPC"
export NEXT_PUBLIC_BASE_RPC_URL_1="$LOCAL_BASE_RPC"
export NEXT_PUBLIC_FAME_FORK_MODE=1
export NEXT_PUBLIC_BASE_UNIVERSAL_MARKETPLACE_ADDRESS="<manifest marketplace address>"
export NEXT_PUBLIC_BASE_FAME_CHECKOUT_ADDRESS="<manifest checkout address>"

doppler run \
  --preserve-env="BASE_RPC_URL,NEXT_PUBLIC_BASE_RPC_URL_1,NEXT_PUBLIC_FAME_FORK_MODE,NEXT_PUBLIC_BASE_UNIVERSAL_MARKETPLACE_ADDRESS,NEXT_PUBLIC_BASE_FAME_CHECKOUT_ADDRESS" \
  -- yarn dev
```

Configure each test wallet's Base network RPC as
`http://127.0.0.1:8545`. Base mainnet and the fork both report chain ID `8453`,
so chain ID alone is not proof that the wallet is using Anvil. Immediately
before the first signature, print Anvil's current latest block hash in the
`fame-contracts` terminal:

```sh
export PRE_SIGN_LOCAL_BLOCK_HASH="$(
  cast block latest --field hash --rpc-url "$LOCAL_BASE_RPC"
)"
echo "Pre-sign local block hash: $PRE_SIGN_LOCAL_BLOCK_HASH"
```

Then run this one-liner in the browser console, replacing the placeholder with
the printed hash:

```js
await (async (expected) => { const block = await window.ethereum.request({ method: "eth_getBlockByNumber", params: ["latest", false] }); return { local: expected, wallet: block.hash, matches: block.hash.toLowerCase() === expected.toLowerCase() }; })("<PRE_SIGN_LOCAL_BLOCK_HASH>")
```

Do not sign unless `matches` is `true` and the displayed `local` and `wallet`
hashes are identical. If Anvil mines another block before signing, repeat both
reads. Stop on any mismatch and record the two hashes and result in the evidence
table. Once this proof passes, open `/fame/market` directly or use the `FAME
Marketplace` menu item.

All remaining provider, staking, unstaking, marketplace checkout, Society
redemption, wallet rejection, and product-state testing is browser-led. Use the
10-ETH and 24-hour helpers above when needed. This runbook deliberately does
not prescribe feature-by-feature transaction sequences or duplicate the UI's
workflow.

## 8. Record evidence and tear down

Record only the facts needed to judge the final deployment candidate:

| Evidence | Result |
|---|---|
| `fame-contracts` revision | |
| `fls-www` revision | |
| Fork block number and hash | |
| Deployment state-machine tests | |
| Latest-Base automated fork campaign | |
| 88-provider checkout gas and configured budget | |
| Manifest path and final status | |
| Temporary marketplace address | |
| Temporary checkout address | |
| Paused validation | |
| Active validation | |
| Active owner and authorized-checkout read-back | |
| WWW started with loopback-only fork overrides | |
| Injected-wallet latest block hash equals local Anvil | |
| Browser campaign result and issue links | |
| Wallet RPC restored and fork stopped | |

When testing ends—or immediately after an uncertain receipt or loss of the
local node—stop `fls-www`, stop Anvil, and restore every test wallet's normal
Base RPC. The manifest is a recovery journal only for this exact Anvil process.
If the fork is lost, keep the manifest only as failure evidence and start a new
fork with a new manifest path.

This rehearsal authorizes no production write, deployment, activation,
ownership transfer, Safe transaction, or public configuration publication.
