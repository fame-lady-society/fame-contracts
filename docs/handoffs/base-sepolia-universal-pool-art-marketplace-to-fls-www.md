# Universal pool art marketplace handoff to `fls-www`

Status: **deployed paused; `fls-www` integration may be prepared but must not be
presented as live**

Production implementation is specified separately in
`docs/handoffs/base-universal-pool-art-marketplace-production-implementation.md`.

`UniversalPoolArtMarketplace` replaces manual per-token listing and rotation
with a continuous exchange:

- one owner-managed global premium applies to every purchase;
- any marketplace-held Society NFT shell can be purchased directly;
- any exclusively eligible Mint Pool or Burn Pool artwork can be moved into a
  marketplace-held shell and purchased atomically; and
- Art Pool artwork is always excluded.

There is no listing mapping, listing event index, operator role, accrued-fee
ledger, or periodic rotation job.

## Release posture

The Base Sepolia deployment exists and has passed independent paused-state
validation. It is not yet active.

| Item | Value |
| --- | --- |
| Chain | Base Sepolia (`84532`) |
| Marketplace | `0x821ab043a94688aC22C5a1b0113fc33ed4Fb6843` |
| FAME / TEST | `0x2cF0408Ee86b337216dD0073ab257F84497067cA` |
| Society NFT mirror | `0x2907936013BDF568F98A98893AC1C746256A9cC5` |
| CreatorMagic | `0xa16C005203cD46cC1929cc8e494cF7945887951B` |
| Owner | `0xD52E2A6bBcEba9673440e4D7843Db6713E9B6FD9` |
| Fee recipient | `0x0Bd54EcB903392B323bC2b3dA61023325f730241` |
| Current configured premium | `1,000 TEST` |
| Deployment block | `44,329,992` |
| Deployment transaction | `0xdd850984dea7107ba98e6ec77f66ff94c2bea9146c4759cfc3e15719ef7f2a97` |
| Current lifecycle state | Paused |
| Current seed inventory | Shell IDs 4, 5, and 6 |
| Explorer verification | Pending |
| Activation | Not broadcast |
| Live smoke | Not run |

The shell IDs above describe deployment-time state, not permanent application
configuration. Always discover current marketplace custody from the mirror.

Authoritative contract-side references:

- `src/UniversalPoolArtMarketplace.sol`
- `out/UniversalPoolArtMarketplace.sol/UniversalPoolArtMarketplace.json`
- `config/fame-public.env`
- `docs/gallery/base-sepolia-universal-pool-art-marketplace.md`

Do not enable buyer writes until the contract is explorer-verified, the owner
has explicitly activated it, `paused()` reads `false`, and the post-activation
validation pass is recorded.

## Product model

The marketplace sells access to artwork through Society NFT shells.

For a held purchase, the selected artwork is already attached to a shell owned
by the marketplace. The buyer receives that same shell ID.

For a pool purchase:

1. `sourceId` identifies the desired Mint Pool or Burn Pool artwork.
2. `shellId` identifies any Society NFT currently owned by the marketplace.
3. CreatorMagic atomically swaps the source artwork into `shellId`.
4. The displaced shell artwork moves back to `sourceId`.
5. The buyer receives `shellId`, now carrying the selected artwork.

The buyer does **not** receive `sourceId` in the pool path. UI copy and result
views must distinguish the delivered shell ID from the selected artwork source
ID.

The buyer pays one FAME unit plus the global premium. On Base Sepolia, the
underlying token is TEST. The contract accepts only the underlying DN404 token;
ETH, WETH, and USDC conversion belongs to the existing swap infrastructure.

The unit sent to the non-skip marketplace generates replacement Society NFT
inventory before the purchased shell leaves. Both purchase paths enforce
`inventoryAfter >= inventoryBefore`.

## Existing `fls-www` foundation

The implemented TEST gallery foundation is on branch
`codex/feat-base-sepolia-test-gallery` at commit
`459e7746ff8ed3fb1e2813a4161f15cbeab5f31f`.

Its useful reusable boundaries include:

