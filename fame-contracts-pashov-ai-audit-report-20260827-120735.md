# 🔐 Security Review — Universal Marketplace

---

## Scope

|                                  |                                                                               |
| -------------------------------- | ----------------------------------------------------------------------------- |
| **Mode**                         | filename                                                                      |
| **Files reviewed**               | `UniversalPoolArtMarketplace.sol` · `FameMarketplaceCheckout.sol`             |
| **Confidence threshold (1-100)** | 80                                                                            |

---

## Findings

[100] **1. [Low] Redemption branches bypass router fees** [agents: 1]

`FameMarketplaceCheckout._validateRedemptionRoute` · Confidence: 100

**Description**
An unprivileged redeemer can convert nearly all FAME through an earlier exact leg, leave dust for the fee-bearing final leg, and receive the large intermediate output fee-free through refunds; impact is limited to router-fee revenue.

**Fix (Option A — restrict)**

```diff
- Permit earlier Exact FAME-input legs before the final All leg.
+ Require a fully merged linear All-balance path ending in route.tokenOut.
```

**Fix (Option B — fee all outputs)**

```diff
- Refund transaction-produced non-final assets without assessing router fees.
+ Reject or charge fees on every transaction-produced non-final asset before refund.
```

---

[90] **2. [Low–Medium] Provider payouts can censor particular pool artwork** [agents: 3]

`UniversalPoolArtMarketplace._executePoolPurchase` · Confidence: 90

**Description**
A threshold-positioned provider can make its premium payment mint the selected DN404 source before consumption, forcing a revert whose rollback restores the censorship state; this denies purchases of particular prepared source IDs without stealing funds.

**Fix (Option A — reclassify)**

```diff
+ Replace the stale comparison with `purchase.path = _requirePoolSource(purchase.sourceId);` after premium distribution, while continuing to reject a source that became owned or otherwise ineligible.
```

**Fix (Option B — consume before payment)**

```diff
+ Move `_distributePremium` until after `banishToMintPool`/`banishToBurnPool` and the immediate artwork-swap postconditions, so payout-induced DN404 mints cannot invalidate the source before consumption.
```

---

[90] **3. [Low] Bonus redemption input retains stale slippage floors** [agents: 1]

`FameMarketplaceCheckout._executeRedemptionRoute` · Confidence: 90

**Description**
When ambient FAME enlarges redemption input, only `amountIn` changes, so unchanged minimums let a sandwich attacker extract donated bonus value while the redeemer still receives their originally quoted minimum.

**Fix**

```diff
- executedRoute.amountIn = actualFameInput;
+ if (actualFameInput != route.amountIn) revert RedemptionInputMismatch(route.amountIn, actualFameInput);
```

---

[75] **4. [Informational] Sybil addresses can monopolize provider admission** [agents: 4]

`UniversalPoolArtMarketplace._providerPositionForDeposit` · Confidence: 75

**Description**
One actor can split `activeProviderCap` units across addresses, occupy every permanent slot, exclude later providers, and collect all provider fees, but materiality depends on the capital cost and whether first-come admission is intentional.

---

Findings List

| # | Confidence | Title |
|---|---|---|
| 1 | [100] | [Low] Redemption branches bypass router fees |
| 2 | [90] | [Low–Medium] Provider payouts can censor particular pool artwork |
| 3 | [90] | [Low] Bonus redemption input retains stale slippage floors |
| 4 | [75] | [Informational] Sybil addresses can monopolize provider admission |

---

## Leads

_Vulnerability trails with concrete code smells where the full exploit path could not be completed in one analysis pass. These are not scored findings._

- **Router output is not independently measured** — `FameMarketplaceCheckout._executeRedemptionRoute` — Code smells: redemption trusts the router's reported recipient output; canonical-router or venue misreporting remains unverified.
- **Checkout can emit a stale fulfillment path** — `FameMarketplaceCheckout._checkout` — Code smells: routing can change DN404 classification before marketplace settlement, producing conflicting checkout and marketplace events without demonstrated asset loss.
- **Withdrawal premium can self-rebate** — `UniversalPoolArtMarketplace.withdrawInventory` — Code smells: a withdrawing provider's remaining units receive part or all of their own provider premium; no independent victim was established.
- **Selected withdrawals exchange generic shell claims** — `UniversalPoolArtMarketplace.withdrawInventory` — Code smells: providers may exchange deposited shells for other shells after maturity, but external value disparity was not proven and the behavior is intentional prior art.
- **Future provider caps may exceed gas limits** — `UniversalPoolArtMarketplace.constructor` — Code smells: the source accepts 888 providers while only the current 88-provider configuration has gas evidence.
- **Later route legs may reintroduce FAME** — `FameMarketplaceCheckout._validateRedemptionRoute` — Code smells: a later leg can recreate FAME after the required all-FAME leg, but the value returns to the caller and no third-party harm was demonstrated.

---

No critical or high-severity issue was identified. These findings do not justify an emergency pause or block the planned vault migration and ownership reassignment. Findings 1–3 are suitable hardening work for the next planned marketplace deployment.

This review assessed the checked-out source. It did not verify deployed bytecode, current on-chain configuration, ownership, balances, or live exploitability.

> ⚠️ This review was performed by an AI assistant. AI analysis can never verify the complete absence of vulnerabilities and no guarantee of security is given. Team security reviews, bug bounty programs, and on-chain monitoring are strongly recommended. For a consultation regarding your projects' security, visit [https://www.pashov.com](https://www.pashov.com)
