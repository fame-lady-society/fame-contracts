---
chain: base-fork
status: ready-for-zero-inventory-rehearsal
contracts: UniversalPoolArtMarketplace + FameMarketplaceCheckout
---

# Base Universal Pool Art Marketplace fork run

This is the current manual release rehearsal. It launches the marketplace with
zero inventory and zero providers, validates and activates it from the
deployer, and only then adds credited provider inventory. It does not transfer
ownership to the Society Safe. There is no operator or Safe seed transfer.

Every transaction below must target the literal loopback RPC
`http://127.0.0.1:8545`. Never substitute a Base RPC, load a production signing
key, commit temporary addresses, or preserve Foundry `broadcast/` output.

## 1. Pass the automated fork preflight

From `fame-contracts`:

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

The result must include:

- the zero-inventory release lifecycle, post-launch eight-token provider batch,
  and real configured checkout;
- the configured 88-provider checkout where every provider payout causes a
  DN404 mint;
- selected provider withdrawal with per-unit timestamp decay and oldest-unit
  consumption; and
- the existing held, pool, contention, redemption, and routing regressions.

A skipped or RPC-less run is not green. These are fork simulations only and do
not authorize a Base transaction.

## 2. Start a latest-state Base fork

```sh
set -a
source config/fame-public.env
set +a

doppler run --config prd -- zsh -c '
  export BASE_RPC="$RPC_URL"
  exec anvil --fork-url base --host 127.0.0.1 --port 8545 --chain-id "$BASE_CHAIN_ID" --quiet
'
```

Leave Anvil running. In a second terminal:

```sh
set -a
source config/fame-public.env
set +a

export LOCAL_BASE_RPC=http://127.0.0.1:8545
export CREATOR_MAGIC_BANISHER_ROLE=4

export FORK_BLOCK_NUMBER="$(cast block-number --rpc-url "$LOCAL_BASE_RPC")"
export FORK_BLOCK_HASH="$(cast block "$FORK_BLOCK_NUMBER" --field hash --rpc-url "$LOCAL_BASE_RPC")"
echo "Fork block: $FORK_BLOCK_NUMBER"
echo "Fork hash:  $FORK_BLOCK_HASH"
```

Record both values. Give the deployer disposable Anvil gas and impersonate it.
Do not transfer FAME to the deployer or marketplace.

```sh
cast rpc anvil_setBalance "$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" 0x56BC75E2D63100000 --rpc-url "$LOCAL_BASE_RPC"
cast rpc anvil_impersonateAccount "$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" --rpc-url "$LOCAL_BASE_RPC"

# Override any stale exports from an earlier seeded rehearsal.
export BASE_UNIVERSAL_MARKETPLACE_INVENTORY=0
export BASE_UNIVERSAL_MARKETPLACE_OWNER="$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER"
```

## 3. Deploy the paused empty stack

Predict the two CREATE addresses, keep them only in this shell, and deploy
through the unlocked deployer:

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

cast call "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" "authorizedCheckout()(address)" --rpc-url "$LOCAL_BASE_RPC"
```

The read-back must equal `BASE_FAME_MARKETPLACE_CHECKOUT_ADDRESS`.

Grant only the CreatorMagic `BANISHER` role. This block intentionally has no
FAME or Society-unit transfer:

```sh
cast send "$BASE_CREATOR_ARTIST_MAGIC_ADDRESS" \
  "grantRoles(address,uint256)" \
  "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" \
  "$CREATOR_MAGIC_BANISHER_ROLE" \
  --from "$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" \
  --unlocked \
  --rpc-url "$LOCAL_BASE_RPC"
```

While the marketplace is still paused, explicitly set both fee components to
2.5% of the 1,000,000 FAME Society unit. A fresh deployment reads these same
values from `config/fame-public.env`; the owner calls make the manual fork state
unambiguous and also repair a fork stack deployed with stale fee exports:

```sh
export BASE_UNIVERSAL_MARKETPLACE_PROVIDER_FEE=25000000000000000000000
export BASE_UNIVERSAL_MARKETPLACE_COMMUNITY_FEE=25000000000000000000000

cast send "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" \
  "setProviderFee(uint256)" "$BASE_UNIVERSAL_MARKETPLACE_PROVIDER_FEE" \
  --from "$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" \
  --unlocked \
  --rpc-url "$LOCAL_BASE_RPC"

