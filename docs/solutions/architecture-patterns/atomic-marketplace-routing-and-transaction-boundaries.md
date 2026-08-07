---
title: Atomic Marketplace Routing And Transaction Boundaries
date: 2026-08-02
category: docs/solutions/architecture-patterns
module: atomic-marketplace-checkout
problem_type: architecture_pattern
component: payments
severity: high
applies_when:
  - A marketplace has a fixed FAME-denominated obligation but users fund purchases with ETH, WETH, or USDC.
  - An exact-input router must provide target-output checkout UX without adding exact-output execution.
  - A checkout path can produce transaction-local surplus or hold unsolicited route assets that become a boon after success.
  - A wallet flow must model submission, replacement, receipt, revert, and rejection without duplicating wagmi.
related_components:
  - FameRouter
  - FameMarketplaceCheckout
  - UniversalPoolArtMarketplace
  - fls-www gallery
tags:
  - fame-router
  - marketplace-checkout
  - exact-input
  - target-output
  - surplus-fame
  - ambient-balances
  - wagmi
  - transaction-lifecycle
---

# Atomic Marketplace Routing And Transaction Boundaries

## Context

The marketplace has a fixed FAME-denominated obligation: one `fame.unit()` plus the configured gross premium. The router deliberately exposes a different contract. A route declares an exact `amountIn`, a post-fee `minAmountOutAfterFee`, a recipient, a deadline, and executable legs (`src/router/FameRouterTypes.sol:43-51`). The checkout coordinator bridges these two contracts without pretending that `FameRouter` is exact-output.

That distinction turns “buy enough FAME to settle this purchase” into an inverse-quote problem. WWW finds an exact input whose protected output reaches the marketplace obligation, then submits one atomic checkout call. Checkout proves caller funding independently from ambient balances, swaps, pays only the marketplace charge, and after success boons the caller the full remaining balance of every snapshotted route asset. Society redemption uses the same successful-settlement boon policy while routing all available FAME into the chosen output.

Earlier iterations treated target-output support as a possible router change, described ordinary overfill with “protected” or “residue” terminology, preserved ambient balances through refund baselines, and accumulated local transaction retry/proof concepts. The implementation converged on narrower boundaries instead: invert the quote rather than execution, separate caller funding proof from successful full-balance boon distribution, and let wagmi own transaction lifecycle truth. (session history)

This implementation remains fork-only. Browser target sizing is the current fork-test implementation, while production deployment and moving target sizing behind a quote service remain separate release decisions (`docs/plans/2026-07-28-001-feat-atomic-marketplace-checkout-plan.md:16-34`).

## Guidance

### Keep the router exact-input; invert the quote

`FameRouter.executeRoute` pulls the route's declared input, executes every leg, computes the fee from gross output, and reverts when net output is below `minAmountOutAfterFee` (`src/FameRouter.sol:92-125`). That is the durable execution contract.

For a marketplace purchase, the quote layer should:

1. Select a route topology.
2. Find an upper input that proves the route can reach the required post-fee FAME output.
3. Retain that sufficient route and input as a valid witness.
4. Spend any remaining quote budget refining input downward on the same route.
5. Search for a new topology only if the selected route is actually invalid, exhausted, or unable to reach the target within its allowed range.

WWW implements this as target-output sizing over exact-input routes. It retains a sufficient upper witness before refinement (`../../../../fls-www/src/features/fame-swap/solver/targetOutput.ts:361-397`), refines without discarding that witness (`../../../../fls-www/src/features/fame-swap/solver/targetOutput.ts:427-491`), and materializes the retained topology into the final exact-input route (`../../../../fls-www/src/features/fame-swap/solver/targetOutput.ts:497-560`).

The contract remains the final guard. Purchase routes must output FAME to checkout, bind the expected recipient and deadline, and protect at least `fame.unit() + maxPremium` after router fees (`src/FameMarketplaceCheckout.sol:544-560`). An upper-bound quote gives the UI a usable route; these on-chain floors make under-delivery atomic and safe.

Do not add an exact-output router entrypoint merely because the marketplace knows its required FAME output. That would duplicate route schemas and venue behavior while leaving the same quote-search problem at the venue boundary.

### Give each layer one responsibility

| Layer | Responsibility |
| --- | --- |
| Quote layer | Find an exact input that reaches a target output and bind the route to current consent inputs. |
| `FameRouter` | Execute the declared exact input, enforce leg/final floors, charge its fee, and refund route-local leftovers. |
| `FameMarketplaceCheckout` | Fund one route, settle the marketplace obligation, apply the entrypoint's balance policy, and return/refund value. |
| `UniversalPoolArtMarketplace` | Enforce artwork, premium, buyer, inventory, and fulfillment rules. |
| wagmi | Own connector state, wallet submission, replacement, receipt, revert, rejection, and confirmation lifecycle. |
| Gallery UI | Explain the transaction, present wagmi state, invalidate domain queries, and project confirmed events for display. |

