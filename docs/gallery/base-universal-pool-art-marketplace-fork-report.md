---
chain: base-fork
status: operator-template
contracts: UniversalPoolArtMarketplace + FameMarketplaceCheckout
---

# Base Universal Pool Art Marketplace Fork Run

This is a disposable local rehearsal, not a deployment procedure. Every command
that sends a transaction below must target the literal loopback RPC
`http://127.0.0.1:8545`. Never substitute a Base RPC, load a production key,
commit the temporary marketplace or checkout address, or preserve Foundry
`broadcast/` output.

Run Anvil, the Forge lifecycle, optional wagmi generation, and `fls-www` as
independent commands. If the page reloads while a transaction is pending, a
receipt is uncertain, or the local node is lost, stop. Discard the fork, reset
the disposable wallet, and start a new run. There is no recovery journal.

## 1. Start a latest-state Base fork

From `fame-contracts`, load public configuration before Doppler. This maps the
existing Doppler `RPC_URL` fallback to the `base` Foundry alias without printing
the secret RPC:

```sh
set -a
source config/fame-public.env
set +a

doppler run --config prd -- zsh -c '
  export BASE_RPC="${BASE_RPC:-${RPC_URL:?Doppler must provide BASE_RPC or RPC_URL}}"
  exec anvil --fork-url base --host 127.0.0.1 --port 8545 --chain-id "$BASE_CHAIN_ID" --quiet
'
```

Leave Anvil running in that terminal. In a second `fame-contracts` terminal,
load the public configuration and define only disposable shell state:

```sh
set -a
source config/fame-public.env
set +a

export LOCAL_BASE_RPC=http://127.0.0.1:8545
export FAME_UNIT=1000000000000000000000000
export CREATOR_MAGIC_BANISHER_ROLE=4

export FORK_BLOCK_NUMBER="$(cast block-number --rpc-url "$LOCAL_BASE_RPC")"
export FORK_BLOCK_HASH="$(cast block "$FORK_BLOCK_NUMBER" --field hash --rpc-url "$LOCAL_BASE_RPC")"
echo "Fork block: $FORK_BLOCK_NUMBER"
echo "Fork hash:  $FORK_BLOCK_HASH"
```

Copy the block number and hash into the evidence table below. They describe the
latest Base state selected when this Anvil process started; they are not a fork
proof or a browser guard.

## 2. Fund and impersonate only on Anvil

The Safe supplies exactly one FAME unit to the deployer for this fork. Give the
Safe and deployer disposable gas, impersonate both accounts, transfer the unit,
then stop impersonating the Safe. Keep the deployer impersonated through
deployment, role grant, seeding, and activation:

```sh
cast rpc anvil_setBalance "$BASE_UNIVERSAL_MARKETPLACE_SEED_SOURCE" 0x56BC75E2D63100000 --rpc-url "$LOCAL_BASE_RPC"
cast rpc anvil_setBalance "$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" 0x56BC75E2D63100000 --rpc-url "$LOCAL_BASE_RPC"

cast rpc anvil_impersonateAccount "$BASE_UNIVERSAL_MARKETPLACE_SEED_SOURCE" --rpc-url "$LOCAL_BASE_RPC"
cast rpc anvil_impersonateAccount "$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" --rpc-url "$LOCAL_BASE_RPC"
cast send "$BASE_FAME_ADDRESS" \
  "transfer(address,uint256)(bool)" \
  "$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" \
  "$FAME_UNIT" \
  --from "$BASE_UNIVERSAL_MARKETPLACE_SEED_SOURCE" \
  --unlocked \
  --rpc-url "$LOCAL_BASE_RPC"
cast rpc anvil_stopImpersonatingAccount "$BASE_UNIVERSAL_MARKETPLACE_SEED_SOURCE" --rpc-url "$LOCAL_BASE_RPC"
```

Record the transfer hash from `cast send`. No fork-fixture preflight or
production funding decision is required.

## 3. Deploy and wire the paused checkout stack

The Solidity script validates the deployed router, deploys the marketplace and
ownerless checkout, then configures the checkout while the marketplace is
paused. Predict both CREATE addresses from the current fork nonce, export them
only in this shell, then run the script through the unlocked deployer account:

```sh
export DEPLOYER_NONCE="$(cast nonce "$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" --rpc-url "$LOCAL_BASE_RPC")"
export BASE_UNIVERSAL_MARKETPLACE_ADDRESS="$(
  cast compute-address "$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" --nonce "$DEPLOYER_NONCE" |
    sed 's/^Computed Address: //'
)"
export CHECKOUT_NONCE="$((DEPLOYER_NONCE + 1))"
export BASE_FAME_MARKETPLACE_CHECKOUT_ADDRESS="$(
  cast compute-address "$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" --nonce "$CHECKOUT_NONCE" |
    sed 's/^Computed Address: //'
)"

forge script script/DeployBaseUniversalPoolArtMarketplace.s.sol:DeployBaseUniversalPoolArtMarketplace \
  --rpc-url "$LOCAL_BASE_RPC" \
  --sender "$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" \
  --unlocked \
  --broadcast

cast code "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" --rpc-url "$LOCAL_BASE_RPC"
cast code "$BASE_FAME_MARKETPLACE_CHECKOUT_ADDRESS" --rpc-url "$LOCAL_BASE_RPC"
cast call "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" \
  "authorizedCheckout()(address)" \
  --rpc-url "$LOCAL_BASE_RPC"
```

The read-back checkout must exactly equal
`BASE_FAME_MARKETPLACE_CHECKOUT_ADDRESS`. Do not add either temporary address to
`config/fame-public.env`, `contracts.ts`, a manifest, or a generated file.
Record both deployment transaction hashes and the wiring transaction hash in
the evidence table.

## 4. Grant BANISHER and seed one shell

CreatorMagic is owned by the deployer at the accepted Base state. Using the
already impersonated deployer, grant only role bit `4` (`BANISHER`) and
transfer exactly one FAME unit into the marketplace:

```sh
cast send "$BASE_CREATOR_ARTIST_MAGIC_ADDRESS" \
  "grantRoles(address,uint256)" \
  "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" \
  "$CREATOR_MAGIC_BANISHER_ROLE" \
  --from "$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" \
  --unlocked \
  --rpc-url "$LOCAL_BASE_RPC"

cast send "$BASE_FAME_ADDRESS" \
  "transfer(address,uint256)(bool)" \
  "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" \
  "$FAME_UNIT" \
  --from "$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" \
  --unlocked \
  --rpc-url "$LOCAL_BASE_RPC"
```

Record both transaction hashes.

## 5. Validate paused, activate, and validate active

The validator performs the detailed canonical-stack, ownership, premium,
inventory, pause, skip-NFT, narrow-role, mutual marketplace/checkout wiring,
checkout immutable, router fee, allowlist, fixture, and live-pool reads. It does
not add checks to either runtime contract.

```sh
export BASE_UNIVERSAL_MARKETPLACE_EXPECTED_PAUSED=true

forge script script/ValidateBaseUniversalPoolArtMarketplace.s.sol:ValidateBaseUniversalPoolArtMarketplace \
  --rpc-url "$LOCAL_BASE_RPC"

forge script script/ActivateBaseUniversalPoolArtMarketplace.s.sol:ActivateBaseUniversalPoolArtMarketplace \
  --rpc-url "$LOCAL_BASE_RPC" \
  --sender "$BASE_UNIVERSAL_MARKETPLACE_OWNER" \
  --unlocked \
  --broadcast

export BASE_UNIVERSAL_MARKETPLACE_EXPECTED_PAUSED=false

forge script script/ValidateBaseUniversalPoolArtMarketplace.s.sol:ValidateBaseUniversalPoolArtMarketplace \
  --rpc-url "$LOCAL_BASE_RPC"

cast rpc anvil_stopImpersonatingAccount "$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" --rpc-url "$LOCAL_BASE_RPC"
```

The successful prefix is one active shell, deployer ownership, the configured
Safe as fee recipient, and `BANISHER` as the marketplace's only CreatorMagic
role. There is no Safe ownership handoff in this run.

## 6. Start `fls-www` separately

Run wagmi generation only when the ABI bindings need refreshing:

```sh
cd /Users/user/Development/fls-www
yarn wagmi generate
```

Then start the app in another `fls-www` terminal. Supply the same literal
loopback RPC to both server and browser code, enable fork-only quote routing,
and pass the temporary marketplace address through the shell:

```sh
export LOCAL_BASE_RPC=http://127.0.0.1:8545
export BASE_RPC_URL="$LOCAL_BASE_RPC"
export NEXT_PUBLIC_BASE_RPC_URL_1="$LOCAL_BASE_RPC"
export NEXT_PUBLIC_FAME_FORK_MODE=1
export NEXT_PUBLIC_BASE_UNIVERSAL_MARKETPLACE_ADDRESS="<temporary address from the Forge terminal>"
export NEXT_PUBLIC_BASE_FAME_MARKETPLACE_CHECKOUT_ADDRESS="<temporary checkout address from the Forge terminal>"

yarn dev
```

Connect only a disposable wallet configured for chain ID `8453` and RPC
`http://127.0.0.1:8545`. Open `/fame/gallery` directly; the route is
intentionally absent from the app menus. The fork-only app mode must reject
non-loopback RPCs, disable public Base fallbacks, and bypass the external
indexed quote service.

Do not begin the browser campaign until the route and fork-only quote mode are
implemented and their focused checks pass.

## 7. Evidence and teardown

This template records concise run facts. It is not a persisted session journal,
deployment manifest, or authorization for production.

| Evidence | Result |
|---|---|
| `fame-contracts` revision | `f1b8a09` |
| `fls-www` revision | `dd6fe40` |
| Fork block number | `49036128` |
| Fork block hash | `0x026d26767901eb3de48a30791d75325138851c184bd71224e10c66c7d3f88b83` |
| Safe-to-deployer one-unit transfer | `0x32be8730ecd8ce828d2ecfa300e3a9bb3653e81bba8731e027cc0441831dd657` |
| Paused marketplace deployment | `0xb6f140784b239e238dfb0736311f03d40c7cbd56f0ed6cb61f0190e05423127b` |
| Paused checkout deployment and authorization | Not recorded in the earlier direct-FAME run |
| BANISHER grant | `0xcf6bd66c10350f8dbc0e87e740bfd4784c978f295a58e7a9e2509d58d3b20a94` |
| One-unit shell seed | `0x6ab71fc3cb5a0b7545bc16a89cb4eac1af99e390e3ae5a18b5cb280b618230d7` |
| Paused validation | Passed |
| Activation transaction | `0xacf778282674a62f789745803f8b79a26be7738ed060caa7793e96326e6bd13a` |
| Active validation | Passed, including exact BANISHER-only role bitmap after review |
| Temporary marketplace address | `0x54e7E4F2d439Be599706f51068f7EB2ce2D2a27e`; localhost fork only |
| Temporary checkout address | Not deployed in the earlier direct-FAME run |
| Browser route and metadata | 92 purchasable artworks; 0 unavailable cards; direct browser metadata |
| Local quote preview | Indexed helper bypassed; local optimizer timed out before producing a safe executable quote |
| Direct-FAME browser campaign | Not run |
| ETH acquisition and purchase | Not run |
| USDC acquisition and purchase | Not run |
| Fork-visible WETH route | Not evaluated |
| One-shell contention | Passed in the latest-state Base fork suite: one winner, one losing buyer |
| Teardown and wallet reset | Pending |

The automated checkout gate ran against the deployed router and latest Base
state on 2026-08-01. ETH-held, USDC-Mint-pool, WETH-Burn-pool, premium-race,
expired-quote, and same-shell-contention cases passed across fork blocks
`49391151` and `49391188`. This is contract-level fork evidence; it is not the
browser campaign and does not create reusable deployment addresses.

When the run ends—or immediately after a reload, uncertain transaction, or
local-node failure—stop `fls-www`, stop Anvil, remove the localhost network from
or reset the disposable wallet, and close the shells containing the temporary
address. Do not copy the address or Foundry `broadcast/` output into tracked
configuration.

Production inventory funding, the three-unit production transfer, live
marketplace/checkout deployment, live activation and testing, and the later
7-of-14 Safe ownership handoff are all deferred.