cast send "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" \
  "setCommunityFee(uint256)" "$BASE_UNIVERSAL_MARKETPLACE_COMMUNITY_FEE" \
  --from "$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" \
  --unlocked \
  --rpc-url "$LOCAL_BASE_RPC"

cast call "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" "providerFee()(uint256)" --rpc-url "$LOCAL_BASE_RPC"
cast call "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" "communityFee()(uint256)" --rpc-url "$LOCAL_BASE_RPC"
cast call "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" "premium()(uint256)" --rpc-url "$LOCAL_BASE_RPC"
```

The read-backs must be 25,000 FAME, 25,000 FAME, and 50,000 FAME respectively
(`25000000000000000000000`, `25000000000000000000000`, and
`50000000000000000000000`). With one credited provider unit, WWW must show
25,000 FAME per marketplace sale before rounding or additional providers.

Prove the exact empty state:

```sh
cast call "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" "inventory()(uint256)" --rpc-url "$LOCAL_BASE_RPC"
cast call "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" "activeProviderCount()(uint256)" --rpc-url "$LOCAL_BASE_RPC"
cast call "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" "totalProviderUnits()(uint256)" --rpc-url "$LOCAL_BASE_RPC"
```

All three values must be zero.

## 4. Validate and activate from the deployer

Validate the deployer-owned paused stack first:

```sh
export BASE_UNIVERSAL_MARKETPLACE_EXPECTED_PAUSED=true
export BASE_UNIVERSAL_MARKETPLACE_INVENTORY=0
export BASE_UNIVERSAL_MARKETPLACE_OWNER="$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER"

forge script script/ValidateBaseUniversalPoolArtMarketplace.s.sol:ValidateBaseUniversalPoolArtMarketplace \
  --rpc-url "$LOCAL_BASE_RPC"
```

The validator's `ValueMismatch("marketplace.inventory", 1, 0)` error means the
current shell still exported an inventory minimum of `1`; it does not mean the
deployed marketplace has inventory. The explicit zero export above prevents
that stale-shell failure.

Activate from the impersonated deployer and validate the active empty stack:

```sh
forge script script/ActivateBaseUniversalPoolArtMarketplace.s.sol:ActivateBaseUniversalPoolArtMarketplace \
  --rpc-url "$LOCAL_BASE_RPC" \
  --sender "$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" \
  --unlocked \
  --broadcast

export BASE_UNIVERSAL_MARKETPLACE_EXPECTED_PAUSED=false

forge script script/ValidateBaseUniversalPoolArtMarketplace.s.sol:ValidateBaseUniversalPoolArtMarketplace \
  --rpc-url "$LOCAL_BASE_RPC"
```

This disposable fork never transfers marketplace ownership. Production
ownership transfer begins only after the live deployment has been activated
and tested successfully by the deployer. The unlocked activation above tests
that deployer path only and does not authorize a production transaction.

The active empty market is intentionally not checkout-ready. The automated
lifecycle test proves an attempted checkout rejects before buyer funding.

## 5. Add the first provider inventory after launch

Use a disposable provider wallet distinct from the buyer and Safe. Give it
Anvil ETH and transfer one through eight real fork Society NFTs to it from
their current fork owners. For each selected ID, resolve `ownerAt`, impersonate
that owner, and transfer the NFT to the provider. These setup transfers are
fork-only; the provider approval and deposit remain the behavior under test.

```sh
export FORK_PROVIDER="<disposable provider wallet>"
export PROVIDER_IDS="[<one through eight distinct Society IDs>]"

cast rpc anvil_setBalance "$FORK_PROVIDER" 0x56BC75E2D63100000 --rpc-url "$LOCAL_BASE_RPC"
cast rpc anvil_impersonateAccount "$FORK_PROVIDER" --rpc-url "$LOCAL_BASE_RPC"

cast send "$BASE_FAME_NFT_ADDRESS" \
  "setApprovalForAll(address,bool)" \
  "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" true \
  --from "$FORK_PROVIDER" \
  --unlocked \
  --rpc-url "$LOCAL_BASE_RPC"

cast send "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" \
  "depositInventoryBatch(uint256[])" "$PROVIDER_IDS" \
  --from "$FORK_PROVIDER" \
  --unlocked \
  --rpc-url "$LOCAL_BASE_RPC"
