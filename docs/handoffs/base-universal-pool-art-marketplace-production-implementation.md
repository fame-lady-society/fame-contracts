# Base Universal Pool Art Marketplace production handoff

## Release contract

The production marketplace may launch with seeded inventory, credited provider
deposits, raw FAME, or donated Society NFTs. Those permissionless balances are
observed operational state, not release drift. Raw FAME or Society-unit
transfers remain irreversible uncredited donations; credited liabilities must
still be fully backed by marketplace inventory and FAME.

The release order is fixed:

1. pass the complete local and latest-Base fork gates;
2. deploy the marketplace and ownerless checkout paused, owned by the deployer;
3. grant the marketplace only CreatorMagic `BANISHER` authority;
4. validate provider structure, credited-unit backing, and exact checkout
   cleanliness against the deployer-owned paused stack;
5. activate from the deployer and validate the active deployer-owned stack;
6. complete initial live acceptance testing while the deployer remains owner;
7. pause from the deployer after live acceptance succeeds;
8. validate the final paused state, including any observed provider inventory;
9. transfer marketplace ownership to the Society Safe;
10. update curated public configuration so the expected marketplace owner is
    the Society Safe;
11. validate the handed-off paused stack; and
12. have the Society Safe execute the later `unpause()` through its normal
    governance process.

An active market with zero inventory is valid but cannot fulfill checkout.
Provider deposits are permissionless while paused or active, and any valid
pre-activation provider state remains valid after activation. Raw FAME or
Society NFT transfers are irreversible uncredited community donations.

## Locked public inputs

Load public values from `config/fame-public.env`. The production release values
must retain:

- `BASE_UNIVERSAL_MARKETPLACE_ACTIVE_PROVIDER_CAP=88`;
- independently configured community and provider fees;
- the deployed FAME, mirror, CreatorMagic, child renderer, router, USDC, WETH,
  deployer, fee-recipient Safe, and future-owner Safe addresses; and
- `BASE_UNIVERSAL_MARKETPLACE_EXPECTED_PAUSED` matching the lifecycle stage.

`BASE_UNIVERSAL_MARKETPLACE_OWNER` remains the deployer through fork testing,
live activation, and initial live acceptance. Immediately after the later
handoff it must be changed to `BASE_UNIVERSAL_MARKETPLACE_FUTURE_OWNER` before
post-handoff validation. CreatorArtistMagic ownership remains a separate
authority and stays configured to its live owner.

Secrets remain in Doppler. Never add RPC URLs, private keys, mnemonics, or
explorer keys to the public config or documentation.

## Mandatory pre-deployment gates

No production deployment discussion is complete until all of these have run
without skips:

- full build with contract-size output;
- focused marketplace, checkout, deployment-validation, fuzz, and invariant
  profiles at the repository's release settings;
- held, pool, contention, ETH/WETH/USDC, redemption, and pause regressions;
- latest-Base release lifecycle through deployer validation and activation,
  maximum eight-token provider provisioning, and a real configured checkout,
  with no fork ownership transfer;
- latest-Base 88-provider payout benchmark where every payout causes a DN404
  mint.

Record the exact Base block number/hash, checkout gas, block gas limit,
configured budget, and headroom assertion. Provider withdrawal has no random
scan or release gas gate. An RPC-less or skipped fork test is `not executed`,
never passing evidence.

The authoritative disposable manual sequence and evidence table are in
`docs/gallery/base-universal-pool-art-marketplace-fork-report.md`.

## Deployment and paused validation

The deployment script creates the market and checkout and wires the authorized
checkout. It never seeds inventory:

```sh
set -a
source config/fame-public.env
set +a

doppler run --config prd -- sh -c '
  BASE_RPC="$RPC_URL" forge script \
    script/DeployBaseUniversalPoolArtMarketplace.s.sol:DeployBaseUniversalPoolArtMarketplace \
    --rpc-url base
'
```

Real broadcast requires separate explicit authorization and an approved
signing path; this handoff intentionally provides no production broadcast
command.

After deployment, grant only `BANISHER`, set
`BASE_UNIVERSAL_MARKETPLACE_EXPECTED_PAUSED=true`, and run:

```sh
doppler run --config prd -- sh -c '
  BASE_RPC="$RPC_URL" forge script \
    script/ValidateBaseUniversalPoolArtMarketplace.s.sol:ValidateBaseUniversalPoolArtMarketplace \
    --rpc-url base
'
```

The validation must prove canonical dependencies and router configuration,
deployer ownership, Safe fee recipient, provider cap and fees, authorized
checkout wiring, checkout/router skip-NFT state, narrow roles, and the paused
state. It must also prove unique nonzero active providers with consistent
indices, nonzero units, an exact provider-unit sum, inventory and FAME backing
for every credited unit, and zero checkout Society/ETH/FAME/USDC/WETH balances
and marketplace/router allowances.

## Deployer activation and live acceptance

Activate the validated stack from the deployer. Set
`BASE_UNIVERSAL_MARKETPLACE_EXPECTED_PAUSED=false` and rerun the validator while
`BASE_UNIVERSAL_MARKETPLACE_OWNER` remains the deployer. Record inventory,
active-provider count, provider positions, total provider units, and raw FAME
without requiring those permissionless values to match a configured target.

