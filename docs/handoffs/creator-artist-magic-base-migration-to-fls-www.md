# CreatorArtistMagic Base migration handoff to `fls-www`

Status: **broadcast complete; ready for `fls-www` cutover**

The migration keeps the repaired legacy `CreatorArtistMagic` contract in the
renderer chain:

```text
FAME
  -> new CreatorArtistMagic
    -> legacy CreatorArtistMagic
      -> legacy child renderer
```

This preserves every existing `tokenURI` while moving creator writes to the new
contract.

## Chain inputs

| Item | Value |
| --- | --- |
| Chain | Base (`8453`) |
| FAME | `0xf307e242BfE1EC1fF01a4Cef2fdaa81b10A52418` |
| Current CreatorArtistMagic | `0xC8268c2aa571F3C88044C2959F73DdB8eB9e139F` |
| Legacy CreatorArtistMagic | `0x8091D00A25ebE87A2A1Ef19e1d33689FCAdC3fA5` |
| Legacy child renderer | `0xA50C9a918C110CA159fb187F4a55896A4d063878` |
| Deployment transaction | `0xaf74bfd34e11ae47cc4e24ddc4cb76945e9c5d9bbcc79f03c4131ffb4eaa5252` |
| Renderer cutover transaction | `0xfb828048907de65435d1671ca21a24382a09b48781d043f81af122b3d1a52cce` |
| Expected starting token ID | `650` |
| Expected art-pool cursor | `266` |

The authoritative prepared inputs are in
`script/manifests/creator-artist-magic-migration-base.json`. Do not copy an
address from a fork or dry-run log into `fls-www`; those deployments are local
simulation artifacts.

The owner confirmed there have been no role changes since the complete scan
through block `48813216`, so no repeat event scan is required. The script still
fails closed if any recorded role mask or the signer/new owner differs.

## Evidence required from the chain migration

Before changing `fls-www`, provide:

1. The repair receipts and readbacks proving IDs `645` through `649` have the
   exact approved metadata and nonzero metadata IDs.
2. The new CreatorArtistMagic address, deployment transaction, cutover
   transaction, role transactions, and final block.
3. Readback showing `FAME.renderer()` equals the new address.
4. Readback showing the new contract uses the legacy CreatorArtistMagic as its
   child renderer, starts at token ID `650`, and has art-pool cursor `266`.
5. Readback showing the three creator wallets each have exactly role mask `2`
   on the new contract.
6. Readback showing all five recorded role principals have mask `0` on the
   legacy contract.
7. `tokenURI` parity for IDs `1` through `888`.

## `fls-www` changes

1. Update the Base return value in
   `src/features/fame/contract.ts::creatorArtistMagicAddress` to the verified
   new address.
2. From `fls-www`, run `npx wagmi generate` with the required explorer keys.
   Review the generated `src/wagmi/index.ts`; it must reflect the current
   `CreatorArtistMagic.sol` ABI.
3. Confirm every CreatorArtistMagic consumer resolves through
   `creatorArtistMagicAddress(base.id)`, especially:
   - `src/service/fame.ts`
   - `src/app/fame/token/image/[tokenId]/route.ts`
   - creator-role and creator-grid hooks
   - creator metadata API routes
   - swap/write hooks
4. Run `yarn lint` and `yarn build`.
5. Smoke test:
   - `/fame` renders existing tokens and the five repaired metadata entries.
   - token image routes resolve existing and burned token metadata through the
     renderer directly where appropriate.
   - `/fame/creator/<wallet>` recognizes each migrated creator.
   - creator metadata reads and a wallet-prepared write target the new address.
   - no production source still uses the legacy CreatorArtistMagic address,
     except historical documentation.

Deploy the chain migration first. Update and deploy `fls-www` only after the
chain readbacks above pass; otherwise the UI can point writes at a contract that
is not yet authoritative.

## Rollback

Before the renderer cutover, rollback is simply to stop.

After the renderer cutover, do not switch FAME back blindly: the migration
revokes the legacy contract's role principals. To restore the old write path:

1. Re-grant the exact legacy role masks from the manifest using the legacy
   owner.
2. Call `FAME.setRenderer(legacyCreatorArtistMagic)`.
3. Verify FAME moved its renderer role back to the legacy contract.
4. If the new contract is being abandoned, revoke its creator roles after the
   old path has been restored.
5. Revert the `fls-www` address only after the on-chain rollback is verified.

The legacy owner retains owner-level authority, including the ability to change
the legacy child renderer. Each migrated CREATOR wallet can likewise change the
new contract's global child renderer; that is existing CREATOR-role behavior,
not metadata-only authority. Renouncing ownership, transferring it, or splitting
global renderer administration into a separate role is a separate security
decision and is not part of this migration.

Because the live migration is a sequence of transactions, broadcast with
Foundry's sequential `--slow` mode. If a transaction fails partway through,
reconcile mined receipts and current role state before resuming; do not rerun
the entire sequence on vibes.

The owner reviewed and approved the migration. The compile-time
`BROADCAST_APPROVED` gate and manifest `broadcastApproved` field are enabled.
This approval does not itself broadcast or change chain state.