- Base Sepolia route/provider composition;
- attention-based canonical reads without background polling;
- bounded Society NFT scanning and disposable discovery caching;
- nested TEST JSON/SVG data-URI decoding;
- the one-button exact-approval transaction queue;
- wagmi/viem replacement and receipt handling;
- the dismissible transaction modal; and
- receipt-backed acquired-NFT presentation.

Do not preserve these closed-loop assumptions:

- `ClosedLoopGallerySwap` contract requests or events;
- per-token listings and premiums;
- event-first listing discovery;
- admin listing, unlisting, repricing, or manual rotation;
- accrued protocol fees; or
- the old `fill(tokenId, recipient)` verification model.

The current `fls-www` checkout may not contain that feature branch. Rebase or
port it deliberately rather than reconstructing its transaction machinery from
memory.

## Bindings and deployment manifest

Add `UniversalPoolArtMarketplace.sol/**` to the Foundry include list in
`fls-www/wagmi.config.ts`, then run:

```sh
doppler run -- yarn wagmi generate
```

The Foundry plugin reads the sibling `fame-contracts` artifact, so generated
bindings do not need to wait for explorer ABI ingestion. Still compare the
generated functions, event, and named errors with the verified explorer ABI
before enabling the route.

Create one Base Sepolia marketplace manifest containing:

- chain ID;
- marketplace address and deployment block;
- FAME, mirror, and CreatorMagic addresses;
- collection bounds;
- TEST metadata strategy; and
- explorer URL.

The manifest supplies deployment facts. It must not become an environment gate
or a substitute for current contract reads.

## Canonical reads

### Global state

Read these facts independently from token-level catalog state:

| Contract | Read | Purpose |
| --- | --- | --- |
| Marketplace | `paused()` | Purchase lifecycle state |
| Marketplace | `premium()` | Global premium for every target |
| Marketplace | `feeRecipient()` | Payment presentation and diagnostics |
| Marketplace | `inventory()` | Current shell inventory count |
| Marketplace | `fame()` | Dependency identity |
| Marketplace | `mirror()` | Dependency identity |
| Marketplace | `creatorMagic()` | Dependency identity |
| FAME | `unit()` | Unit component of the purchase price |

Refresh global state on initial load, focus, explicit refresh, and relevant
confirmed transactions. Do not poll an idle tab.

### Marketplace shells

Marketplace shell discovery is bounded and canonical:

1. Scan the Society NFT universe using the mirror's non-reverting ownership
   read.
2. Keep token IDs whose current owner equals the marketplace.
3. Read each shell's current `tokenURI` or `artworkHash`.
4. Treat direct mirror transfers as custody changes, not as listings.

The deployment currently owns three shells, but the contract is designed to
operate from current custody rather than a hardcoded set.

### Artwork targets

For each candidate artwork token ID, read:

- `creatorMagic.tokenURI(tokenId)`;
- `marketplace.artworkHash(tokenId)`;
- `creatorMagic.isTokenInMintPool(tokenId)`;
- `creatorMagic.isTokenInBurnedPool(tokenId)`;
- `mirror.ownerAt(tokenId)`; and
- the CreatorMagic Art Pool bounds.

Global and per-token projections should remain independently refreshable.
Visible or selected candidates can be loaded lazily. A bounded full scan remains
reasonable for the 888-token collection when initiated intentionally and
cached.

## Fulfillment routing

Resolve a selected artwork target in this order:

1. If the intended recipient already owns `targetId`, show the owned result and
   do not submit a purchase.
2. If `mirror.ownerAt(targetId) == marketplace`, use a held purchase with
   `shellId = targetId`.
3. Otherwise, read Mint and Burn eligibility.
4. If exactly one eligibility predicate is true, use a pool purchase with
   `sourceId = targetId` and a currently marketplace-owned `shellId`.
5. If neither predicate is true, the artwork is not currently purchasable.
6. If both predicates are true, surface an ambiguous canonical state and do not
   guess a path.
7. Never offer an Art Pool source.

For pool fulfillment, shell selection is operational rather than a product
choice. Any currently marketplace-owned shell can deliver the selected artwork.
The selection must be frozen into the transaction fingerprint and revalidated
immediately before simulation.

