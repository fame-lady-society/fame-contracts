---
chain: base-sepolia
status: predeployment
contract: UniversalPoolArtMarketplace
---

# Base Sepolia Universal Pool Art Marketplace

The marketplace deployment is intentionally pending. The successor contract and
its release tooling are implemented. Only the fee-recipient preparation
transactions documented below have been authorized and broadcast.

## Intended configuration

| Field | Value |
|---|---|
| Chain | Base Sepolia (`84532`) |
| FAME / TEST | `0x2cF0408Ee86b337216dD0073ab257F84497067cA` |
| Society NFT mirror | `0x2907936013BDF568F98A98893AC1C746256A9cC5` |
| CreatorMagic | `0xa16C005203cD46cC1929cc8e494cF7945887951B` |
| Owner | `0xD52E2A6bBcEba9673440e4D7843Db6713E9B6FD9` |
| Fee recipient | `0x0Bd54EcB903392B323bC2b3dA61023325f730241` |
| Premium | `1,000 TEST` |
| Seed inventory | 2 Society NFT shells |
| Initial state | Paused |
| Marketplace address | Pending |
| Simulated nonce | 31 |
| Simulated address | `0x821ab043a94688aC22C5a1b0113fc33ed4Fb6843` |

The marketplace receives only CreatorMagic `BANISHER`. It must not receive
CreatorMagic `CREATOR`, CreatorMagic `ART_POOL_MANAGER`, or FAME `SKIP_MANAGER`.
The fee recipient must remain `skipNFT=true`; the marketplace must remain
`skipNFT=false`.

## Fee recipient preparation

Prepared on Base Sepolia on 2026-07-18:

- Funded with exactly `0.0001 ETH`:
  `0xa6ded7840580cc5ba84869946c442f4db07a1e2eaf8ffc601fa0fb062fff31aa`
- Called `Fame.setSkipNFT(true)`:
  `0xf4484234195720d0b2691ed5790319e90299c39f843412002fdc25f3dfcbb77c`
- Canonical readback: `Fame.getSkipNFT(feeRecipient) == true`

The private key is stored only as the masked Doppler `dev` secret
`BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_FEE_RECIPIENT_PRIVATE_KEY`.

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
| Current-head fork | Passed again after fee-recipient setup on 2026-07-18 |
| Deployment dry run | Passed at nonce 31 |
| Mined address and transaction hashes | Pending |
| Explorer source and ABI | Pending |
| Strict deployed-address fork | Pending |
| Activation transaction | Pending |
| Post-activation fork | Pending |
| Smoke script rehearsal | Passed locally and on current-head fork |
| Bounded live smoke | Pending |

No `broadcast/` logs are committed. Mined public facts belong in this document
and `config/fame-public.env`; signer material and RPC credentials remain in
Doppler.

The non-broadcast deployment rehearsal at nonce 31 completed successfully with
four simulated transactions: deploy, grant BANISHER, seed shell one, and seed
shell two. Its predicted address is
`0x821ab043a94688aC22C5a1b0113fc33ed4Fb6843`. This is not a deployed-address
claim and must be recomputed if the deployer nonce changes.

## Bounded smoke

The smoke tooling freezes one plan hash containing:

- buyer and exact starting nonce;
- direct, Burn, and Mint recipients;
- three unique marketplace shell IDs;
- Burn and Mint source IDs;
- selected and displaced artwork hashes;
- current unit, premium, exact three-purchase spend, inventory, fee balance,
  buyer mirror balance, and buyer post-purchase minimum.

The script sets an exact allowance and executes Burn, Mint, then direct held.
The allowance is three units plus three premiums, except when the buyer is the
fee recipient, where premium self-transfers are skipped and the exact allowance
is three units.
That order is required because any unit deposited into the non-skip marketplace
can remint a burned ID or advance supply into a Mint source. The result validator
does not assume that DN404 replenishes inventory with either selected source ID.

The smoke requires both an explicit confirmation value and a secret buyer key in
Doppler. No live smoke plan is configured until the marketplace is deployed,
verified, and activated.

The complete smoke script plus independent result validator passed again
against an ephemeral successor on Base Sepolia fork block `44,301,168`
(`0x533310aae1590e270bc202168830331982bdf2912bbf1b8c033aa429f21f4642`).

## WWW handoff

The future frontend integration should use the verified deployed address and ABI
for `UniversalPoolArtMarketplace`. The address is currently pending.

Buyer discovery and routing:

1. If `mirror.ownerAt(targetId) == marketplace`, buy that held shell with
   `purchaseHeld`.
2. Otherwise, if exactly one of `isTokenInBurnedPool(targetId)` and
   `isTokenInMintPool(targetId)` is true, select any canonically
   marketplace-owned shell and call `purchasePool(shellId, targetId, ...)`.
   Neither predicate means the artwork is unavailable; both predicates mean the
   source is ambiguous and the contract rejects it.
3. If the intended recipient already owns `targetId`, short-circuit to the owned
   result instead of purchasing.
4. Art Pool IDs are excluded and must not be presented as marketplace inventory.

Transaction inputs:

- `expectedArtworkHash = keccak256(bytes(creatorMagic.tokenURI(targetId)))`;
- `maxPremium` is the premium the buyer accepted;
- `minBuyerMirrorBalanceAfter` is `0` to opt out or a caller-selected DN404
  postcondition;
- payment is only `unit + premium` in the underlying FAME/TEST token;
- external swap infrastructure may acquire the underlying token before this
  transaction but is not part of the marketplace contract.

The frontend should re-read source eligibility, shell custody, artwork hash,
premium, allowance, and recipient immediately before simulation. A successful
`ArtworkPurchased` event reports buyer, recipient, delivered shell, fulfillment
path, selected source, artwork hash, unit, premium, and before/after inventory.
The path values are `0 = Held`, `1 = MintPool`, and `2 = BurnPool`; held
purchases report `sourceId = 0`.

Metadata remains a deployment-specific presentation concern. Base Sepolia TEST
uses nested on-chain data URIs; production FAME uses URL metadata. Settlement
depends only on the exact URI hash and does not parse either format.
