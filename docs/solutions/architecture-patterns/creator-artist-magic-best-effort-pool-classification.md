---
title: CreatorArtistMagic Best-Effort Pool Classification
date: 2026-08-11
category: docs/solutions/architecture-patterns
module: CreatorArtistMagic
problem_type: architecture_pattern
component: metadata-marketplace
severity: high
applies_when:
  - CreatorArtistMagic must distinguish unowned burned IDs from unowned revealed mint-pool IDs.
  - The deployed DN404 contract exposes live total NFT supply but not its historical next-token frontier.
  - A migration observes a frontier that will change after later mints or burns.
related_components:
  - Fame
  - FameMirror
  - UniversalPoolArtMarketplace
  - fls-www gallery
tags:
  - creator-artist-magic
  - dn404
  - mint-pool
  - burn-pool
  - live-supply
  - best-effort
---

# CreatorArtistMagic Best-Effort Pool Classification

## Context

An unowned Society token ID is ambiguous. It may never have minted, or it may have minted and later burned. `FameMirror.ownerOf` distinguishes owned from unowned, but it does not preserve that history. The deployed FAME contract exposes DN404's live `totalNFTSupply()` while its monotonically assigned next-token frontier remains private.

V2 therefore used live supply as an observable proxy. V3 briefly replaced that proxy with the migration-time frontier `592`. That made the observed burned high IDs classify correctly at the migration block, but the frozen value could not advance when DN404 later assigned fresh sequential IDs. It traded one approximation for a permanently stale boundary.

## Decision

Retain the V2-compatible live classifier:

```text
burn pool = unowned && tokenId <= totalNFTSupply && outside art pool
mint pool = unowned && tokenId > totalNFTSupply && tokenId < nextTokenId && outside art pool
```

`getMintPoolStart()` returns `totalNFTSupply() + 1`. Because the inequalities are complementary, a token can never be in both pools.

This is explicitly best-effort:

- Fresh sequential NFT mints increase `totalNFTSupply()`, so the inferred boundary advances automatically.
- Burns decrease `totalNFTSupply()`, so the inferred boundary can move backward.
- While burned IDs are waiting to be reminted, a historically minted high ID can be classified as Mint Pool.
- Art Pool membership and current ownership remain exact exclusions.

Do not reintroduce a constructor frontier or a migration-time constant to classify pools. Values such as `592` are useful observations for validating a particular chain snapshot, not permanent contract state.

## Why Exact Classification Is Not Available

Exact automatic classification needs a source of historical mint truth: a public monotonically increasing DN404 frontier, an explicit `everMinted(tokenId)` view, or a hook that updates CreatorArtistMagic whenever DN404 assigns a fresh ID. The deployed FAME interface provides none of those. CreatorArtistMagic cannot reconstruct lost history from `ownerOf` and live supply alone.

If a future FAME version adds one of those primitives, migrate the classifier using that authoritative source. Until then, the live-supply proxy is preferred because it continues to follow ordinary sequential mint growth without an operator-maintained cursor.

## Consumer Guidance

- Contracts must call `isTokenInBurnedPool` and `isTokenInMintPool`; they must not infer a static boundary independently.
- Web clients should read pool views at one pinned block when composing a single screen or transaction request.
- Indexers may record historical classifications for display, but must not present them as canonical current state.
- Tests must cover both sides of the tradeoff: the boundary advances after a fresh mint, and a burned high ID can be classified as Mint Pool while live supply is lower.

## Rejected Alternative

```text
mintPoolStartTokenId = 592 at migration
```

This accurately describes one observed private DN404 frontier, but there is no deployed callback or public source that can advance it. Once all recycled burn IDs are exhausted and DN404 creates a fresh ID, the static boundary misclassifies that new history forever unless an administrator manually updates it. V3 release operations advance metadata's `nextTokenId`; they do not observe DN404 NFT assignment and cannot safely advance a mint-history cursor.

The static frontier should not be reintroduced unless the FAME contract first exposes an authoritative update mechanism.
