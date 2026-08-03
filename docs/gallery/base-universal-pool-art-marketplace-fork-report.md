---
chain: base-fork
status: ready-for-manual-provider-rehearsal
contracts: UniversalPoolArtMarketplace + FameMarketplaceCheckout
---

# Base Universal Pool Art Marketplace Fork Run

This is a disposable local rehearsal, not a deployment procedure. Every command
that sends a transaction below must target the literal loopback RPC
`http://127.0.0.1:8545`. Never substitute a Base RPC, load a production key,
commit the temporary marketplace or checkout address, or preserve Foundry
`broadcast/` output.

This runbook now includes the Society inventory-provider acceptance pass. The
contract release suite must be green before starting Anvil:

```sh
set -a
source config/fame-public.env
set +a

doppler run --config prd -- sh -c '
  BASE_RPC="$RPC_URL" FOUNDRY_PROFILE=universal_marketplace \
    forge test --isolate \
      --match-contract "^(UniversalPoolArtMarketplaceForkBaseTest|FameMarketplaceCheckoutForkBaseTest|UniversalPoolArtMarketplaceContentionBaseTest)$" \
      --summary
'
```

The required automated result includes the configured 88-provider all-mint
checkout, the full 888-ID free-exit scan, and
`testLatestBaseReleaseLifecycleDeploysValidatesActivatesAndHandsOff`, which now
credits the maximum eight-token provider batch before validation and handoff. A
skipped or RPC-less run is not green. These are fork simulations only; they do
not authorize a Base transaction.

Run Anvil, the Forge lifecycle, optional wagmi generation, and `fls-www` as
independent commands. If the page reloads while a transaction is pending, a
receipt is uncertain, or the local node is lost, stop. Discard the fork, reset
the operator test wallet's fork connection, and start a new run. There is no
recovery journal.

## 1. Start a latest-state Base fork

From `fame-contracts`, load public configuration before Doppler. The `prd`
config supplies the Base mainnet `RPC_URL`; the Doppler subshell maps it to the
`BASE_RPC` variable used by the `base` Foundry alias without printing the
secret RPC:

```sh
set -a
source config/fame-public.env
set +a

doppler run --config prd -- zsh -c '
  export BASE_RPC="$RPC_URL"
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

```

The successful prefix is at least one active shell, deployer ownership, the
configured Safe as fee recipient, the configured immutable provider cap of
`88`, and `BANISHER` as the marketplace's only CreatorMagic role. Validation
also checks the live provider array, indexes, and unit total rather than
requiring an empty provider set, because deposits and direct donations remain
open while checkout is paused. Keep deployer impersonation available until the
final paused ownership-handoff rehearsal in section 8.

## 6. Start `fls-www` separately

Run wagmi generation only when the ABI bindings need refreshing:

```sh
cd /Users/user/Development/fls-www
doppler run --config prd -- yarn wagmi generate
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
export NEXT_PUBLIC_BASE_FAME_CHECKOUT_ADDRESS="<temporary checkout address from the Forge terminal>"

doppler run --config prd \
  --preserve-env="BASE_RPC_URL,NEXT_PUBLIC_BASE_RPC_URL_1,NEXT_PUBLIC_FAME_FORK_MODE,NEXT_PUBLIC_BASE_UNIVERSAL_MARKETPLACE_ADDRESS,NEXT_PUBLIC_BASE_FAME_CHECKOUT_ADDRESS" \
  -- yarn dev
```

The explicit `--preserve-env` list lets Doppler supply the rest of WWW's local
configuration without replacing the five fork overrides exported above. Do not
use `--preserve-env=true`; preserve only these public, fork-scoped values.

Connect an operator-owned test account through the normal injected wallet
connector. Configure that wallet's Base RPC as `http://127.0.0.1:8545` before
connecting. Because both the fork and Base mainnet use chain ID `8453`, confirm
the wallet's active RPC endpoint before signing; chain ID alone cannot
distinguish them. Open `/fame/gallery` directly or use the `FAME Marketplace`
menu item. The fork-only app mode must reject non-loopback RPCs, disable public
Base fallbacks, and bypass the external indexed quote service.
Artwork metadata must use the normal token URI loading path during the campaign.

Do not begin the browser campaign until the route and fork-only quote mode are
implemented and their focused checks pass.