Complete initial live acceptance from the deployer-owned deployment. Provider
inventory may be added permissionlessly after activation. If acceptance adds
provider inventory, record and validate the observed inventory, active-provider
count, and provider-unit totals; do not require them to return to zero.

Safe ownership handoff is not a prerequisite for fork activation, live
activation, or initial live testing.

## Paused ownership handoff after acceptance

After live acceptance succeeds, the deployer pauses the marketplace and reruns
the validator with `BASE_UNIVERSAL_MARKETPLACE_EXPECTED_PAUSED=true`. Checkout
must be paused while provider deposits and withdrawals remain available.

`script/TransferBaseUniversalPoolArtMarketplaceOwnership.s.sol` validates the
current production stack and refuses an unpaused handoff. It accepts only the
exact Society Safe `0xC952C53D8B63919e372caa2E6FEe605ee24E4D3D`, requires
deployed code at that address, and rejects zero, current, EOA, or arbitrary
contract destinations before broadcast. Its production use requires the
deployer signing path and separate authorization.

After the ownership transfer succeeds:

1. set `BASE_UNIVERSAL_MARKETPLACE_OWNER` in curated public configuration to
   the Society Safe;
2. keep `BASE_UNIVERSAL_MARKETPLACE_EXPECTED_PAUSED=true`;
3. rerun the validator; and
4. prove provider-position integrity at the observed inventory level.

Do not begin the handoff until deployer-owned live activation and acceptance
have succeeded.

## Society Safe activation

After handoff, the Society Safe may later call `unpause()` through its normal
governance process. Deployment tooling does not impersonate the Safe or hold a
Safe signing key. The unlocked activation script in the fork runbook always
uses the deployer and never rehearses Safe activation.

After the Safe transaction confirms:

1. set `BASE_UNIVERSAL_MARKETPLACE_EXPECTED_PAUSED=false`;
2. rerun the validator against the Safe-owned active stack; and
3. prove inventory, active-provider count, and total provider units remain
   internally consistent with the handed-off state.

Checkout is expected to reject while the active market is empty. If live
acceptance or users have already added inventory, validate that observed state
instead.

## Post-launch provider inventory

Provider setup is permissionless and does not require owner or Safe action.
The frontend-friendly path is one `setApprovalForAll` approval followed by one
atomic `depositInventoryBatch(uint256[])` for one through eight distinct valid
Society IDs. `depositInventory(uint256)` remains the single-token path.

### Intentional open-pool risk (deposit-to-snipe)

The market is a **universal pool**, not a per-token listing book. Once a Society
shell is deposited while the market is **unpaused** (or the market is later
unpaused with inventory already held), that exact shell is immediately
purchasable by anyone via `purchaseHeld` / `checkoutHeld` (or pool paths that
consume the shell as fulfillment capacity).

There is **no** deposit cooldown, exclusive listing lock, or promise to return
the deposited token ID. The sole exit is
`withdrawInventory(tokenId, maxPremium)`: it transfers a currently
marketplace-owned Society token selected by the provider and consumes the
provider's oldest credited unit. Each credited unit keeps its actual deposit
timestamp. Its required gross premium starts at the current configured premium,
decays linearly with upward rounding, and reaches exactly zero at 24 hours. The
`maxPremium` argument remains the provider's consent bound while fee and time
state change. The selected shell still races public buyers.

This is **product-intentional**. Operators and WWW copy should treat provider
deposits as contributing fungible inventory units plus scarce art that can be
bought immediately, not as private listings. Optional mitigations are
operational only (deposit while paused, private coordination before unpause),
not on-chain exclusivity.

For the first credited deposit, record:

- all deposited token IDs;
- the provider position unit count and nonzero index;
- one active-provider slot consumed for the wallet;
- total provider units equal to the deposited batch length; and
- live marketplace inventory equal to the received Society units.

Then complete one real checkout and prove exact configured gross fee routing,
unchanged provider weight, inventory preservation, cleared marketplace/router
allowances, and zero checkout ETH, USDC, WETH, FAME, and Society balances.

## Go/no-go

Go only when:

- the current commit is reviewed and reproducibly built;
- every mandatory local and latest-Base fork gate is green with no skips;
- the 88-provider payout gas evidence remains inside its configured budget;
- the disposable manual lifecycle passed with structurally valid provider and
  backing state and an exactly clean checkout;
- deployer-owned live activation and initial acceptance passed before handoff;
- production addresses and expected ownership have been independently checked;
- the paused handoff and final Safe activation calldata have been reviewed; and
- explicit deployment and Safe governance authorizations have been granted.

No-go on any missing fork evidence, owner/config mismatch, provider structure
or backing failure, unexplained role, dirty transient checkout balance or
allowance, or an ownership destination other than the exact deployed Society
Safe.

## Out of scope

This handoff does not authorize broadcast, deployment, ownership transfer, Safe
execution, FLS WWW changes, or publication. It does not add a seed requirement,
receipt NFT, claim distributor, adjustable provider cap, rescue path, global
custody pause, or selected-withdrawal payment route beyond direct FAME.
