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
10. validate the handed-off paused stack using the manifest addresses and
    process-local Safe-owner expectations;
11. have the Society Safe execute `unpause()` through its normal governance
    process and reconcile that execution to the manifest;
12. validate the final Safe-owned active stack using the manifest addresses;
    and
13. only then publish the marketplace address, checkout address, Safe owner,
    and active expectation together in curated public configuration.

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

The tracked `BASE_UNIVERSAL_MARKETPLACE_OWNER` remains the deployer and the
tracked marketplace and checkout addresses remain unpublished throughout every
deployment and lifecycle send. Validators consume the two addresses from the
manifest and use process-local owner/paused overrides for the stage being
checked. Only after Safe activation reconciliation and final validation may the
tracked owner, paused expectation, marketplace address, and checkout address be
updated and committed together. CreatorArtistMagic ownership remains a
separate authority and stays configured to its live owner.

Secrets remain in Doppler. Never add RPC URLs, private keys, mnemonics, or
explorer keys to the public config or documentation.

## Mandatory pre-deployment gates

No production deployment discussion is complete until all of these have run
without skips:

- full-repository build plus the target-scoped marketplace and checkout runtime
  and initcode size gate;
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

Production deployment is the receipt-aware viem state machine in
`js/deploy/base-universal-pool-art-marketplace.mjs`. It creates the market,
creates the checkout, and wires the authorized checkout as three separate
nonce-pinned transactions. It never seeds inventory. Prepare a secret-free
manifest before requesting broadcast authorization:

`js/deploy/base-universal-pool-art-marketplace-state.test.mjs` is the state and
recovery test authority. The Solidity
`test/helpers/UniversalPoolArtMarketplaceDeploymentFixture.sol` is test-only;
it is not a production broadcaster. The read-only
`script/ValidateBaseUniversalPoolArtMarketplace.s.sol` remains the independent
on-chain validator.

```sh
set -a
source config/fame-public.env
set +a

export MARKETPLACE_DEPLOYMENT_MANIFEST=script/manifests/base-universal-pool-art-marketplace-deployment.json

MARKETPLACE_DEPLOYMENT_MODE=production FOUNDRY_PROFILE=universal_marketplace \
  doppler run --config prd -- \
  yarn marketplace:deployment prepare "$MARKETPLACE_DEPLOYMENT_MANIFEST"
```

Preparation pins Base chain ID, deployer and starting nonce, both CREATE
addresses, source commit, compiler/profile, ABI and bytecode hashes, constructor
inputs, and authorization calldata. The manifest contains raw public creation
and call data, transaction and replacement hashes, receipts, and verified
results. It must never contain an RPC URL, private key, mnemonic, or raw signed
transaction.

Review the manifest, the predicted addresses, and the explicit deployment
authorization. Then run one reconciliation and at most one `advance` per fresh
invocation:

```sh
MARKETPLACE_DEPLOYMENT_MODE=production FOUNDRY_PROFILE=universal_marketplace \
  doppler run --config prd -- \
  yarn marketplace:deployment reconcile "$MARKETPLACE_DEPLOYMENT_MANIFEST"

MARKETPLACE_DEPLOYMENT_MODE=production FOUNDRY_PROFILE=universal_marketplace \
  doppler run --config prd -- \
  yarn marketplace:deployment advance "$MARKETPLACE_DEPLOYMENT_MANIFEST"
```

`advance` submits only the first unexecuted step and does not loop. Repeat the
reconcile-review-advance process in a new process for the remaining authorized
steps. The four valid recovery prefixes are: nothing mined (deploy the pinned
marketplace), marketplace only (deploy the pinned checkout), marketplace plus
checkout (authorize that checkout), and fully authorized (submit nothing).
Canonical receipts and contract state decide the prefix; a recorded pending or
missing transaction is uncertainty, not permission to reuse its nonce.

The state machine stops on any unexpected nonce use, code, runtime hash,
dependency, ownership/configuration, authorization, revert, dropped receipt, or
changed-payload replacement. A same-sender, same-nonce, same-target, exact-data
replacement may be submitted only through a separately authorized
`replace <manifest> <deployment-step-id>` invocation after reconciliation; it
is recorded in replacement history. The same rule is available to a dropped or
pending direct lifecycle transaction through `replace-operation`. No Forge
production broadcaster exists as a bypass.

After the fully authorized prefix is confirmed, independently compare the
canonical addresses and runtime hashes to the manifest. Export the two
validated manifest addresses for interim validators without editing
`config/fame-public.env`:

```sh
export BASE_UNIVERSAL_MARKETPLACE_ADDRESS="$(jq -er '.intent.marketplace' "$MARKETPLACE_DEPLOYMENT_MANIFEST")"
export BASE_FAME_MARKETPLACE_CHECKOUT_ADDRESS="$(jq -er '.intent.checkout' "$MARKETPLACE_DEPLOYMENT_MANIFEST")"
```