## 7. Seed the operator wallet and run Society redemption

Use the same normal wallet account that will sign in the browser. The address
needs ETH only on Anvil; no private key or mock connector belongs in WWW:

```sh
export FORK_BUYER="<operator-owned wallet address>"

cast rpc anvil_setBalance "$FORK_BUYER" 0x56BC75E2D63100000 --rpc-url "$LOCAL_BASE_RPC"
cast rpc anvil_impersonateAccount "$FORK_BUYER" --rpc-url "$LOCAL_BASE_RPC"
cast send "$BASE_FAME_ADDRESS" \
  "setSkipNFT(bool)" \
  false \
  --from "$FORK_BUYER" \
  --unlocked \
  --rpc-url "$LOCAL_BASE_RPC"
cast rpc anvil_stopImpersonatingAccount "$FORK_BUYER" --rpc-url "$LOCAL_BASE_RPC"
```

If the wallet does not already own enough Society NFTs at the forked block,
seed it from real fork holders. Choose an ID whose `ownerAt` result is neither
zero nor the temporary marketplace, then repeat this block for every required
ID. These are fork-only setup transfers; approval and redemption remain normal
wallet-signed browser transactions:

```sh
export SOCIETY_TOKEN_ID="<1 through 888>"
export SOCIETY_OWNER="$(
  cast call "$BASE_FAME_NFT_ADDRESS" \
    "ownerAt(uint256)(address)" \
    "$SOCIETY_TOKEN_ID" \
    --rpc-url "$LOCAL_BASE_RPC"
)"

cast rpc anvil_setBalance "$SOCIETY_OWNER" 0xDE0B6B3A7640000 --rpc-url "$LOCAL_BASE_RPC"
cast rpc anvil_impersonateAccount "$SOCIETY_OWNER" --rpc-url "$LOCAL_BASE_RPC"
cast send "$BASE_FAME_NFT_ADDRESS" \
  "transferFrom(address,address,uint256)" \
  "$SOCIETY_OWNER" \
  "$FORK_BUYER" \
  "$SOCIETY_TOKEN_ID" \
  --from "$SOCIETY_OWNER" \
  --unlocked \
  --rpc-url "$LOCAL_BASE_RPC"
cast rpc anvil_stopImpersonatingAccount "$SOCIETY_OWNER" --rpc-url "$LOCAL_BASE_RPC"
```

Seed 42 transferable IDs to execute the complete matrix below without reusing
an NFT: three one-ID runs, three two-ID runs, one 32-ID run, and one direct
checkout donation. To create the pre-funded bonus, transfer the extra ID to
`BASE_FAME_MARKETPLACE_CHECKOUT_ADDRESS` instead of `FORK_BUYER`. Because the
checkout is in skip-NFT mode, that ID becomes one unit of checkout FAME and is
included in the next successful redemption.

Reload `/fame/gallery` with the wallet connected to the literal loopback Base
RPC. Ownership discovery starts while `Your Society NFTs` is collapsed. Open
the accordion and confirm its ascending ID list matches both the checkout read
and the mirror balance:

```sh
cast call "$BASE_FAME_MARKETPLACE_CHECKOUT_ADDRESS" \
  "ownedSocietyTokenIds(address,uint256,uint256)(uint256[])" \
  "$FORK_BUYER" \
  1 \
  889 \
  --rpc-url "$LOCAL_BASE_RPC"

cast call "$BASE_FAME_NFT_ADDRESS" \
  "balanceOf(address)(uint256)" \
  "$FORK_BUYER" \
  --rpc-url "$LOCAL_BASE_RPC"
```

Run this browser matrix. The first run should show `Approve NFT redemption`,
wait for one confirmation, and stop without submitting redemption. Review the
selected IDs, estimate, minimum output, and irreversible-burn copy, then click
`Burn N NFTs` yourself. Later rows should reuse the operator approval.

| Selection | Receive | Bonus expectation |
|---|---|---|
| 1 ID | ETH | Shows and consumes the pre-funded checkout bonus |
| 1 ID | WETH | No bonus row after the first success |
| 1 ID | USDC | No bonus row after the first success |
| 2 IDs | ETH | Exact selected IDs only |
| 2 IDs | WETH | Exact selected IDs only |
| 2 IDs | USDC | Exact selected IDs only |
| 32 IDs | WETH | Record receipt gas and compare with the fork block gas limit |

