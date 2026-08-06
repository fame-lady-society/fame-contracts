---
date: 2026-06-21
topic: closed-loop-gallery-swap
status: superseded
superseded_date: 2026-08-06
superseded_by: UniversalPoolArtMarketplace + FameMarketplaceCheckout
---

# Closed-Loop Gallery Swap Requirements

> **Superseded (2026-08-06).** Product surface removed; kept as historical requirements only. See `docs/gallery/marketplace-checkout-review-decisions.md` (D1).

## Summary

Build a protocol-only gallery swap for curated Society NFTs. A buyer fills a listed gallery piece by paying one FAME unit plus a FAME premium, and the fill only succeeds if protocol Society NFT inventory does not decrease.

---

## Problem Frame

The product should let users choose from a rotating set of protocol-owned Society NFTs without turning CreatorMagic into a broad marketplace. The key promise is not merely that the protocol can sell stock; it is that a completed fill preserves the gallery loop so the protocol does not drain its curated inventory.

FAME is a DN404-style hybrid where one Society NFT corresponds to one `1_000_000 * 10 ** 18` FAME unit. A mirror NFT transfer also moves one unit of FAME from NFT sender to recipient, so the gallery swap must treat the selected NFT as a unit-backed object rather than a normal standalone ERC721.

---

## Key Decisions

- **Protocol-owned inventory only for V1.** Holder listings, consignment, and peer seller flows are excluded so V1 can prove the closed-loop mechanism before taking on stale listings, seller approvals, and cancellation semantics.
- **Inventory non-decrease is an atomic fill invariant.** A fill must not rely on later operator rebalancing; if the protocol inventory count would drop, the fill should not complete.
- **FAME premium is the protocol fee.** The buyer posts one full FAME unit plus a premium; the premium is the protocol's economic upside while the unit maintains the backing loop.
- **CreatorMagic is adjacent, not the settlement surface.** CreatorMagic can inform which art is curated into the gallery, but V1 does not expose arbitrary metadata purchase or pool selection as the marketplace action.

---

## Actors

- A1. Buyer: a wallet that wants a selected protocol-owned Society NFT and can fund the fill in FAME.
- A2. Gallery vault: the protocol-controlled holder of curated Society NFTs and received FAME.
- A3. Protocol operator: the party that curates listed inventory, sets premiums, and removes unavailable pieces.
- A4. Planner or implementer: the downstream reader who must preserve DN404 unit and inventory semantics while designing the contract.

---

## Key Flows

- F1. Gallery fill
  - **Trigger:** A buyer chooses an available protocol-owned Society NFT from the rotating gallery.
  - **Actors:** A1, A2
  - **Steps:** The buyer provides FAME equal to one unit plus the listed premium; the gallery vault receives the FAME; the selected Society NFT transfers to the buyer only if the vault's Society NFT inventory is not lower after the fill.
  - **Outcome:** The buyer receives the selected Society NFT, the protocol retains non-decreased Society NFT inventory, and the premium remains as protocol revenue.
  - **Covered by:** R1, R2, R3, R4, R5

- F2. Gallery curation
  - **Trigger:** The protocol operator wants to expose or rotate available gallery pieces.
  - **Actors:** A2, A3
  - **Steps:** The operator lists only protocol-owned Society NFTs, assigns each a FAME premium, and removes pieces that are unavailable or should no longer be offered.
  - **Outcome:** Buyers see a curated set of real transferable Society NFTs rather than arbitrary CreatorMagic metadata pool entries.
  - **Covered by:** R6, R7, R8

---

## Requirements

**Gallery Scope**

- R1. V1 must list only Society NFTs owned by the protocol-controlled gallery vault.
- R2. V1 must not support holder-owned listings, consignment, peer-to-peer sales, or buyer-selected metadata pool entries.
- R3. Each listed gallery piece must have a FAME premium above one full FAME unit.

**Fill Semantics**

- R4. A fill must require the buyer to provide one FAME unit plus the listed FAME premium.
- R5. A fill must transfer the selected protocol-owned Society NFT to the buyer only when the protocol Society NFT inventory count after settlement is greater than or equal to the count before settlement.
- R6. A fill must fail rather than complete as a stock-draining sale when the non-decrease invariant cannot be satisfied.
- R7. A fill must leave the premium attributable to the protocol as fee revenue.

**DN404 Safety**

