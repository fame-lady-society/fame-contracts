---
title: Base Sepolia Gallery Test Stack
date: 2026-07-15
module: closed-loop-gallery-swap
---

# Base Sepolia Gallery Test Stack

This stack validates the closed-loop gallery against the existing Base Sepolia `Example / TEST` FAME deployment. It uses a deterministic on-chain renderer so every token ID has distinct JSON metadata and SVG art without relying on a hosted endpoint.

## Public Configuration

Confirmed by direct Base Sepolia reads on 2026-07-15:

- FAME: `0x2cf0408ee86b337216dd0073ab257f84497067ca`
- Society NFT mirror: `0x2907936013BDF568F98A98893AC1C746256A9cC5`
- FAME owner/admin and test deployer: `0xD52E2A6bBcEba9673440e4D7843Db6713E9B6FD9`
- Identity: `Example / TEST`
- NFT unit: `1,000,000 TEST`
- Expected prior renderer: zero address, pinned in public config and rechecked by the deploy script
- Transfer posture: a zero-value transfer from an arbitrary account succeeded, confirming public transfers are enabled
- Deployment nonce: `17`, retained as the fail-closed retry guard
- Test renderer: `0x980f1c21b29d4e16ac3Fc49Fe9Aaf64b97C5A9De`
- CreatorMagic: `0xa16C005203cD46cC1929cc8e494cF7945887951B`
- Closed-loop gallery: `0x7f9bA27F40686E548f613e679835158070901c47`
- Smoke recipient: `0x7307E109C747AaD76CBc0A09612b8350410D35ba`

The smoke recipient private key is stored as the masked Doppler `dev` secret `BASE_SEPOLIA_SMOKE_RECIPIENT_PRIVATE_KEY`. Generated `broadcast/` output remains uncommitted; curated public evidence is recorded below.

## Stack

1. `BaseSepoliaTestRenderer` returns nested Base64 JSON and SVG data URIs. Token names, visible labels, colors, and the Token ID attribute vary by token ID.
2. `CreatorArtistMagic` uses that renderer as its child renderer and starts with `nextTokenId = 500`.
3. FAME delegates token metadata to CreatorMagic.
4. Deployment seeds `ClosedLoopGallerySwap` with two Society NFTs before FAME is rewired to CreatorMagic.
5. `ClosedLoopGallerySwap` rotates metadata through CreatorMagic and sells each NFT for one FAME unit plus a positive premium.
6. The gallery receives CreatorMagic `BANISHER | ART_POOL_MANAGER`, never broad `CREATOR` authority.

For the mint-pool path, rotation selects `totalNFTSupply + 1`. Filling the listing transfers one FAME unit plus premium into the gallery, which mints that exact pool token into gallery custody before the selected NFT leaves. The premium remains accrued in FAME, and gallery NFT inventory does not decrease.

## Verification Before Deployment

Load public configuration first and map Doppler's secret RPC only inside the child process:

```sh
set -a
source config/fame-public.env
set +a
doppler run --config dev -- sh -c 'BASE_SEPOLIA_RPC="$RPC_URL" forge test --match-path test/ClosedLoopGallerySwapForkBaseSepolia.t.sol'
```

The predeployment fork rehearsal currently proves the live FAME identity and mirror, ephemeral stack wiring, unique metadata rotation, a `1.01M TEST` fill, exact premium accrual, recipient ownership, and nondecreasing inventory. It uses the same freshness, listing, balance, role, and payer predicates as the live smoke. The separate deployed-address fork gate skips during ordinary local runs until the three stack addresses are configured. The strict post-deployment command fails rather than skipping when RPC or addresses are absent:

```sh
doppler run --config dev -- sh -c 'BASE_SEPOLIA_RPC="$RPC_URL" BASE_SEPOLIA_REQUIRE_DEPLOYED_STACK=true forge test --match-path test/ClosedLoopGallerySwapForkBaseSepolia.t.sol'
```

Run the deployment as a simulation first:

```sh
doppler run --config dev -- sh -c 'BASE_SEPOLIA_RPC="$RPC_URL" cast nonce "$BASE_SEPOLIA_FAME_EXPECTED_ADMIN" --rpc-url base_sepolia'
# Set the returned public value as BASE_SEPOLIA_EXPECTED_DEPLOYER_NONCE.
doppler run --config dev -- sh -c 'BASE_SEPOLIA_RPC="$RPC_URL" forge script script/DeployBaseSepoliaGalleryTestStack.s.sol:DeployBaseSepoliaGalleryTestStack --rpc-url base_sepolia'
```

Do not add `--broadcast` until the deployment is explicitly authorized. Immediately before an authorized run, read and record FAME's current renderer and deployer nonce again; historical values are not permanent assumptions. The script also requires enough TEST to seed two NFTs before broadcasting. Any submitted transaction changes the pinned nonce, so a partial deployment cannot be blindly retried.

## Deployment And Validation

After an authorized deployment, record the three public addresses in `config/fame-public.env`, then run the read-only validator:

```sh
doppler run --config dev -- sh -c 'BASE_SEPOLIA_RPC="$RPC_URL" forge script script/ValidateBaseSepoliaGalleryTestStack.s.sol:ValidateBaseSepoliaGalleryTestStack --rpc-url base_sepolia'
```

The validator checks code presence, FAME name/symbol/unit/mirror, child-renderer wiring, `nextTokenId`, active FAME renderer, gallery owner/operator/fee recipient, at least two gallery NFTs, non-skip NFT custody, narrow CreatorMagic roles, and distinct renderer output.

If post-deploy validation fails after FAME was rewired, the FAME admin can restore the renderer captured immediately before deployment with `setRenderer(previousRenderer)`. Do not guess the rollback address from this document.

