# Society Bots handoff: CreatorArtistMagic V3 address cutover

Status: **ready for `society-bots` implementation**

The CreatorArtistMagic V3 stack is live and independently verified on Base. Society Bots must replace its active marketplace, checkout, and CreatorArtistMagic authorities as one atomic deployment. The legacy receipt fixture remains historical evidence and must not be rewritten.

## Receipt-confirmed active addresses

| Authority | New active address |
| --- | --- |
| CreatorArtistMagic V3 | `0x6754e4871775A781702f2Ab6e494754a562586ee` |
| UniversalPoolArtMarketplace V3 | `0x93222897902a5Fc2f20079d242c660117277930A` |
| FameMarketplaceCheckout V3 | `0x50B9649Aa28D7d0B966B2A51092C5BcF37905a63` |
| FAME | `0xf307e242BfE1EC1fF01a4Cef2fdaa81b10A52418` |
| FAME mirror | `0xBB5ED04dD7B207592429eb8d599d103CCad646c4` |

The deployment and explorer evidence are in `docs/handoffs/creator-artist-magic-v3-base-deployment.md`.

## Exact `society-bots` changes

1. In `src/constants.ts`:
   - Change `BASE_UNIVERSAL_MARKETPLACE_ADDRESS` from `0x54e7E4F2d439Be599706f51068f7EB2ce2D2a27e` to `0x93222897902a5Fc2f20079d242c660117277930A`.
   - Change `BASE_FAME_CHECKOUT_ADDRESS` from `0x1905B4a633074243f3D9FDB59596fB7419adce2c` to `0x50B9649Aa28D7d0B966B2A51092C5BcF37905a63`.
2. In `src/fame-swap-pool-state/landing-snapshot-runtime.ts`:
   - Change `MARKETPLACE` to `0x93222897902a5Fc2f20079d242c660117277930A`.
   - Change `CREATOR_MAGIC` to `0x6754e4871775A781702f2Ab6e494754a562586ee`.
3. Update `src/fame-swap-pool-state/landing-snapshot-runtime.test.ts` so the authority assertion expects CreatorArtistMagic V3.
4. Update address-dependent purchase, stake, indexer, DynamoDB-key, and landing-snapshot tests through the shared constants. Do not add a compatibility fallback to the retired active addresses.

## Preserve the historical receipt fixture

Do **not** replace the old marketplace or checkout addresses inside `src/fame-metadata-refresh/_fixtures/base-failing-marketplace-receipt.json`. That file represents a real transaction emitted by the old stack. Its embedded log addresses are part of the fixture's historical identity.

If tests using that fixture need to continue exercising the active decoder after the constants change, keep the raw fixture immutable and explicitly project or remap the fixture logs in test setup. Do not make production code accept the legacy marketplace or checkout as active authorities.

## Runtime behavior after the cutover

- Purchase and stake log scans must target only the new marketplace.
- Checkout settlement recognition must target only the new checkout.
- Landing snapshot reads must target the new marketplace and continue failing closed unless its immutable `creatorMagic()` equals V3 and its FAME/mirror bindings remain canonical.
- Metadata-update scans remain on the unchanged FAME mirror. `releaseArtwork` routes ERC-4906 updates through FAME to that mirror, so no metadata-event address change is needed.
- Existing purchase and stake checkpoints should be retained. The indexer queries the newly active address from its stored block cursor, so it can cover any new-market events since that cursor without replaying retired-market activity.
- The new marketplace began unpaused with zero inventory. An available marketplace snapshot with zero inventory/provider units is valid deployment state, not an address failure.

## Legacy addresses

| Retired authority | Address | Society Bots behavior |
| --- | --- | --- |
| CreatorArtistMagic V2 | `0xC8268c2aa571F3C88044C2959F73DdB8eB9e139F` | Renderer-chain child only; never active marketplace authority |
| Legacy marketplace | `0x54e7E4F2d439Be599706f51068f7EB2ce2D2a27e` | Paused and withdrawal-only; do not scan for new purchases/stakes |
| Legacy checkout | `0x1905B4a633074243f3D9FDB59596fB7419adce2c` | Retired; historical fixtures only |

Legacy provider recovery is owned by `fls-www`; Society Bots does not need a legacy withdrawal path.

## Acceptance checks

- The complete active address tuple changes together in one deployment.
- The landing runtime accepts `marketplace.creatorMagic() == 0x6754e4871775A781702f2Ab6e494754a562586ee` and rejects V2.
- Purchase projection recognizes the new marketplace and new checkout, and rejects the retired addresses outside immutable historical-fixture tests.
- Stake projection and stake notification keys use the new marketplace.
- Metadata refresh still reads authoritative metadata through the unchanged FAME mirror and preserves exact `metadata.image` URLs.
- A same-block landing snapshot succeeds against the new marketplace when its state is internally consistent, including the expected initial zero-inventory case.
- Focused metadata-refresh and landing-snapshot suites pass before deploying Society Bots.

No contract broadcast, provider migration, or `fls-www` change is part of this handoff.
