# Marketplace / Checkout Review Decisions

**Branch:** `codex/closed-loop-gallery-swap`  
**Review run:** `20260805-211740-f497` (vs `origin/main`)  
**Started:** 2026-08-05  
**Status:** In progress

Decision vocabulary:

| Decision | Meaning |
|----------|---------|
| **Accept** | Do the suggested fix as written |
| **Accept with updates** | Do it, with noted changes to the approach |
| **Discuss** | Need more context before deciding |
| **Reject** | Do not act; intentional or out of scope |
| **Applied** | Already landed in tree |
| **Superseded** | Closed by a broader decision (no separate fix) |

---

## Accepted product decisions

### D1. Remove `ClosedLoopGallerySwap` entirely

**Decision:** **Accept** (2026-08-05)  
**Rationale:** Closed-loop gallery swap was an earlier product surface. It is **superseded by** `UniversalPoolArtMarketplace` (+ `FameMarketplaceCheckout` for multi-asset atomic settlement). Do not fix gallery fee accrual / `feeRecipient` wiring; delete the stack instead.

**Removal scope (expected):**

| Area | Paths |
|------|--------|
| Contract | `src/ClosedLoopGallerySwap.sol` |
| Scripts | `script/DeployClosedLoopGallerySwap.s.sol`, `script/ValidateClosedLoopGallerySwapBase.s.sol` |
| Tests | `test/ClosedLoopGallerySwap*.sol`, `test/mocks/ReentrantGalleryRecipient.sol` (if gallery-only) |
| Docs | `docs/gallery/closed-loop-gallery-swap.md`, plan/brainstorm as historical or mark superseded |
| Config / CONCEPTS | Any public env keys, release-plan bullets, CONCEPTS entries that still describe live ClosedLoop deployables |

**Follow-ups when implementing removal:**

- [x] Delete source, scripts, tests, gallery-only mocks (incl. Base Sepolia gallery test stack + `BaseSepoliaTestRenderer`)
- [x] Clean `docs/fame-release-plan.md`, `config/fame-public.env`, operational gallery docs
- [x] Mark plan/brainstorm superseded
- [x] Handoffs that already say “do not preserve closed-loop assumptions” left as historical guidance

**Review findings closed by D1 (no separate fix):**

| # | Title | Why superseded |
|---|--------|----------------|
| 1 | Accrued gallery fees lock behind inventory invariant | Delete vault; do not redesign fee withdraw |
| 5 | `feeRecipient` never routes gallery fees | Delete contract |
| 17 | Gallery Base fork skips without RPC | Applied fail-closed already; file removed with stack |

---

## Already applied (review fix commit)

Commit: `ff55da1` — `fix(review): align checkout pause/art-pool errors and fail-closed Base fork`

| # | Decision | Summary |
|---|----------|---------|
| 3 | **Applied** | Checkout pause error → `PurchasesPaused` (match market + WWW table) |
| 4 | **Applied** | Art-pool preflight → `ArtPoolSourceExcluded` (match market) |
| 17 | **Applied** then **Superseded by D1** | ClosedLoop Base fork fail-closed; removal will drop the test file |

---

## Open items — decision log

Fill **Decision** / **Notes** as we walk. Implementation status tracked separately.

### Marketplace + checkout (primary)

| # | Sev | Item | Suggested action | Decision | Notes |
|---|-----|------|------------------|----------|-------|
| 2 | P1 | Checkout accounting fail-closed paths untested | Unit tests for `RouterOutputMismatch`, charge/accounting/ambient/mirror/refund mismatches | **Accept** | 2026-08-06 — tests only; exact selectors + full rollback |
| 6 | P2 | `ArtworkPurchased.premiumAmount` ≠ amount paid | Emit measured paid premium (or add paid field) | **Accept (a)** | 2026-08-06 — ABI/semantic: emit actual premium debited, not only configured spot premium |
| 7 | P2 | Fee recipient skipNFT flip freezes settlement | Remove `FeeRecipientNotSkippingNFT` / skip requirement on fee recipient | **Accept with updates** | 2026-08-06 — do not reject fee recipients that can mint NFTs; drop skipNFT gate on feeRecipient |
| 8 | P2 | `AmbiguousPoolSource` never exercised | Unit test dual mint+burn eligibility | **Accept** | 2026-08-06 — market + checkout |
| 9 | P2 | Bare `expectRevert` in checkout tests | Pin exact selectors | **Accept** | 2026-08-06 |
| 10 | P2 | Invariant handler never calls `checkoutPool` | Add pool mint/burn actions to handler | **Accept** | 2026-08-06 |
| 11 | P2 | `CheckoutSettled` omits pool `sourceId` / artwork | Add `sourceId` + artwork fields to event | **Accept (a)** | 2026-08-06 — ABI: checkout-only receipts for pool path |
| 12 | P2 | `redeemSociety` reentrancy untested | Reentrancy test like checkoutHeld | **Accept** | 2026-08-06 |
| 13 | P2 | Redemption `routeHash` uses adjusted `amountIn` | Emit both submitted + executed route hashes | **Accept (a)** | 2026-08-06 — ABI: dual hash on SocietyRedeemed (or equivalent) |
| 14 | P2 | Duplicate refund loops (checkout vs redemption) | Consolidate; refund all route assets (shared helper) | **Accept with updates** | 2026-08-06 — consolidate logic; refund all route assets (align purchase/redemption surplus policy per operator) |
| 15 | P2 | Duplicate route-header validation | Shared private header helper | **Accept** | 2026-08-06 |
| 16 | P2 | Deposit-to-snipe rare shell | Document as intentional universal-pool risk | **Accept with updates (b)** | 2026-08-06 — docs only; open pool is product |
| 18 | P3 | Public `purchaseHeld` snipes checkout shell | On-chain lock / docs / reject as known contention | **Reject** | 2026-08-06 — atomic revert; gas/UX only; open market intentional |
| 19 | P3 | Near-threshold provider mints inflate gas | Keep benchmark gates; optional pull-payment later | **Reject (c)** | 2026-08-06 — no action; existing benchmark/cap posture sufficient |
| 20 | P3 | Marketplace reentrancy asserts any non-empty revert | Assert `SettlementInProgress` / guard selector | **Accept** | 2026-08-06 |