If a preceding FAME swap causes the buyer to mint the exact target NFT, repeat
the ownership and eligibility reads after the swap. Short-circuit to the owned
result when appropriate rather than continuing with stale purchase inputs.

## Pricing and allowance

For every buyer (including the fee recipient):

```text
total = fame.unit() + marketplace.premium()
     = fame.unit() + communityFee + providerFee
```

Prefer `marketplace.purchaseCharge(buyer)` for allowance sizing; charge does not
depend on buyer identity. Fee-recipient buyers pay the full premium like anyone
else (community fee may self-transfer when they are also the FAME payer).

The one-button TEST flow should:

1. Freeze account, recipient, target artwork, fulfillment path, shell ID,
   source ID, artwork hash, unit, premium, total, and calldata.
2. Reuse an existing allowance when it covers the required spend.
3. Otherwise approve the exact required spend.
4. Wait one confirmation.
5. Re-read and simulate the marketplace call.
6. Request the purchase transaction automatically when the frozen context
   remains current.

Set `maxPremium` to the premium accepted by the buyer. The transaction reverts
if the current premium is higher and pays the lower current premium if it has
decreased.

Use `minBuyerMirrorBalanceAfter = 0` unless a specific product flow asks the
contract to enforce a buyer-balance postcondition. Do not invent a nonzero
minimum as a generic wallet eligibility rule.

## Contract calls

### Held artwork

```solidity
purchaseHeld(
    uint256 shellId,
    bytes32 expectedArtworkHash,
    uint256 maxPremium,
    uint256 minBuyerMirrorBalanceAfter,
    address recipient
)
```

Use when the marketplace currently owns the selected target shell.

### Mint or Burn Pool artwork

```solidity
purchasePool(
    uint256 shellId,
    uint256 sourceId,
    bytes32 expectedArtworkHash,
    uint256 maxPremium,
    uint256 minBuyerMirrorBalanceAfter,
    address recipient
)
```

Use only when `sourceId` is exclusively Mint Pool or Burn Pool eligible.
`sourceId` must differ from `shellId`.

Prefer the contract's `artworkHash(tokenId)` result over reproducing URI hashing
with ad hoc frontend encoding.

Immediately before either simulation, refresh:

- `paused`;
- wallet chain and account;
- recipient;
- FAME unit, balance, and allowance;
- premium;
- target artwork hash;
- target ownership and pool eligibility;
- shell custody and current shell artwork; and
- dependency addresses when the cached deployment identity is unavailable.

Contract simulation and named reverts remain authoritative. The frontend should
explain current state but must not invent buyer eligibility rules.

## Purchase outcome

The canonical receipt must contain one matching `ArtworkPurchased` event:

```solidity
event ArtworkPurchased(
    address indexed buyer,
    address indexed recipient,
    uint256 indexed shellId,
    FulfillmentPath path,
    uint256 sourceId,
    bytes32 artwork,
    uint256 unitAmount,
    uint256 premiumAmount,
    uint256 inventoryBefore,
    uint256 inventoryAfter
);
```

Path values:

- `0`: held;
- `1`: Mint Pool;
- `2`: Burn Pool.

Held purchases report `sourceId = 0`.

`premiumAmount` is the **measured** FAME premium debit from the payer (provider
shares actually transferred + community leg), not necessarily equal to
`marketplace.premium()` when provider self-shares are skipped.

For multi-asset checkout, also project `CheckoutSettled` (includes `sourceId`,
`artwork`, and measured `marketplaceFameCharge`).

After confirmation, reconcile the receipt with canonical reads at the receipt
block where supported:

- event buyer, recipient, shell, path, source, artwork, unit, and measured premium match
  the frozen purchase / charge;
- `inventoryAfter >= inventoryBefore`;
- the mirror transfer moves `shellId` from the marketplace to `recipient`;
- `mirror.ownerAt(shellId) == recipient`;
- `marketplace.artworkHash(shellId) == expectedArtworkHash`; and
- the acquired result renders metadata from the delivered `shellId`.

