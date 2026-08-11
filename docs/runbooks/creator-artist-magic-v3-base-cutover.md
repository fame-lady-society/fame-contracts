# CreatorArtistMagic V3 Base cutover runbook

Status: **completed and verified on Base on 2026-08-11**

The cutover mined successfully in blocks `49840113` through `49840131`. All 15 receipts have status `1`, `verifyDeployed()` passed against live Base state, and all three new contracts are source-verified on BaseScan. The immutable deployment evidence is recorded in `docs/handoffs/creator-artist-magic-v3-base-deployment.md`.

This is the operator runbook for the one-shot Base cutover from CreatorArtistMagic V2 to V3, a replacement `UniversalPoolArtMarketplace`, and a replacement `FameMarketplaceCheckout`.

The deployment does not move the legacy provider position. The old marketplace is paused by the first transaction, but its withdrawal path remains available. The provider later withdraws through `fls-www` and deposits into the replacement marketplace through the normal active-market flow.

## Canonical inputs

| Item | Value |
| --- | --- |
| Chain | Base (`8453`) |
| Operator | `0xD52E2A6bBcEba9673440e4D7843Db6713E9B6FD9` |
| Expected starting nonce | `230` |
| FAME | `0xf307e242BfE1EC1fF01a4Cef2fdaa81b10A52418` |
| CreatorArtistMagic V2 | `0xC8268c2aa571F3C88044C2959F73DdB8eB9e139F` |
| Legacy marketplace | `0x54e7E4F2d439Be599706f51068f7EB2ce2D2a27e` |
| Legacy checkout | `0x1905B4a633074243f3D9FDB59596fB7419adce2c` |
| Predicted V3 | `0x6754e4871775A781702f2Ab6e494754a562586ee` |
| Predicted replacement marketplace | `0x93222897902a5Fc2f20079d242c660117277930A` |
| Predicted replacement checkout | `0x50B9649Aa28D7d0B966B2A51092C5BcF37905a63` |
| V3 `nextTokenId` | `651` |
| V3 `artPoolNext` | `266` |
| Live DN404 supply snapshot | `564` |
| Migration-only DN404 next-ID snapshot | `592` |

The authoritative machine-readable inputs are in `script/manifests/creator-artist-magic-v3-base.json`. The public confirmations and predicted addresses are in `config/fame-public.env`.

Doppler `prd` supplies the secrets:

- `RPC_URL`
- `DEPLOYER_PRIVATE_KEY`
- `ETHERSCAN_API_KEY`

Never print any of these values. The execute and broadcast switches are command-scoped so sourcing `config/fame-public.env` remains read-only.

## Deployment sequence

The migration script performs these transactions in order:

1. Pause the legacy marketplace.
2. Deploy CreatorArtistMagic V3 with V2 as its child renderer.
3. Grant the three creator wallets exactly `CREATOR` (`2`).
4. Set V3 as FAME's top-level renderer.
5. Deploy the replacement marketplace bound to V3.
6. Grant the replacement marketplace exactly `BANISHER` (`4`).
7. Deploy and authorize the replacement checkout.
8. Unpause the replacement marketplace with zero inventory.
9. Revoke the three creator roles and legacy-market write role from V2.

Do not withdraw, transfer, or recreate the legacy provider position during this sequence.

## 1. Qualify the exact commit

Start from the repository root. Do not broadcast from an uncommitted or dirty checkout.

```sh
git status --short
git rev-parse HEAD
```

The web cutover must contain the same predicted address tuple in `src/features/fame/contract.ts`, and its generated ABI must match the committed `CreatorArtistMagic.sol`.

Run the local contract gates:

```sh
forge fmt --check
forge test --match-contract '^CreatorArtistMagicTest$'
forge test --match-test testPurchasePoolMaterializesNewlyReleasedArtwork
forge test --match-contract MigrateCreatorArtistMagicV3ManifestTest
```

Run every Base fork suite with the Doppler production RPC:

```sh
set -a
source config/fame-public.env
set +a
doppler run --config prd -- sh -c 'BASE_RPC="$RPC_URL" forge test --match-path "test/*ForkBase.t.sol"'
```

Expected: all relevant suites pass, including the seven V3 migration tests. Do not substitute a public RPC.

## 2. Run the final read-only live preflight

This command performs no writes because the execute and broadcast switches are absent. It fails closed on chain ID, code, renderer, operator nonce, cursors, DN404 snapshots, roles, old-market state, and the legacy provider snapshot.

```sh
set -a
source config/fame-public.env
set +a
doppler run --config prd -- sh -c 'forge script script/MigrateCreatorArtistMagicV3.s.sol:MigrateCreatorArtistMagicV3 --sig "run()" --rpc-url "$RPC_URL" -vv'
```

Expected final log:

```text
Inspection complete; no state changed.
```

If this fails, stop. Update pinned state and recompute every predicted address only after understanding the drift. Do not weaken an assertion to force the deployment through.

## 3. Record broadcast approval

Approval is a committed code review decision. Change these together:

1. Set `BROADCAST_APPROVED = true` in `script/MigrateCreatorArtistMagicV3.s.sol`.
2. Set `broadcastApproved` to `true` in `script/manifests/creator-artist-magic-v3-base.json`.
3. Change the manifest test to require `true`.
4. Replace `testBroadcastRemainsDisabledUntilManifestIsFinal` with a test requiring `migration.BROADCAST_APPROVED()` to be `true`.