- R8. The requirements and later plan must account for DN404 side effects from FAME transfers, including sender NFT burns, recipient NFT mints, direct NFT transfers, and `skipNFT` state.
- R9. The buyer experience must not imply that Society NFTs behave like ordinary standalone ERC721s.
- R10. The vault behavior must be designed so received FAME and transferred Society NFTs preserve the gallery inventory invariant.

**Curation and Metadata**

- R11. The gallery must expose a rotating curated set of protocol-owned Society NFTs, not the full unminted pool, burn pool, or art pool.
- R12. CreatorMagic metadata operations must not be exposed as public purchase settlement in V1.
- R13. Any future use of CreatorMagic to prepare gallery pieces must stay operator-controlled and must not grant buyers broad metadata write authority.

**Observability and Failure**

- R14. A downstream implementation must make it observable whether a fill preserved protocol Society NFT inventory.
- R15. Unavailable, transferred, or invariant-breaking gallery pieces must fail cleanly rather than partially settling.
- R16. Premium, unit amount, selected token, and recipient must be unambiguous enough for offchain UIs and reviewers to explain the transaction.

---

## Acceptance Examples

- AE1. **Covers R4, R5, R7.** Given the vault has a listed Society NFT and the fill can preserve the vault's Society NFT count, when the buyer fills with one FAME unit plus premium, then the buyer receives the selected NFT and the premium remains protocol revenue.
- AE2. **Covers R5, R6.** Given a selected gallery NFT would leave the vault with fewer Society NFTs after settlement, when a buyer attempts to fill it, then the fill does not complete.
- AE3. **Covers R1, R2, R11.** Given a token is not owned by the protocol vault, when it appears in an offchain candidate set, then V1 must not treat it as fillable gallery inventory.
- AE4. **Covers R8, R10.** Given a FAME transfer would interact with DN404 mint, burn, direct-transfer, or `skipNFT` behavior, when planning settlement, then the plan must preserve the inventory invariant under that behavior rather than assuming plain ERC20 semantics.
- AE5. **Covers R12, R13.** Given CreatorMagic can update token metadata through role-gated functions, when a buyer fills a gallery piece, then the buyer must not receive general metadata mutation authority.

---

## Success Criteria

- The V1 requirements can be planned without inventing whether holder listings are included.
- The V1 mechanism has a clear invariant: completed fills do not reduce protocol Society NFT inventory.
- Reviewers can trace why DN404 unit mechanics are load-bearing for the product.
- The product can be described as a curated protocol gallery without implying a general NFT marketplace.

---

## Scope Boundaries

Deferred or outside V1:

- Holder listings, consignment, peer order books, and seller cancellation flows.
- Generic selection from unminted, burned, or art-pool metadata.
- Public metadata purchase, arbitrary CreatorMagic mutation, or buyer-directed metadata writes.
- Wrapped `gSOCIETY` trading and governance-lock behavior.
- Seaport, OpenSea, or other third-party marketplace listing support as a V1 promise.
- Operational post-fill rebalancing as a substitute for the atomic inventory invariant.

---

## Dependencies / Assumptions

- The protocol has or can establish a gallery vault that owns curated Society NFTs.
- The vault can be configured or designed around FAME `skipNFT` behavior.
- The implementation can measure protocol Society NFT inventory before and after fill settlement.
- Premiums are denominated in FAME for V1.
- Public Base deployment addresses remain in `config/fame-public.env`; secrets remain in Doppler.

---

## Outstanding Questions

Resolve during planning:

- What exact inventory count is authoritative for the invariant when FAME transfer mechanics move, mint, or burn mirror NFTs?
- Should the premium have a protocol-defined minimum, operator-defined value per token, or both?
- Which account receives the premium, and does it need to avoid holding additional mirror NFTs?
- How should unavailable gallery items be represented to offchain UIs?

---

## Sources / Research

- `docs/ideation/2026-06-21-creator-magic-fame-society-marketplace-ideation.html` — source ideation artifact and ranked option.
- `src/Fame.sol` — FAME unit size and role-gated `skipNFT` management.
- `src/DN404.sol` — DN404 ERC20 and mirror NFT transfer behavior.
- `src/DN404Mirror.sol` — mirror transfer path into DN404 base transfer.
- `src/CreatorArtistMagic.sol` — metadata pool and role-gated metadata behavior.
- `src/GovSociety.sol` — wrapped Society NFT alternative rejected for V1.
- `config/fame-public.env` — public Base FAME and Society NFT deployment constants.