These boundaries keep product-specific target sizing out of the shared router and wallet-protocol state out of gallery reducers.

### Separate caller funding from the successful boon

Purchase checkout separates three amounts:

- the exact ETH, WETH, or USDC input funded for the route;
- the marketplace's unit plus gross premium charge; and
- the full post-settlement balance of every snapshotted route asset, including transaction-local surplus and ambient value.

Checkout computes the current marketplace charge, grants the marketplace only that amount, calls the typed `purchaseHeldFor` or `purchasePoolFor` entrypoint, clears the allowance, and verifies the measured debit (`src/FameMarketplaceCheckout.sol:395-427`).

Snapshots prove funding isolation; they are not balances that must survive success. Ambient ETH or ERC-20 value cannot satisfy the caller's declared route input, and ambient FAME cannot satisfy the protected marketplace output. After a purchase succeeds, checkout sends the full remaining balance of every snapshotted route asset to the buyer. If settlement or any boon transfer fails, the transaction reverts and all funding, swap, purchase, allowance, NFT, and balance changes roll back.

Therefore, if a route produces 1,040,000 FAME, the marketplace charges 1,030,000 FAME, and checkout already held 5,000 FAME, the successful buyer receives the full 15,000 FAME remainder. Only the route-produced 10,000 FAME participates in proving that this caller funded the charge; the ambient 5,000 FAME is a post-settlement boon.

Successful purchase must also finish with zero Society NFTs. Any directly donated Society NFT is consumed by settlement and its released backing FAME joins the same successful-caller boon. Failure at any point restores checkout's complete pre-call custody and every other pre-call balance; it does not return a prior donation to its sender.

### Treat extra route assets as a successful-settlement boon

“Surplus” and “ambient balance” are not synonyms, and unsolicited FAME is not automatically an attack.

#### Purchase and redemption refund policy: boon snapshotted route assets (finders-keepers)

After a **successful** `checkoutHeld` / `checkoutPool` or `redeemSociety`, checkout sends the **full remaining balance** of every asset in the route snapshot to the caller (latent ambient + transaction-local surplus). Assets not on the route stay put until a later successful call that snapshotted them. There is no owner rescue; dust is not buried forever on purpose.

Purchase FAME accounting separates caller funding from final distribution:

```text
preFundingFameBalance + routerFameOutput == marketplaceFameCharge + fullFameBoon
```

`preFundingFameBalance` includes any directly donated Society NFT's FAME
backing. Only `routerFameOutput` proves that the caller funded the protected
output. `fullFameBoon` is the complete post-settlement FAME balance transferred
after success.

#### Society redemption: all-in FAME, then boon residual route assets

After pulling the caller's selected Society NFTs, checkout measures its complete FAME balance (backing + ambient). Checkout copies the quoted route, replaces `amountIn` with this actual balance, approves exactly that amount, executes once, and clears the allowance. The route must contain exactly one final `All`-mode FAME-consuming leg. Success requires zero FAME and zero Society NFTs, then boons any residual snapshotted non-FAME (e.g. ambient WETH on a WETH out route) to the redeemer.

The policy still fails closed on quote/pull/route/inventory errors (full atomic revert).

### Let wagmi own transaction truth

Frontend application state should describe the wagmi lifecycle, not compete with it:

```text
simulate a fresh consent-bound request once
  -> request wallet signature through wagmi
  -> retain the submitted hash for display
  -> wait for one receipt through wagmi
  -> let wagmi/viem resolve replacements and surface its canonical receipt or error
  -> invalidate application queries after success
```

The redemption hook uses `@wagmi/core`'s `waitForTransactionReceipt` with the active config, chain, hash, and confirmation count (`../../../../fls-www/src/features/fame-gallery/hooks/useGalleryRedemption.ts:297-308`). It reuses a cached simulation only while its consent key is unchanged, writes once, waits for one confirmation, and refreshes queries after success (`../../../../fls-www/src/features/fame-gallery/hooks/useGalleryRedemption.ts:175-197`). Tests explicitly require no retry on simulation or wallet failure and delegate replacement/receipt semantics to wagmi (`../../../../fls-www/src/features/fame-gallery/hooks/useGalleryRedemption.test.ts:77-132`). Purchase tests likewise require one write after a receipt failure (`../../../../fls-www/src/features/fame-gallery/transactions/purchaseQueue.test.ts:246-260`).

Use the repository's existing `TransactionsModal` to present this lifecycle. Do not add:

- automatic transaction resubmission;
- home-grown replacement detection;
- extra confirmation counters for a Base sequencer flow;
- persisted “proof” records;
- mock fork-wallet identity as a second account source;
- a second receipt state machine that can disagree with wagmi.