Run the manifest and V3 fork tests again, then commit the approval change. Do not combine approval with unrelated code changes.

Immediately before broadcasting, repeat the read-only live preflight from step 2. The expected operator nonce must still be `230`.

## 4. Broadcast

The following is the only normal live-broadcast command. The two mode switches are explicit and are not stored in Doppler or the public env file.

```sh
set -a
source config/fame-public.env
set +a
CREATOR_ARTIST_MAGIC_V3_EXECUTE=true \
CREATOR_ARTIST_MAGIC_V3_BROADCAST=true \
doppler run --config prd -- sh -c 'forge script script/MigrateCreatorArtistMagicV3.s.sol:MigrateCreatorArtistMagicV3 --sig "run()" --rpc-url "$RPC_URL" --broadcast --slow --verify --etherscan-api-key "$ETHERSCAN_API_KEY" -vv'
```

The script independently derives the signer from `DEPLOYER_PRIVATE_KEY`, verifies that it is the expected operator, checks the three public confirmation addresses, and asserts the three deployed addresses before completing.

Do not start the legacy provider withdrawal while this command is running.

## 5. Resume an interrupted Foundry broadcast

If the broadcast process is interrupted, inspect the Foundry broadcast journal and Base receipts first. Resume the same journal; do not start a fresh deployment sequence.

```sh
set -a
source config/fame-public.env
set +a
CREATOR_ARTIST_MAGIC_V3_EXECUTE=true \
CREATOR_ARTIST_MAGIC_V3_BROADCAST=true \
doppler run --config prd -- sh -c 'forge script script/MigrateCreatorArtistMagicV3.s.sol:MigrateCreatorArtistMagicV3 --sig "run()" --rpc-url "$RPC_URL" --broadcast --slow --resume -vv'
```

The old marketplace pause is intentionally the first write. A partial run may leave it paused while later transactions are pending. Provider withdrawal remains available, but do not use it until post-deployment verification completes.

## 6. Record outputs and verify deployed state

Record every transaction hash and receipt status. The three deployed addresses must exactly match the predictions in this runbook.

Update the public outputs in `config/fame-public.env`:

```text
BASE_CREATOR_ARTIST_MAGIC_V3_ADDRESS=0x6754e4871775A781702f2Ab6e494754a562586ee
BASE_UNIVERSAL_MARKETPLACE_V3_ADDRESS=0x93222897902a5Fc2f20079d242c660117277930A
BASE_FAME_MARKETPLACE_CHECKOUT_V3_ADDRESS=0x50B9649Aa28D7d0B966B2A51092C5BcF37905a63
```

Update the three `contracts` fields and deployment status in `script/manifests/creator-artist-magic-v3-base.json`, and record the receipt hashes in the deployment handoff.

Run the read-only post-state verifier before the legacy provider withdraws:

```sh
set -a
source config/fame-public.env
set +a
doppler run --config prd -- sh -c 'forge script script/MigrateCreatorArtistMagicV3.s.sol:MigrateCreatorArtistMagicV3 --sig "verifyDeployed()" --rpc-url "$RPC_URL" -vv'
```

`verifyDeployed()` checks:

- V3 ownership, FAME binding, V2 child renderer, live cursor, Art Pool cursor, and roles.
- FAME renderer and role cutover.
- Replacement marketplace ownership, V3 binding, checkout authorization, unpaused state, and zero inventory.
- Replacement checkout bindings.
- Legacy marketplace paused state and unchanged provider position.
- Revoked V2 write roles.
- `tokenURI` parity for Society IDs `1` through `888`.

The verifier intentionally expects the original legacy provider snapshot. After the provider withdraws, that specific deployment-time assertion will no longer pass.

Verify the three new contracts on the Base explorer using the exact committed sources and constructor arguments before declaring the contract release complete.

## 7. Hand off to `fls-www`

Only after receipt-backed addresses and `verifyDeployed()` pass:

1. Confirm the active V3, marketplace, and checkout addresses in `src/features/fame/contract.ts` exactly match the receipts.
2. Confirm the generated wagmi ABI matches the deployed CreatorArtistMagic source.
3. Run the focused creator release, role, sponsored upload, active-address, and legacy recovery tests.
4. Deploy the web commit that contains the complete address tuple.

Do not expose legacy recovery UI unless `providerPosition(wallet).unitCount > 0` on the legacy marketplace. Never expose legacy deposit, purchase, or metadata-swap actions.

## 8. Legacy provider recovery

After the chain cutover and web deployment are verified, connect the provider wallet through `fls-www` and withdraw from the legacy marketplace. Then deposit into the replacement marketplace through the normal active-market staking flow.

Do not perform this recovery from the deployment signer unless that signer is also the recorded provider wallet.

## Stop conditions

Stop before broadcast when any of these are true:

- The checkout is dirty or the approval change is not committed.
- The live preflight fails.
- The operator nonce is not `230`.
- Any predicted address differs.
- The Base fork migration suite is not green.
- The signer is not the expected operator.
- The legacy provider snapshot differs from the manifest.

After a partial broadcast, stop starting new sequences. Reconcile the Foundry journal and mined receipts, then use `--resume` only.
