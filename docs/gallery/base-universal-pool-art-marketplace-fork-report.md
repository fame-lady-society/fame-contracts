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
export NEXT_PUBLIC_FAME_FORK_ACCOUNT="<disposable impersonated address>"
export NEXT_PUBLIC_FAME_FORK_METADATA_FALLBACK=1
export NEXT_PUBLIC_BASE_UNIVERSAL_MARKETPLACE_ADDRESS="<temporary address from the Forge terminal>"
export NEXT_PUBLIC_BASE_FAME_CHECKOUT_ADDRESS="<temporary checkout address from the Forge terminal>"

yarn dev
```

Connect only a disposable wallet configured for chain ID `8453` and RPC
`http://127.0.0.1:8545`. Open `/fame/gallery` directly; the route is
intentionally absent from the app menus. The fork-only app mode must reject
non-loopback RPCs, disable public Base fallbacks, and bypass the external
indexed quote service. The mock connector and local metadata fallback are both
explicit fork-test aids; leave their environment variables unset everywhere
else.

Do not begin the browser campaign until the route and fork-only quote mode are
implemented and their focused checks pass.

## 7. Evidence and teardown

This template records concise run facts. It is not a persisted session journal,
deployment manifest, or authorization for production.

| Evidence | Result |
|---|---|
| `fame-contracts` checkout baseline | `bae7c1f` |
| `fls-www` gallery baseline | `fbd2a88`, plus the fork harness and browser fixes recorded by the campaign |
| Fork block number | `49392666` |
| Fork block hash | `0x1637485978b2c48bf27782e8e1dc585851a76fc61ff14d125d998bdc41ec7d5d` |
| Paused deployment and checkout authorization | Passed on the disposable fork |
| Paused validation | Passed |
| Active validation | Passed |
| Temporary addresses | Intentionally omitted; localhost fork only |
| Direct FAME held purchase | Passed in the browser |
| Native ETH pool checkout | Passed atomically; zero retained checkout balance |
| USDC pool checkout | Passed atomically; zero retained checkout balance |
| WETH held checkout | Passed atomically; zero retained checkout balance |
| Direct FAME purchase | `0xcb1cf62cdad15177c7828c35757a412db633e645cf84d3398e22ae55f150b572` |
| ETH checkout / route | `0x8fe371095f496e528fd3dbf95fb546a0706c1a51e3d91bd9d33913f0329b663e` / `0x941a35a1a857158ae525d3cb08120682d8b81d2ab88d5cd98ff789167f6448be` |
| USDC checkout / route | `0x0473c7922105197ad0b247d031d831ea7a49b0f8088422b256437b27802da921` / `0x1fdbb62f0ad3e0e13c9d9ae8f947f1a4b8493676de056422fa98cb2ba153c742` |
| WETH checkout / route | `0x0c612ba1a7c356f5ed053d6f034062758dd70f76d4b9fa08c0063eb41bfb0550` / `0x2b80d0a7738f992a1fd2c73089b77ba638c557bd132be07803884aa9cac71593` |
| Buyer refund accounting | Each checkout returned excess FAME; selected routes had zero input residue |
| Checkout mirror custody | Zero after the campaign |
| One-shell contention | Passed in the contract fork suite: one winner, one losing buyer |
| Teardown and wallet reset | Required after the local campaign |

The automated checkout gate ran against the deployed router and latest Base
state on 2026-08-01. ETH-held, USDC-Mint-pool, WETH-Burn-pool, premium-race,
expired-quote, and same-shell-contention cases passed at fork head `49392705`,
hash
`0x6891ce9282e1a979c4f274524c56bf5e8e2fd3c73d19b85b0af7385cdb622a8c`.
This is contract-level fork evidence; it is not the browser campaign and does
not create reusable deployment addresses.

When the run ends—or immediately after a reload, uncertain transaction, or
local-node failure—stop `fls-www`, stop Anvil, remove the localhost network from
or reset the disposable wallet, and close the shells containing the temporary
address. Do not copy the address or Foundry `broadcast/` output into tracked
configuration.

Production inventory funding, the three-unit production transfer, live
marketplace/checkout deployment, live activation and testing, and the later
7-of-14 Safe ownership handoff are all deferred.
