---
title: Closed-Loop Gallery Swap
date: 2026-06-28
module: closed-loop-gallery-swap
---

# Closed-Loop Gallery Swap

The closed-loop gallery swap is a protocol-controlled way to sell curated FAME Society NFTs without draining protocol inventory. Buyers fill a listed vault-owned Society NFT for one FAME unit plus a positive FAME premium. A fill succeeds only when the gallery vault's Society NFT balance after settlement is greater than or equal to its balance before settlement.

## Contracts

- `ClosedLoopGallerySwap` owns the gallery inventory, stores listings, settles fills, records accrued protocol fees, and exposes operator-only CreatorMagic rotation calls.
- `Fame` is the DN404 base token. One Society NFT corresponds to `fame.unit()`.
- `FameMirror` is the Society NFT mirror used for ownership, listing eligibility, and inventory checks.
- `CreatorArtistMagic` remains the metadata rotation surface. The gallery vault calls its swap-style functions as the token owner; buyers never call CreatorMagic through the fill path.

## Buyer Fill Flow

1. UI reads active listings from the gallery contract and confirms the vault still owns the listed token.
2. Buyer approves `fame.unit() + premium` FAME to the gallery.
3. Buyer calls `fill(tokenId, recipient)`.
4. The gallery snapshots its Society NFT balance.
5. The gallery pulls FAME from the buyer.
6. The gallery safe-transfers the selected Society NFT to the recipient.
7. The gallery records the premium as accrued protocol fee revenue.
8. The gallery verifies its Society NFT balance did not decrease.

The premium stays in the vault during fill. Any later fee withdrawal must preserve the vault's Society NFT inventory and can revert if moving FAME would burn or direct-transfer a mirror NFT out of the vault.

## Operator Rotation

Operators rotate art only for tokens the vault currently owns. The gallery contract is the CreatorMagic caller because CreatorMagic checks `msg.sender` ownership on swap-style paths.

The intended CreatorMagic role posture is:

- Gallery vault has `BANISHER` and `ART_POOL_MANAGER`.
- Gallery vault does not have `CREATOR` unless governance explicitly accepts direct metadata authority.
- Unexpected `CREATOR` role holders are production metadata authorities because `updateMetadata` is role-gated but not owner-gated.

The gallery exposes operator rotation helpers for:

- art-pool rotation;
- end-of-mint-pool rotation;
- mint-pool swaps;
- burn-pool swaps.

The buyer fill path does not call CreatorMagic and does not expose direct `updateMetadata`.

## UI Contract

UIs should treat a listing as fillable only when:

- `listings(tokenId).active` is true;
- `listings(tokenId).premium` is greater than zero;
- `FameMirror.ownerOf(tokenId)` is the gallery vault;
- the displayed total price is `fame.unit() + premium`.

UIs should show that Society NFTs are DN404 mirror NFTs backed by FAME unit accounting. They should not describe them as ordinary standalone ERC721s.

The `Filled` event includes:

- buyer;
- recipient;
- token ID;
- unit amount;
- premium;
- vault Society NFT balance before settlement;
- vault Society NFT balance after settlement.

Those before/after balances are the observable proof that the closed-loop invariant held for the fill.

## Launch Gates

Before launch:

- Set public deployment values in `config/fame-public.env`.
- Keep deployer keys, RPC URLs, and explorer keys in Doppler.
- Confirm `BASE_CREATOR_ARTIST_MAGIC_ADDRESS`; do not invent or reuse an unverified address.
- Deploy with `script/DeployClosedLoopGallerySwap.s.sol`.
- Confirm `getSkipNFT(gallery) == false`.
- Confirm the vault has the narrow CreatorMagic roles required for swap rotation.
- Confirm the vault does not have CreatorMagic `CREATOR` unless governance accepts that trust surface.
- Confirm expected owner, operator, and fee recipient addresses.
- Run `script/ValidateClosedLoopGallerySwapBase.s.sol` on Base.
- Record the deployed gallery address in `config/fame-public.env`.
- Do not commit Foundry `broadcast/` logs.

## Operational Notes

- List only vault-owned Society NFTs.
- If a listed token leaves the vault, fills for that token revert until the listing is repaired or removed.
- Fee withdrawals can revert when moving FAME would reduce the vault's Society NFT balance.
- Rescue cannot move listed Society NFTs and cannot rescue FAME through the generic ERC20 rescue path.
- Direct CreatorMagic role-holder changes should be treated as production metadata-authority changes, not as harmless admin cleanup.