```

For a single-ID-specific acceptance pass, approve that ID and call
`depositInventory(uint256)` instead. A raw NFT or FAME transfer is an
irreversible uncredited donation and must not be used for provider setup.

Read the credited state:

```sh
cast call "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" \
  "providerPosition(address)(uint256,uint256)" "$FORK_PROVIDER" \
  --rpc-url "$LOCAL_BASE_RPC"
cast call "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" "activeProviderCount()(uint256)" --rpc-url "$LOCAL_BASE_RPC"
cast call "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" "totalProviderUnits()(uint256)" --rpc-url "$LOCAL_BASE_RPC"
cast call "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" "inventory()(uint256)" --rpc-url "$LOCAL_BASE_RPC"
```

The provider unit count and total provider units must equal the batch length,
the provider index must be nonzero, and exactly one active-provider slot must
be consumed.

## 6. Start `fls-www` against the fork

Run wagmi generation only when the ABI bindings need refreshing:

```sh
cd /Users/user/Development/fls-www
doppler run -- yarn wagmi generate
```

Then start the app in another `fls-www` terminal. Supply the same literal
loopback RPC to server and browser code, enable fork-only quote routing, and
pass both temporary contract addresses through the shell:

```sh
export LOCAL_BASE_RPC=http://127.0.0.1:8545
export BASE_RPC_URL="$LOCAL_BASE_RPC"
export NEXT_PUBLIC_BASE_RPC_URL_1="$LOCAL_BASE_RPC"
export NEXT_PUBLIC_FAME_FORK_MODE=1
export NEXT_PUBLIC_BASE_UNIVERSAL_MARKETPLACE_ADDRESS="<temporary address from the Forge terminal>"
export NEXT_PUBLIC_BASE_FAME_CHECKOUT_ADDRESS="<temporary checkout address from the Forge terminal>"

doppler run \
  --preserve-env="BASE_RPC_URL,NEXT_PUBLIC_BASE_RPC_URL_1,NEXT_PUBLIC_FAME_FORK_MODE,NEXT_PUBLIC_BASE_UNIVERSAL_MARKETPLACE_ADDRESS,NEXT_PUBLIC_BASE_FAME_CHECKOUT_ADDRESS" \
  -- yarn dev
```

The explicit `--preserve-env` list lets Doppler supply the rest of WWW's local
configuration without replacing the five public fork overrides. Do not use
`--preserve-env=true`.

Connect an operator-owned test account through the normal injected wallet.
Configure that wallet's Base RPC as `http://127.0.0.1:8545` before connecting.
The fork and Base mainnet both use chain ID `8453`, so verify the wallet's
active RPC endpoint before every signing campaign; chain ID alone cannot
distinguish them. Open `/fame/gallery` directly or use the `FAME Marketplace`
menu item.

In fork mode, WWW must reject non-loopback RPCs, disable public Base fallback,
and bypass the external indexed quote service. Artwork metadata must continue
through the normal token URI path. Do not begin wallet signing until the page
loads from the loopback fork and shows the temporary marketplace state.

## 7. Run the browser provider and checkout acceptance

Section 5 is the command-line provider acceptance. For the browser campaign,
use an operator-owned provider wallet and seed it with one through eight real
Society NFTs before opening `/fame/gallery/stake/deposit`. If the CLI campaign
already consumed the chosen IDs, select different live IDs. For each ID,
resolve its current fork owner and transfer it to the provider only on Anvil:

```sh
export FORK_PROVIDER="<operator-owned provider wallet>"
export SOCIETY_TOKEN_ID="<1 through 888>"
export SOCIETY_OWNER="$(
  cast call "$BASE_FAME_NFT_ADDRESS" \
    "ownerAt(uint256)(address)" "$SOCIETY_TOKEN_ID" \
    --rpc-url "$LOCAL_BASE_RPC"
)"

cast rpc anvil_setBalance "$FORK_PROVIDER" 0x56BC75E2D63100000 --rpc-url "$LOCAL_BASE_RPC"
cast rpc anvil_setBalance "$SOCIETY_OWNER" 0xDE0B6B3A7640000 --rpc-url "$LOCAL_BASE_RPC"
cast rpc anvil_impersonateAccount "$SOCIETY_OWNER" --rpc-url "$LOCAL_BASE_RPC"
cast send "$BASE_FAME_NFT_ADDRESS" \
  "transferFrom(address,address,uint256)" \
  "$SOCIETY_OWNER" "$FORK_PROVIDER" "$SOCIETY_TOKEN_ID" \
  --from "$SOCIETY_OWNER" --unlocked --rpc-url "$LOCAL_BASE_RPC"
cast rpc anvil_stopImpersonatingAccount "$SOCIETY_OWNER" --rpc-url "$LOCAL_BASE_RPC"
```