### Live Deployment Evidence

Deployed to Base Sepolia on 2026-07-17. Every receipt below has status `1`:

- Grant FAME metadata role: `0xed58a3db5ed44231756494fae309731339d26b62279268d911a7a5b06ba41e21`
- Deploy test renderer: `0xcade804cb283d0f492b748337991169cb5be0ee4982274a8fd6a04f37dd7af52`
- Deploy CreatorMagic: `0xcafded983ffcd30663e2236b8f7694d3efe5712ca19b778b2d9558f709561dae`
- Deploy gallery: `0xbb306d7ce86152aea4ca2ebbe5d90a024bd0960a763f10d7318fa66919d12be2`
- Grant narrow CreatorMagic roles: `0xd8eb6503b236785b5f6abb4f9f169b29eb333064fd03104628fba7b4dab1adf2`
- Seed two gallery NFTs: `0x97dff4dcaa16993e8d9ba34e3fea0f4ffd65422987fefa9b4b42ca2e1334b5ef`
- Set FAME renderer: `0x4e831bf7fb6317e31583bad2330f07703e4aee74a699f52a78c8a5c2d965ee3c`

The read-only stack validator passed against the mined contracts. The strict deployed-address fork passed with both predeployment and deployed-stack tests running without skips.

Basescan source verification completed on 2026-07-17 using the exact Solidity `0.8.28`, optimizer, and constructor settings from the deployment:

- [BaseSepoliaTestRenderer verified source](https://sepolia.basescan.org/address/0x980f1c21b29d4e16ac3fc49fe9aaf64b97c5a9de#code)
- [CreatorArtistMagic verified source](https://sepolia.basescan.org/address/0xa16c005203cd46cc1929cc8e494cf7945887951b#code)
- [ClosedLoopGallerySwap verified source](https://sepolia.basescan.org/address/0x7f9ba27f40686e548f613e679835158070901c47#code)

## Bounded Smoke

The smoke runner defaults to a `1,000 TEST` premium, so the total purchase is `1,001,000 TEST`. It requires the two NFTs seeded during deployment, rotates the next mint-pool metadata leg, lists, approves, fills to the configured recipient, and emits the selected IDs and inventory counts.

`BASE_SEPOLIA_SMOKE_RECIPIENT` is required and must be a separate EOA from the deployer. The payer must own zero Society NFTs so DN404 mints a replacement instead of transferring an existing payer NFT. Preflight also rejects active listings, previously rotated candidates, contract recipients, zero/oversized premiums, insufficient TEST, and role drift before broadcast begins. The strict fork proves the exact selected pool ID will be replenished under current DN404 burned-pool state, and the smoke refuses to report completion unless that exact ID enters gallery custody.

If a broadcast stops after rotation or listing, or the exact replacement-ID postcondition fails after fill, do not blindly rerun it. Inspect the metadata, listing, burned-pool effect, and ownership state and explicitly complete or unwind that partial smoke first.

Simulation still requires the explicit smoke flag but does not submit transactions without `--broadcast`:

```sh
doppler run --config dev -- sh -c 'BASE_SEPOLIA_RPC="$RPC_URL" BASE_SEPOLIA_SMOKE_CONFIRMED=true BASE_SEPOLIA_SMOKE_RECIPIENT=<separate-eoa> forge script script/SmokeBaseSepoliaGalleryTestStack.s.sol:SmokeBaseSepoliaGalleryTestStack --rpc-url base_sepolia'
```

An authorized live smoke adds `--broadcast`. After the receipts are mined, pass the emitted IDs into the mandatory read-only result validator:

```sh
doppler run --config dev -- sh -c 'BASE_SEPOLIA_RPC="$RPC_URL" BASE_SEPOLIA_SMOKE_RECIPIENT=<same-separate-eoa> BASE_SEPOLIA_SMOKE_TOKEN_ID=<sold-id> BASE_SEPOLIA_SMOKE_POOL_TOKEN_ID=<pool-id> forge script script/ValidateBaseSepoliaGallerySmokeResult.s.sol:ValidateBaseSepoliaGallerySmokeResult --rpc-url base_sepolia'
```

This checks final-chain recipient ownership, exact replacement-token custody, the bidirectional metadata swap, cleared listing state, and minimum gallery inventory. Independently record `accruedProtocolFees` as part of the smoke evidence. A successful broadcast process without the mined receipts and this result validation is not sufficient evidence.

### Live Smoke Evidence

The authorized Base Sepolia smoke completed on 2026-07-17:

- Rotated gallery token `1` with mint-pool token `3`: `0x67a87589173faf645c718cdb2775d0247c5a75d1352f48f51b4c8294066e21c0`
- Listed token `1`: `0xf7ce0b238a6fe86a376a450e1c528d7fd69e9ed36c9cc6ce209a082e0900c363`
- Approved `1,001,000 TEST`: `0x6604025f2f9a2c6e7ec19b7048f7e1aa0ea51d67f5ce0809ac98954e382498e5`
- Filled to the smoke recipient: `0x25abc0744d1d15d36a1c71c48734eee9c4445734d6beec244b42250e75403b3e`

All four receipts have status `1`. Independent final-state validation proved token `1` belongs to the smoke recipient, token `3` belongs to the gallery, their deterministic metadata was swapped bidirectionally through the active FAME renderer, the listing is inactive, gallery inventory remains `2`, and `accruedProtocolFees` is `1,000 TEST`.

## Evidence Boundary

- Local renderer, deployment-validator, and multi-run smoke rehearsals pass.
- The Base Sepolia predeployment and deployed-address fork gates pass without skips.
- The Base Sepolia renderer, CreatorMagic, and gallery are deployed and pass mined-state validation.
- One live smoke purchase completed and passed independent final-state validation.