Keep these process-local values for every validation through final Safe
activation. Do not configure a frontend from console output or a pending
transaction, and do not write or commit either address to tracked config while
any lifecycle send remains. Grant only `BANISHER`, then validate the initial
deployer-owned paused state with process-local stage expectations:

```sh
BASE_UNIVERSAL_MARKETPLACE_OWNER="$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER" \
BASE_UNIVERSAL_MARKETPLACE_EXPECTED_PAUSED=true \
  doppler run --config prd -- sh -c '
  BASE_RPC="$RPC_URL" FOUNDRY_PROFILE=universal_marketplace forge script \
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

Prepare and review a separate deployer-authorized activation operation. The
operation pins `unpause()` calldata, the deployer's untouched nonce, the
expected `MarketUnpaused` event, and the final owner/paused state:

```sh
MARKETPLACE_DEPLOYMENT_MODE=production FOUNDRY_PROFILE=universal_marketplace \
  doppler run --config prd -- \
  yarn marketplace:deployment prepare-operation \
    "$MARKETPLACE_DEPLOYMENT_MANIFEST" deployer-activation

MARKETPLACE_DEPLOYMENT_MODE=production FOUNDRY_PROFILE=universal_marketplace \
  doppler run --config prd -- \
  yarn marketplace:deployment advance-operation \
    "$MARKETPLACE_DEPLOYMENT_MANIFEST" deployer-activation-1
```

Use the operation ID printed by `prepare-operation`; the example assumes it is
the first lifecycle operation. A timeout or replacement stops the command and
must be reconciled before any further action. Direct lifecycle reconciliation
uses the recorded sender and nonce: it checks every known transaction hash,
then scans canonical blocks from the operation's preparation/submission block,
and records an exact-payload replacement without requiring its hash as input:

```sh
MARKETPLACE_DEPLOYMENT_MODE=production FOUNDRY_PROFILE=universal_marketplace \
  doppler run --config prd -- \
  yarn marketplace:deployment reconcile-operation \
    "$MARKETPLACE_DEPLOYMENT_MANIFEST" "<operation-id>"
```

A conflicting sender, nonce, target, or calldata is persisted as a no-go
canonical observation. Recent recovery scans at most 10,000 blocks directly;
older recovery first locates the nonce-consumption block with historical nonce
reads, then inspects that one canonical block. If the configured RPC cannot
serve those historical reads, recovery fails closed for manual disposition. A
transaction whose hash was lost before manifest persistence and which remains
only pending cannot be discovered from canonical blocks; wait for it to mine or
for the pending nonce to clear before manual disposition. If the exact
transaction is proven pending or dropped, a separately
authorized replacement may be submitted without changing sender, nonce,
target, or calldata:

```sh
MARKETPLACE_DEPLOYMENT_MODE=production FOUNDRY_PROFILE=universal_marketplace \
  doppler run --config prd -- \
  yarn marketplace:deployment replace-operation \
    "$MARKETPLACE_DEPLOYMENT_MANIFEST" "<operation-id>"
```

Before either `advance-operation` or `replace-operation` sends, it reruns the
same pinned source commit, compiler/profile, artifact and calldata hashes,
public configuration, canonical dependency, deployment-mode, and production
clean-tree checks used by deployment sends. After confirmation, rerun the
validator with process-local
`BASE_UNIVERSAL_MARKETPLACE_OWNER="$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER"` and
`BASE_UNIVERSAL_MARKETPLACE_EXPECTED_PAUSED=false`; do not edit tracked config.
Record inventory, active-provider count, provider positions, total provider
units, and raw FAME without requiring those permissionless values to match a
configured target.

Complete initial live acceptance from the deployer-owned deployment. Provider
inventory may be added permissionlessly after activation. If acceptance adds
provider inventory, record and validate the observed inventory, active-provider
count, and provider-unit totals; do not require them to return to zero.

Safe ownership handoff is not a prerequisite for fork activation, live
activation, or initial live testing.

## Paused ownership handoff after acceptance

After live acceptance succeeds, the deployer pauses the marketplace and reruns
the validator with process-local
`BASE_UNIVERSAL_MARKETPLACE_OWNER="$BASE_UNIVERSAL_MARKETPLACE_DEPLOYER"` and
`BASE_UNIVERSAL_MARKETPLACE_EXPECTED_PAUSED=true`. Checkout must be paused while
provider deposits and withdrawals remain available. Keep tracked config
unchanged so the pinned source commit and clean-tree checks remain valid for
the ownership send.

Prepare the ownership handoff only after the authorized pause transaction has
a canonical success receipt and paused validation passes. The state machine
refuses an unpaused handoff, accepts only the exact Society Safe
`0xC952C53D8B63919e372caa2E6FEe605ee24E4D3D`, requires deployed code at that
address, and pins the expected `OwnershipTransferred` receipt and final paused
state:

```sh
MARKETPLACE_DEPLOYMENT_MODE=production FOUNDRY_PROFILE=universal_marketplace \
  doppler run --config prd -- \
  yarn marketplace:deployment prepare-operation \
    "$MARKETPLACE_DEPLOYMENT_MANIFEST" ownership-handoff

