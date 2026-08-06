# Base Universal Pool Art Marketplace production handoff

## Release contract

The production marketplace launches with zero inventory and zero active
providers. Credited provider deposits are optional post-launch activity. Raw
FAME or Society-unit transfers remain irreversible uncredited donations and are
not deployment, validation, ownership-handoff, or activation prerequisites.

The release order is fixed:

1. pass the complete local and latest-Base fork gates;
2. deploy the marketplace and ownerless checkout paused, owned by the deployer;
3. grant the marketplace only CreatorMagic `BANISHER` authority;
4. validate exact zero inventory, zero active providers, and zero provider
   units against the deployer-owned paused stack;
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

The active empty market is valid but cannot fulfill checkout. Its first
credited post-launch deposit makes inventory-backed checkout available without
another owner action. Raw FAME or Society NFT transfers are irreversible
uncredited community donations.

## Locked public inputs

Load public values from `config/fame-public.env`. The production release values
must retain:

- `BASE_UNIVERSAL_MARKETPLACE_INVENTORY=0`;
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
- latest-Base zero-inventory release lifecycle through deployer validation and
  activation, maximum eight-token provider provisioning, and a real configured
  checkout, with no fork ownership transfer;
- latest-Base 88-provider payout benchmark where every payout causes a DN404
  mint; and
- latest-Base free withdrawal forced through the full 888-ID scan.

Record the exact Base block number/hash, checkout gas, free-exit gas, block gas
limit, configured budgets, and headroom assertions. An RPC-less or skipped fork
test is `not executed`, never passing evidence.

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
checkout wiring, checkout/router skip-NFT state, narrow roles, exact zero
inventory, exact zero provider count, exact zero total provider units, and the
paused state.

## Deployer activation and live acceptance

Activate the validated empty stack from the deployer. Set
`BASE_UNIVERSAL_MARKETPLACE_EXPECTED_PAUSED=false` and rerun the validator while
`BASE_UNIVERSAL_MARKETPLACE_OWNER` remains the deployer. Prove the active empty
state before any provider deposit.

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
current production stack and refuses an unpaused handoff. Its production use
requires the deployer signing path and separate authorization.

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

For the first credited deposit, record:

- all deposited token IDs;
- the provider position unit count and nonzero index;
- one active-provider slot consumed for the wallet;
- total provider units equal to the deposited batch length; and
- live marketplace inventory equal to the received Society units.

Then complete one real checkout and prove exact configured fee routing,
unchanged provider weight, inventory preservation, cleared marketplace/router
allowances, and zero checkout ETH, USDC, WETH, FAME, and Society balances.

## Go/no-go

Go only when:

- the current commit is reviewed and reproducibly built;
- every mandatory local and latest-Base fork gate is green with no skips;
- the 88-provider and 888-ID gas evidence remains inside configured budgets;
- the disposable manual lifecycle passed in the exact empty-launch order;
- deployer-owned live activation and initial acceptance passed before handoff;
- production addresses and expected ownership have been independently checked;
- the paused handoff and final Safe activation calldata have been reviewed; and
- explicit deployment and Safe governance authorizations have been granted.

No-go on any missing fork evidence, owner/config mismatch, nonzero required
launch inventory, unexplained role, dirty transient checkout balance or
allowance, or failed zero-state assertion.

## Out of scope

This handoff does not authorize broadcast, deployment, ownership transfer, Safe
execution, FLS WWW changes, or publication. It does not add a seed requirement,
receipt NFT, claim distributor, adjustable provider cap, rescue path, global
custody pause, or selected-withdrawal payment route beyond direct FAME.