### ClosedLoop (secondary — closed by D1 unless noted)

| # | Sev | Item | Decision | Notes |
|---|-----|------|----------|-------|
| 1 | P1 | Fee lock / inventory invariant | **Superseded by D1** | Remove stack |
| 5 | P2 | Unused `feeRecipient` | **Superseded by D1** | Remove stack |
| 17 | P3 | Fork skip without RPC | **Applied** + **Superseded by D1** | |

### Residual risks (not numbered findings; decide if action needed)

| ID | Topic | Decision | Notes |
|----|--------|----------|-------|
| R1 | Ambient / mistaken assets on checkout | **Accept: boon (surface 3)** | 2026-08-06 — finders-keepers on **either** successful purchase or redemption (first claim wins). No forever-lock for ambient route assets. Implement with #14: consolidate refund; successful caller receives latent + tx-local surplus. Document as intentional MEV/tip-jar. |
| R2 | Ambient FAME on checkout is next-redeemer bonus | **Intended** | 2026-08-06 — no action |
| R3 | `activeProviderCap` immutable; prod 88 gas-qualified | **Intended** | 2026-08-06 — no action |
| R4 | Trusted roles (owner, SKIP_MANAGER, BANISHER, router) | **Intended** | 2026-08-06 — no action |
| R5 | Fee-recipient community fee waiver | **Accept: remove waiver** | 2026-08-06 — treat feeRecipient like any other purchaser; drop buyer==feeRecipient branches in `purchaseCharge` / `_distributePremium`. No special case; self-pay community fee is fine. Fix handoff prose that claimed “unit only.” |

---

## Walk order (operator)

1. Confirm D1 removal scope (this section) — **accepted**
2. #2 accounting tests (P1)
3. #6 / #11 / #13 event & receipt contract (integrator-facing)
4. #7 / #16 / #18 / #19 product/ops risk
5. #8 / #9 / #10 / #12 / #20 test hardening
6. #14 / #15 pure refactors
7. Residual risks R1–R5
8. Schedule implementation PR(s): removal PR, then test/docs PR, then optional event ABI PR

---

## Implementation tracking

| Workstream | Decision refs | Status |
|------------|---------------|--------|
| Delete ClosedLoopGallerySwap stack | D1, #1, #5, #17 | Done (removal commit) |
| Checkout accounting + selector tests | #2, #8, #9, #12, #20 Accept | Not started |
| Invariant pool coverage | #10 Accept | Not started |
| Event/receipt ABI | #6, #11, #13 Accept (a) | Not started |
| Drop feeRecipient skipNFT requirement | #7 Accept with updates | Done |
| Remove fee-recipient buyer waiver | R5 Accept | Done |
| Docs: deposit sniping intentional | #16 (b) | Not started |
| #18 shell contention | Reject | Closed |
| #19 provider mint gas | Reject | Closed |
| Checkout refund policy (boon + consolidate) | #14 + R1 surface 3 | Done |
| Shared route-header helper | #15 Accept | Done |

---

## Changelog

| Date | Change |
|------|--------|
| 2026-08-05 | Doc created. D1 accept: remove ClosedLoopGallerySwap. Applied #3/#4/#17 recorded. Open items pending walk-through. |
| 2026-08-06 | #2 Accept — checkout accounting fail-closed path unit tests. |
| 2026-08-06 | #6/#11/#13 Accept (a) — measured premium on ArtworkPurchased; CheckoutSettled source/artwork fields; dual redemption route hashes. |
| 2026-08-06 | #7 Accept with updates — remove FeeRecipientNotSkippingNFT (allow fee recipients that mint NFTs). #16 Accept (b) docs. #18 Discuss. #19 Reject. |
| 2026-08-06 | #18 Reject — open-market shell contention is gas/UX only under atomic checkout; no code change. |
| 2026-08-06 | #8/#9/#10/#12/#20 Accept — test hardening batch. |
| 2026-08-06 | #14/#15 Discuss; R1 Discuss; R2–R4 Intended; R5 Discuss (handoff vs purchaseCharge). |
| 2026-08-06 | #14 Accept with updates (refund all route assets, consolidate). #15 Accept. R1/R5 still Discuss (boon vs snapshot; feeRecipient waiver rationale). |
| 2026-08-06 | R1 Accept: boon latent assets rather than bury forever; couples with #14 policy redesign. R5 still open. |
| 2026-08-06 | R1 surface **3**: boon on either successful purchase or redemption (first claim wins). Operator notes UniswapV2 Router dust is negligible in practice. |
| 2026-08-06 | R5 Accept: remove fee-recipient buyer special case; same charge/premium path as all buyers. |
| 2026-08-06 | D1 implemented: removed ClosedLoop + Base Sepolia gallery test stack from tree; superseded notes on plans/brainstorms/ops docs. |
| 2026-08-06 | R5 + #7 implemented: no buyer fee waiver; no fee-recipient skipNFT gate; scripts/tests/handoffs updated. |
| 2026-08-06 | #14 + R1 implemented: consolidated `_refundSnapshottedBalances` boons full route-asset balances on purchase/redemption success. |
| 2026-08-06 | #15 implemented: `_validateSharedRouteHeader` for purchase + redemption. |