Domain receipt interpretation is still useful. A post-transaction page may use wagmi to fetch the canonical receipt and project marketplace, checkout, router, transfer, and metadata events for presentation. That projection is not a competing confirmation protocol and must not trigger a retry.

Event projection must preserve normalized settlement semantics. Prefer
`CheckoutSettled.marketplaceFameCharge` for the full FAME charge and
`ArtworkPurchased.grossPremiumAmount` for the full configured premium executed
through the premium-transfer path. Count payer-to-self community or provider
legs in `grossPremiumAmount`; it is not the buyer's net debit. `SocietyRedeemed` emits both
`submittedRouteHash` (quoted route) and `executedRouteHash` (`amountIn` adjusted
to actual FAME).

Read fallbacks are also different from transaction retries. Retrying a provider-limited ownership `eth_call` in smaller block-pinned ranges is safe read behavior. Resubmitting a wallet write because receipt waiting failed can duplicate user intent and is not allowed.

## Why This Matters

Preserving exact-input execution keeps one router schema and one set of venue adapters. The quote layer can answer a target-output product question while contracts continue enforcing explicit input, per-leg floors, post-fee final output, recipient, and deadline. A sufficient upper witness provides a usable route early; refinement improves price without making the user wait for perfection.

Atomic swap, charge, purchase, and refund behavior avoids the dangerous intermediate state of a two-transaction flow where the user owns newly swapped FAME after the artwork, premium, or eligible shell has changed. Any stale floor, artwork mismatch, failed payment, failed NFT transfer, or failed refund reverts the whole transaction.

The single boon policy makes unsolicited tokens unsurprising. Ambient balances cannot satisfy caller funding or protected marketplace output, but after a successful purchase or redemption every snapshotted route asset's full remainder belongs to that caller. The security boundary is success: any failure fully rolls back, while success leaves zero Society NFTs, zero FAME, and zero residual marketplace/router allowances in checkout.

Finally, wagmi already models the wallet protocol. Duplicating it creates split-brain states where the application claims a transaction is pending, replaced, failed, or unverified while the connected wallet stack knows otherwise. Thin product state plus domain query invalidation is easier to reason about and more accurate.

## When to Apply

- A fixed output-denominated obligation must be funded through a shared exact-input router.
- A swap and marketplace action must both settle or both revert.
- Variable swap output should benefit the caller instead of accumulating in an intermediary.
- A coordinator can receive unsolicited assets and each public path needs an explicit balance policy.
- A wagmi application needs domain-specific transaction copy without rebuilding wallet transaction handling.

Do not infer production readiness from this pattern. Production deployment, public address configuration, release approval, and moving quote computation behind a service remain separate gates.

## Examples

### Target-output purchase over exact-input execution

```text
market requirement = fame.unit() + maxPremium
selected topology  = ETH -> ... -> FAME

find sufficient upper amountIn
retain that route as soon as post-fee FAME >= requirement
refine amountIn downward on the same topology while budget remains

checkout:
  execute exact-input route once
  pay fame.unit() + grossPremium
  purchase selected artwork
  boon full remaining balances of all snapshotted route assets
```

No exact-output route executes. The quote layer only found an exact input whose protected post-fee output is sufficient.

### Existing FAME improves a Society redemption

```text
selected NFT backing       = 2,000,000 FAME
existing checkout FAME     =   250,000 FAME
quoted basis               = 2,250,000 FAME
actual balance after pulls = 2,250,000 FAME or more

copy route.amountIn = actual balance
consume FAME through the final All-mode leg
send ETH, WETH, or USDC directly to the redeemer
require checkout FAME and Society balances == 0
```

The extra 250,000 FAME is not trapped and is not swept to an administrator. It improves the next successful redemption. If another redemption consumes it first, the stale transaction reverts before any NFT burn persists.

### Rejected anti-patterns

```text
Wrong: rewrite FameRouter as exact-output for one marketplace feature.
Wrong: add rescue roles because somebody can donate FAME.
Wrong: retry a wallet transaction after a receipt error.
Wrong: maintain local replacement or proof state beside wagmi.

Right: exact-input route plus protected post-fee output.
Right: prove caller funding without ambient balances, then boon all snapshotted route-asset remainders after success.
Right: require zero checkout Society NFTs and FAME after successful settlement.
Right: wagmi/viem receipt, replacement resolution, and error state is authoritative.
```

## Related

- [Atomic Marketplace Checkout Plan](../../plans/2026-07-28-001-feat-atomic-marketplace-checkout-plan.md)
- [FAME Router Schema](../../router/fame-router-schema.md)
- [FAME Multi-Leg Router Plan](../../plans/2026-05-11-001-feat-fame-multi-leg-router-plan.md)
- [Keep Generated Deployment Artifacts Out Of The Repo](../workflow-issues/keep-generated-deployment-artifacts-out-of-repo-2026-05-15.md)