MARKETPLACE_DEPLOYMENT_MODE=production FOUNDRY_PROFILE=universal_marketplace \
  doppler run --config prd -- \
  yarn marketplace:deployment advance-operation \
    "$MARKETPLACE_DEPLOYMENT_MANIFEST" ownership-handoff-2
```

Use the printed operation ID. Production use requires the deployer signing path
and separate authorization. A submitted handoff is never replayed; reconcile
its canonical receipt or exact-payload replacement first using the same
sender-plus-nonce recovery command above.

After the ownership transfer succeeds:

1. rerun the validator with process-local
   `BASE_UNIVERSAL_MARKETPLACE_OWNER="$BASE_UNIVERSAL_MARKETPLACE_FUTURE_OWNER"`
   and `BASE_UNIVERSAL_MARKETPLACE_EXPECTED_PAUSED=true`;
2. prove provider-position integrity at the observed inventory level; and
3. leave tracked public configuration unchanged because Safe activation is
   still a later lifecycle operation.

Do not begin the handoff until deployer-owned live activation and acceptance
have succeeded.

## Society Safe activation

After handoff, prepare the Society Safe's later `unpause()` intent:

```sh
MARKETPLACE_DEPLOYMENT_MODE=production FOUNDRY_PROFILE=universal_marketplace \
  doppler run --config prd -- \
  yarn marketplace:deployment prepare-operation \
    "$MARKETPLACE_DEPLOYMENT_MANIFEST" safe-activation
```

The command prints only the Safe inner-call target and calldata. Deployment
tooling does not impersonate the Safe, hold a Safe signing key, or submit the
Safe transaction. Review and execute the call through the Safe's normal
governance process. Once it has a canonical execution transaction hash, bind
that receipt and the Safe transaction identifier to the manifest:

```sh
MARKETPLACE_DEPLOYMENT_MODE=production FOUNDRY_PROFILE=universal_marketplace \
  doppler run --config prd -- \
  yarn marketplace:deployment reconcile-operation \
    "$MARKETPLACE_DEPLOYMENT_MANIFEST" safe-activation-3 \
    "<canonical execution transaction hash>" "<Safe transaction hash>"
```

Use the printed operation ID. Reconciliation requires the outer transaction to
target the pinned Society Safe, exactly one Safe `ExecutionSuccess` event whose
emitted transaction hash matches the reviewed Safe hash, the
marketplace-emitted `MarketUnpaused` event attributed to the Society Safe, the
pinned marketplace runtime, unchanged checkout authorization, and the
Safe-owned active final state. A Safe `ExecutionFailure`, missing execution
event, or mismatched hash is a no-go. Both hashes are required and remain
distinct in the manifest: `safeTransactionHash` is the reviewed bytes32 Safe
transaction identifier, while `executionTransactionHash` is the canonical
outer Base transaction whose receipt and events were verified.

After the Safe transaction confirms:

1. rerun the validator against the Safe-owned active stack with process-local
   `BASE_UNIVERSAL_MARKETPLACE_OWNER="$BASE_UNIVERSAL_MARKETPLACE_FUTURE_OWNER"`
   and `BASE_UNIVERSAL_MARKETPLACE_EXPECTED_PAUSED=false`;
2. prove inventory, active-provider count, and total provider units remain
   internally consistent with the handed-off state;
3. independently compare both manifest addresses and the final owner/paused
   state to canonical Base reads; and
4. only after every check passes, write `.intent.marketplace` to
   `BASE_UNIVERSAL_MARKETPLACE_ADDRESS`, `.intent.checkout` to
   `BASE_FAME_MARKETPLACE_CHECKOUT_ADDRESS`, the Society Safe to
   `BASE_UNIVERSAL_MARKETPLACE_OWNER`, and `false` to
   `BASE_UNIVERSAL_MARKETPLACE_EXPECTED_PAUSED` in `config/fame-public.env`,
   then review and commit that one final publication change.

No receipt-aware lifecycle send may follow tracked config publication. If a
lifecycle operation must be reopened, restore the exact clean source/config
state pinned by the manifest, reconcile first, and defer publication again.

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