For a pool purchase, capture the pre-transaction shell artwork hash if the
diagnostic view needs to show that the displaced artwork moved to `sourceId`.
This is useful test evidence but does not need to dominate the buyer result.

The completed transaction modal should become a "what you got" view showing:

- actual artwork;
- delivered shell ID;
- selected source ID and Mint/Burn path when applicable;
- recipient;
- unit, premium, and total paid;
- transaction hash and explorer link; and
- verified current ownership.

If the receipt confirms but follow-up reads fail, show confirmed with
verification still refreshing. Do not report a mined purchase as failed.

## Error mapping

At minimum, map these named errors into specific recoverable states:

| Error | UI meaning |
| --- | --- |
| `PurchasesPaused` | Marketplace is not active |
| `PremiumExceedsMaximum` | Premium changed above buyer consent |
| `UnavailableShell` | Selected delivery shell left marketplace custody |
| `ArtworkMismatch` | Metadata changed; refresh the selected artwork |
| `IneligiblePoolSource` | Target is no longer in Mint or Burn Pool |
| `AmbiguousPoolSource` | Pool state is contradictory; refresh and stop |
| `ArtPoolSourceExcluded` | Target is intentionally unavailable |
| `SourceEqualsShell` | Refresh fulfillment routing |
| `InvalidRecipient` | Recipient is zero |
| `BuyerMirrorBalanceTooLow` | Requested postcondition was not met |
| `InventoryInvariantBroken` | Contract invariant stopped settlement |
| `StackMismatch` | Deployed dependency wiring changed |
| `InvalidFeeRecipient` | Fee recipient is zero or the marketplace itself |
| `PaymentTransferFailed` | FAME transfer or allowance failed |

Reuse the app's existing transaction error display and replacement handling.
Do not add a marketplace-specific error framework.

## Metadata

Base Sepolia TEST metadata remains nested on-chain Base64 JSON/SVG and can reuse
the existing browser decoder. Production FAME metadata uses URLs.

Settlement is metadata-format agnostic. The contract compares
`keccak256(bytes(tokenURI))` and never parses the URI. Keep metadata resolution
as a replaceable presentation boundary rather than coupling it to payment or
fulfillment.

## Admin surface

The successor admin surface is much smaller than the closed-loop workbench.

Routine owner controls:

- read and set the global premium;
- read and set the fee recipient;
- pause; and
- unpause.

Advanced owner controls:

- ownership handover; and
- rescue unrelated ERC-20 or ERC-721 assets while paused.

FAME and Society NFT rescue is blocked by the contract. Ownership renunciation
is disabled. There is no operator role and no listing, unlisting, per-token
premium, manual Mint/Burn rotation, or fee-withdrawal action.

Admin visibility may follow current contract owner state. Contract ownership is
the write-security boundary.

## Verification checklist

Before `fls-www` buyer writes are considered ready:

1. BaseScan source and ABI verification is complete.
2. `doppler run -- yarn wagmi generate` includes both purchase calls,
   `ArtworkPurchased`, and all named errors.
3. The deployment manifest points to the mined marketplace address.
4. Read-only pages correctly show the paused state before activation.
5. Owner activation is separately authorized and mined.
6. The post-activation contract validator and deployed-address fork pass.
7. Unit tests cover held, Mint Pool, Burn Pool, unavailable, Art Pool,
   ambiguous, repriced, stale shell, metadata-changed, and paused states.
8. Request-mapping tests assert exact address, chain, function, and arguments
   for approval, `purchaseHeld`, and `purchasePool`.
9. Receipt tests validate all `ArtworkPurchased` fields and the delivered
   shell transfer.
10. Browser QA covers disconnected reads, one-button approval/purchase,
    verified acquired artwork, and narrow-screen transaction states.

The contract repository's bounded live smoke remains separate from frontend QA.
Do not claim either one from the other.

## Explicit non-goals

- No periodic featured rotation.
- No Art Pool purchases.
- No per-token listings or premiums.
- No frontend-maintained order book.
- No marketplace contract support for ETH, WETH, or USDC.
- No background polling.
- No exportable validation report.
- No frontend restrictions that the contracts do not impose.
