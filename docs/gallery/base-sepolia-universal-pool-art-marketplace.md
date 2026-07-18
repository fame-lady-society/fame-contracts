---
chain: base-sepolia
status: predeployment
contract: UniversalPoolArtMarketplace
---

# Base Sepolia Universal Pool Art Marketplace

This deployment is intentionally pending. The successor contract and its release
tooling are implemented, but no live transaction has been authorized or
broadcast.

## Intended configuration

| Field | Value |
|---|---|
| Chain | Base Sepolia (`84532`) |
| FAME / TEST | `0x2cF0408Ee86b337216dD0073ab257F84497067cA` |
| Society NFT mirror | `0x2907936013BDF568F98A98893AC1C746256A9cC5` |
| CreatorMagic | `0xa16C005203cD46cC1929cc8e494cF7945887951B` |
| Owner | `0xD52E2A6bBcEba9673440e4D7843Db6713E9B6FD9` |
| Fee recipient | `0xD52E2A6bBcEba9673440e4D7843Db6713E9B6FD9` |
| Premium | `1,000 TEST` |
| Seed inventory | 2 Society NFT shells |
| Initial state | Paused |
| Marketplace address | Pending |
| Simulated nonce | 30 |
| Simulated address | `0x0177e4CE933a672483758FB6a40BE83B969A8066` |

The marketplace receives only CreatorMagic `BANISHER`. It must not receive
CreatorMagic `CREATOR`, CreatorMagic `ART_POOL_MANAGER`, or FAME `SKIP_MANAGER`.
The fee recipient must remain `skipNFT=true`; the marketplace must remain
`skipNFT=false`.

## Release sequence

1. Refresh the expected deployer nonce in `config/fame-public.env`.
2. Run the deployment script without `--broadcast` and inspect every simulated
   transaction.
3. Obtain explicit authorization before adding `--broadcast`.
4. Record the mined address and deployment, BANISHER, and shell-seed transaction
   hashes here and in `config/fame-public.env`.
5. Run the read-only validator and strict deployed-address fork.
6. Confirm explorer source and ABI verification using the
   `universal_marketplace` Foundry profile.
7. Simulate activation. Broadcast the separate owner `unpause` only after
   explicit authorization.
8. Run the post-activation fork and bounded smoke.

The deploy script is prefix-aware. It predicts the nonce-derived address,
validates an existing paused deployment, and simulates only missing BANISHER and
seed-inventory steps. Any owner, dependency, premium, fee recipient, skip state,
or authority mismatch stops the run.

## Verification evidence

| Evidence | Status |
|---|---|
| Unit tests | Passed |
| 10,000-case fuzz campaign | Passed |
| 512 x 128 invariant campaign | Passed |
| Pinned Base Sepolia fork | Passed at block `44,267,553` |
| Current-head fork | Passed during implementation |
| Deployment dry run | Passed at nonce 30 |
| Mined address and transaction hashes | Pending |
| Explorer source and ABI | Pending |
| Strict deployed-address fork | Pending |
| Activation transaction | Pending |
| Post-activation fork | Pending |
| Bounded smoke | Pending |

No `broadcast/` logs are committed. Mined public facts belong in this document
and `config/fame-public.env`; signer material and RPC credentials remain in
Doppler.

The non-broadcast deployment rehearsal at nonce 30 completed successfully with
four simulated transactions: deploy, grant BANISHER, seed shell one, and seed
shell two. The simulated address is not a deployed-address claim and must be
recomputed if the deployer nonce changes.