After every success, wait for one confirmation and verify the selected IDs are
gone, the wallet output balance increased, and both checkout inventories are
zero. Record the transaction hash, selected IDs, quote-basis and actual FAME,
route hash, output, and receipt gas from the standard transaction modal and
receipt. The decisive post-state reads are:

```sh
cast call "$BASE_FAME_ADDRESS" \
  "balanceOf(address)(uint256)" \
  "$BASE_FAME_MARKETPLACE_CHECKOUT_ADDRESS" \
  --rpc-url "$LOCAL_BASE_RPC"

cast call "$BASE_FAME_NFT_ADDRESS" \
  "balanceOf(address)(uint256)" \
  "$BASE_FAME_MARKETPLACE_CHECKOUT_ADDRESS" \
  --rpc-url "$LOCAL_BASE_RPC"
```

Both must return zero. Wallet rejection, simulation failure, or mined revert is
recorded once; do not retry automatically or invent a recovery flow.

## 8. Rehearse providers, checkout-only pause, and ownership handoff

Use two disposable provider wallets. Give provider A two real Society NFTs and
provider B one using the owner-transfer procedure in section 7, and give both
wallets Anvil ETH. Keep the provider wallets distinct from the buyer and from
the Society Safe. Provider A uses the frontend-friendly batch path: one
`setApprovalForAll` approval followed by one atomic `depositInventoryBatch`
transaction. Provider B preserves evidence for the original single-token path:

```sh
export FORK_PROVIDER_A="<first disposable provider wallet>"
export FORK_PROVIDER_B="<second disposable provider wallet>"
export PROVIDER_A_ID_1="<first Society ID transferred to provider A>"
export PROVIDER_A_ID_2="<second Society ID transferred to provider A>"
export PROVIDER_B_ID="<Society ID transferred to provider B>"

for PROVIDER in "$FORK_PROVIDER_A" "$FORK_PROVIDER_B"; do
  cast rpc anvil_setBalance "$PROVIDER" 0x56BC75E2D63100000 --rpc-url "$LOCAL_BASE_RPC"
  cast rpc anvil_impersonateAccount "$PROVIDER" --rpc-url "$LOCAL_BASE_RPC"
done

cast send "$BASE_FAME_NFT_ADDRESS" \
  "setApprovalForAll(address,bool)" \
  "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" true \
  --from "$FORK_PROVIDER_A" --unlocked --rpc-url "$LOCAL_BASE_RPC"
cast send "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" \
  "depositInventoryBatch(uint256[])" "[$PROVIDER_A_ID_1,$PROVIDER_A_ID_2]" \
  --from "$FORK_PROVIDER_A" --unlocked --rpc-url "$LOCAL_BASE_RPC"

cast send "$BASE_FAME_NFT_ADDRESS" \
  "approve(address,uint256)" \
  "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" \
  "$PROVIDER_B_ID" \
  --from "$FORK_PROVIDER_B" --unlocked --rpc-url "$LOCAL_BASE_RPC"
cast send "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" \
  "depositInventory(uint256)" "$PROVIDER_B_ID" \
  --from "$FORK_PROVIDER_B" --unlocked --rpc-url "$LOCAL_BASE_RPC"
```

Read back both direct positions. Provider A must report two units, provider B
must report one, and both must have a nonzero index. The active-provider count
must be `2`, while total provider units must be `3`:

```sh
cast call "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" \
  "providerPosition(address)(uint256,uint256)" "$FORK_PROVIDER_A" \
  --rpc-url "$LOCAL_BASE_RPC"
cast call "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" \
  "providerPosition(address)(uint256,uint256)" "$FORK_PROVIDER_B" \
  --rpc-url "$LOCAL_BASE_RPC"
cast call "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" \
  "activeProviderCount()(uint256)" --rpc-url "$LOCAL_BASE_RPC"
cast call "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" \
  "totalProviderUnits()(uint256)" --rpc-url "$LOCAL_BASE_RPC"
```

For visible payout evidence on the disposable fork, set a nonzero provider fee
from the deployer, then complete one normal browser checkout from section 6.
`1,000 FAME` is well below the 10% component cap:

```sh
export FORK_PROVIDER_FEE=1000000000000000000000
cast send "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" \
  "setProviderFee(uint256)" "$FORK_PROVIDER_FEE" \
  --from "$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" \
  --unlocked --rpc-url "$LOCAL_BASE_RPC"
```

Before and after checkout, record both provider FAME balances, the Safe balance,
`premium()`, inventory, and both positions. The provider component must split
2:1 according to the positions, provider rounding dust and the community
component must reach the Safe, the checkout must retain no FAME or allowance,
and neither position may change.

Next, prove selected exit has no self-rebate. Use the checkout helper to scan
the marketplace's current live IDs after the purchase, select any returned ID,
and fund provider A with exactly the current premium on Anvil:

```sh
cast call "$BASE_FAME_MARKETPLACE_CHECKOUT_ADDRESS" \
  "ownedSocietyTokenIds(address,uint256,uint256)(uint256[])" \
  "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" 1 889 \
  --rpc-url "$LOCAL_BASE_RPC"

export SELECTED_POOL_ID="<one ID returned above>"
cast call "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" \
  "premium()(uint256)" --rpc-url "$LOCAL_BASE_RPC"
export CURRENT_PREMIUM="<raw uint256 before the bracketed display value>"

cast rpc anvil_impersonateAccount "$BASE_UNIVERSAL_MARKETPLACE_SEED_SOURCE" --rpc-url "$LOCAL_BASE_RPC"
cast send "$BASE_FAME_ADDRESS" \
  "transfer(address,uint256)(bool)" "$FORK_PROVIDER_A" "$CURRENT_PREMIUM" \
  --from "$BASE_UNIVERSAL_MARKETPLACE_SEED_SOURCE" \
  --unlocked --rpc-url "$LOCAL_BASE_RPC"
cast rpc anvil_stopImpersonatingAccount "$BASE_UNIVERSAL_MARKETPLACE_SEED_SOURCE" --rpc-url "$LOCAL_BASE_RPC"

cast send "$BASE_FAME_ADDRESS" \
  "approve(address,uint256)(bool)" \
  "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" "$CURRENT_PREMIUM" \
  --from "$FORK_PROVIDER_A" --unlocked --rpc-url "$LOCAL_BASE_RPC"
cast send "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" \
  "withdrawInventorySelected(uint256,uint256)" \
  "$SELECTED_POOL_ID" "$CURRENT_PREMIUM" \
  --from "$FORK_PROVIDER_A" --unlocked --rpc-url "$LOCAL_BASE_RPC"
```

Provider A must remain with exactly one credited unit. Its exiting unit is
removed before distribution and its wallet receives no provider-fee rebate;
provider B receives its one-unit weighted share. The Safe receives the
community component, provider A's excluded share, and any rounding dust.

Pause checkout and prove custody remains open. Both providers' free exits must
succeed while paused and return whichever live IDs the contract selects. Each
exit removes the wallet's final position; together they reduce the
active-provider count to zero:

```sh
cast send "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" "pause()" \
  --from "$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" \
  --unlocked --rpc-url "$LOCAL_BASE_RPC"
cast send "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" "withdrawInventory()" \
  --from "$FORK_PROVIDER_A" --unlocked --rpc-url "$LOCAL_BASE_RPC"
cast send "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" "withdrawInventory()" \
  --from "$FORK_PROVIDER_B" --unlocked --rpc-url "$LOCAL_BASE_RPC"
```

Finally rehearse the one-way owner transition only on this disposable fork.
CreatorArtistMagic ownership intentionally stays with the deployer; only the
marketplace owner becomes the Society Safe:

```sh
cast send "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" \
  "transferOwnership(address)" "$BASE_UNIVERSAL_MARKETPLACE_FUTURE_OWNER" \
  --from "$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" \
  --unlocked --rpc-url "$LOCAL_BASE_RPC"

export BASE_UNIVERSAL_MARKETPLACE_OWNER="$BASE_UNIVERSAL_MARKETPLACE_FUTURE_OWNER"
export BASE_UNIVERSAL_MARKETPLACE_EXPECTED_PAUSED=true
forge script script/ValidateBaseUniversalPoolArtMarketplace.s.sol:ValidateBaseUniversalPoolArtMarketplace \
  --rpc-url "$LOCAL_BASE_RPC"
```

Stop impersonating both provider wallets and the deployer after validation:

```sh
for PROVIDER in "$FORK_PROVIDER_A" "$FORK_PROVIDER_B"; do
  cast rpc anvil_stopImpersonatingAccount "$PROVIDER" --rpc-url "$LOCAL_BASE_RPC"
done
cast rpc anvil_stopImpersonatingAccount "$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" --rpc-url "$LOCAL_BASE_RPC"
```

Never copy the temporary addresses or transaction hashes into public deployment
configuration.

## 9. Evidence and teardown

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
| Two direct provider positions, including a two-ID batch | Not run in this template yet |
| Checkout provider payout split | Not run in this template yet |
| Selected exit with no self-rebate | Not run in this template yet |
| Free exit while checkout paused | Not run in this template yet |
| Paused owner handoff to Society Safe | Automated fork gate passed; manual run pending |
| Temporary addresses | Intentionally omitted; localhost fork only |
| Direct FAME held purchase | Passed in the browser |
| Native ETH pool checkout | Passed atomically; zero retained checkout balance |
| USDC pool checkout | Passed atomically; zero retained checkout balance |
| WETH held checkout | Passed atomically; zero retained checkout balance |
| Direct FAME purchase | `0xcb1cf62cdad15177c7828c35757a412db633e645cf84d3398e22ae55f150b572` |
| ETH checkout / route | `0x8fe371095f496e528fd3dbf95fb546a0706c1a51e3d91bd9d33913f0329b663e` / `0x941a35a1a857158ae525d3cb08120682d8b81d2ab88d5cd98ff789167f6448be` |
| USDC checkout / route | `0x0473c7922105197ad0b247d031d831ea7a49b0f8088422b256437b27802da921` / `0x1fdbb62f0ad3e0e13c9d9ae8f947f1a4b8493676de056422fa98cb2ba153c742` |
| WETH checkout / route | `0x0c612ba1a7c356f5ed053d6f034062758dd70f76d4b9fa08c0063eb41bfb0550` / `0x2b80d0a7738f992a1fd2c73089b77ba638c557bd132be07803884aa9cac71593` |
| Buyer refund accounting | Each checkout returned excess FAME |
| Checkout mirror custody | Zero after the campaign |
| One-shell contention | Passed in the contract fork suite: one winner, one losing buyer |
| One-ID ETH/WETH/USDC redemption | Automated Base-fork gate passed; browser wallet matrix not executed yet |
| Multi-ID bonus redemption | Automated Base-fork gate passed with a direct NFT donation; browser wallet matrix not executed yet |
| 32-ID redemption | Automated Base-fork gate passed at 1,192,182 execution gas against a 400,000,000 block gas limit; browser wallet matrix not executed yet |
| Final redemption inventory | Automated Base-fork gate passed with zero checkout FAME, Society NFTs, and router allowance |
| Teardown and wallet reset | Required after the local campaign |

The automated checkout gate ran against the deployed router and latest Base
state on 2026-08-01. ETH-held, USDC-Mint-pool, WETH-Burn-pool, premium-race,
expired-quote, and same-shell-contention cases passed at fork head `49392705`,
hash
`0x6891ce9282e1a979c4f274524c56bf5e8e2fd3c73d19b85b0af7385cdb622a8c`.
This is contract-level fork evidence; it is not the browser campaign and does
not create reusable deployment addresses.

The automated redemption gate ran against the deployed router and latest Base
state on 2026-08-01. One-ID ETH, WETH, and USDC routes, a three-ID USDC route
with a directly donated NFT bonus, the 32-ID WETH route, meaningful protected
output floors, and an over-floor rollback case passed at fork head `49426944`,
hash
`0xdcfcca14511ac20036e2335581407cede2842544c55eacd180f0ddfad28bb1d4`.
The browser wallet matrix remains `not executed`; the contract proof does not
pretend to be wallet or rendered-UX evidence.

When the run ends—or immediately after a reload, uncertain transaction, or
local-node failure—stop `fls-www`, stop Anvil, restore the operator test
wallet's normal Base RPC configuration, and close the shells containing the
temporary address. Do not copy the address or Foundry `broadcast/` output into
tracked configuration.

Production inventory funding and its exact transfer amount, live
marketplace/checkout deployment, live activation and testing, and the later
7-of-14 Safe ownership handoff are all deferred.