Repeat the owner-transfer block for every selected ID. These are fork-only
setup transfers. The provider approval and deposit must be normal wallet-signed
WWW transactions:

1. Connect `FORK_PROVIDER` and open `/fame/gallery/stake/deposit`.
2. Confirm the page discovers the wallet's Society NFTs through the live mirror.
3. Select up to eight distinct cards and confirm the `N selected / 8 maximum`
   count and projected per-sale provider share.
4. Click `Approve Society NFTs`, wait for one confirmation, then click
   `Stake N Society NFTs`.
5. Confirm the transaction modal reports one atomic batch deposit and the
   liquidity overview shows the resulting credited position.

Do not transfer a Society NFT or FAME directly to the marketplace address.
Those transfers are irreversible, uncredited donations and are not provider
setup.

Read back the browser-created position with the commands in section 5. The
unit count and total-provider-unit delta must equal the selected batch length,
and a new provider consumes exactly one active-provider slot.

Next complete one normal routed checkout for a live market-owned ID from
`/fame/gallery`. Record:

- route, checkout, and `ArtworkPurchased` events;
- inventory before and after;
- the provider position and FAME balance before and after;
- the Society Safe FAME balance before and after; and
- checkout ETH, USDC, WETH, FAME, and marketplace allowance after settlement.

Inventory and provider position weight must be preserved, the configured
community/provider fees must route exactly, and all checkout transient balances
and allowances must be zero. The broader browser payment matrix is direct FAME
held purchase, native ETH pool checkout, USDC pool checkout, and WETH held
checkout. Record the transaction and route hashes for each route actually run;
mark every unrun row `not executed`. Automated fork tests are contract-level
proof, not browser-wallet proof.

## 8. Run the browser Society-redemption matrix

Use the same normal wallet account that will sign in the browser. Give it ETH
only on Anvil and ensure receiving FAME may auto-mint Society NFTs:

```sh
export FORK_BUYER="<operator-owned buyer wallet>"

cast rpc anvil_setBalance "$FORK_BUYER" 0x56BC75E2D63100000 --rpc-url "$LOCAL_BASE_RPC"
cast rpc anvil_impersonateAccount "$FORK_BUYER" --rpc-url "$LOCAL_BASE_RPC"
cast send "$BASE_FAME_ADDRESS" \
  "setSkipNFT(bool)" false \
  --from "$FORK_BUYER" --unlocked --rpc-url "$LOCAL_BASE_RPC"
cast rpc anvil_stopImpersonatingAccount "$FORK_BUYER" --rpc-url "$LOCAL_BASE_RPC"
```

If the wallet does not own enough Society NFTs, seed it from real fork holders
using the `ownerAt` and impersonated `transferFrom` procedure in section 7,
substituting `FORK_BUYER` for `FORK_PROVIDER`. Seed 42 transferable IDs for the
complete matrix without reusing an NFT: three one-ID runs, three two-ID runs,
one 32-ID run, and one direct checkout donation.

For the pre-funded bonus only, transfer the extra Society ID to
`BASE_FAME_MARKETPLACE_CHECKOUT_ADDRESS` instead of the buyer. That raw transfer
is intentionally an irreversible checkout donation; it becomes one unit of
checkout FAME and must be consumed by the next successful redemption.

Reload `/fame/gallery` with the wallet connected to the literal loopback RPC.
Open `Your Society NFTs` and confirm its ascending ID list matches both reads:

```sh
cast call "$BASE_FAME_MARKETPLACE_CHECKOUT_ADDRESS" \
  "ownedSocietyTokenIds(address,uint256,uint256)(uint256[])" \
  "$FORK_BUYER" 1 889 --rpc-url "$LOCAL_BASE_RPC"

cast call "$BASE_FAME_NFT_ADDRESS" \
  "balanceOf(address)(uint256)" "$FORK_BUYER" \
  --rpc-url "$LOCAL_BASE_RPC"
```

Run this browser matrix:

| Selection | Receive | Expected evidence |
|---|---|---|
| 1 ID | ETH | Shows and consumes the pre-funded checkout bonus |
| 1 ID | WETH | No bonus after the first success |
| 1 ID | USDC | No bonus after the first success |
| 2 IDs | ETH | Burns the exact selected IDs |
| 2 IDs | WETH | Burns the exact selected IDs |
| 2 IDs | USDC | Burns the exact selected IDs |
| 32 IDs | WETH | Record receipt gas and compare with the fork block gas limit |

The first run should show `Approve NFT redemption`. Wait for that approval to
confirm and verify that WWW does not submit the redemption automatically.
Review the selected IDs, estimate, minimum output, and irreversible-burn copy,
then submit `Burn N NFTs` yourself. Later rows should reuse the approval.

After every success, wait for one confirmation and verify the selected IDs are
gone and the wallet output balance increased. Record the transaction hash,
selected IDs, quote basis and actual FAME, route hash, output, and receipt gas.
Both final checkout custody reads must return zero:

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

Record a wallet rejection, simulation failure, or mined revert once. Do not
retry automatically or invent a recovery flow.

## 9. Prove checkout-only pause and provider custody

Pause from the deployer and prove provider custody remains open:

```sh
cast send "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" "pause()" \
  --from "$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" \
  --unlocked \
  --rpc-url "$LOCAL_BASE_RPC"

export WITHDRAW_TOKEN_ID="<currently marketplace-owned Society ID>"
export WITHDRAW_MAX_PREMIUM="$(
  cast call "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" \
    "withdrawalPremium(address)(uint256)" "$FORK_PROVIDER" \
    --rpc-url "$LOCAL_BASE_RPC"
)"

cast send "$BASE_UNIVERSAL_MARKETPLACE_ADDRESS" \
  "withdrawInventory(uint256,uint256)" \
  "$WITHDRAW_TOKEN_ID" "$WITHDRAW_MAX_PREMIUM" \
  --from "$FORK_PROVIDER" \
  --unlocked \
  --rpc-url "$LOCAL_BASE_RPC"
```

The marketplace must be paused while the provider exit succeeds. The exit consumes
the provider's oldest credited unit and transfers the selected marketplace-owned
shell. Each unit retains its actual deposit timestamp; the required gross
premium decays linearly with upward rounding from the current configured
premium to zero at 24 hours. `maxPremium` is the consent bound. A nonzero
premium uses direct FAME, removes the exiting unit before distribution so it
cannot rebate itself, and executes the complete gross transfer path. There is
no random withdrawal, inventory scan, or withdrawal gas release gate.

This disposable fork never transfers marketplace ownership or asks the Safe to
activate it. Keep all administrative test transactions on the deployer. The
production Safe transfer occurs only after live deployer activation and
validation are complete.

## 10. Evidence and teardown

Record concise run facts:

| Evidence | Result |
|---|---|
| Git revision | |
| Fork block number and hash | |
| Automated latest-Base suite | |
| 88-provider all-mint benchmark gas | |
| Empty paused deployer validation | |
| Empty active deployer validation | |
| Provider/community fee read-back | 25,000 / 25,000 FAME |
| Total marketplace premium read-back | 50,000 FAME |
| `fls-www` revision | |
| WWW startup with loopback fork overrides | |
| Wallet active RPC verified as loopback | |
| Gallery route and normal token URI metadata | |
| First post-launch provider batch | |
| Browser batch approval and atomic stake | |
| First real checkout after provisioning | |
| Browser payment routes and transaction/route hashes | |
| Browser Society redemption matrix | |
| Checkout balances and allowances zero | |
| Timestamped selected provider exit while checkout paused | |
| Teardown and wallet RPC reset | |

When the run ends—or immediately after a reload with a pending transaction, an
uncertain receipt, or loss of the local node—stop `fls-www`, stop Anvil, restore
the operator wallet's normal Base RPC, and close the shells containing
temporary addresses. Discard the fork and start a new run after uncertainty;
there is no recovery journal. Do not copy temporary addresses or Foundry
`broadcast/` output into tracked configuration.

No production write, deployment, activation, ownership transfer, or Safe
transaction is authorized by this rehearsal. Browser rows remain `not
executed` until a human runs them; the automated fork suite does not substitute
for injected-wallet and rendered-UI evidence.
