---
chain: base-sepolia
status: deployed-paused
contract: UniversalPoolArtMarketplace
---

# Base Sepolia Universal Pool Art Marketplace

The marketplace was deployed to Base Sepolia on 2026-07-18 and remains paused.
Deployment, narrow CreatorMagic authority, and three-shell seeding are complete.
Activation and live smoke have not been authorized or broadcast.

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
| Seed inventory | 3 Society NFT shells |
| Initial state | Paused |
| Marketplace address | `0x821ab043a94688aC22C5a1b0113fc33ed4Fb6843` |
| Deployment nonce | 31 |
| Deployment block | `44,329,992` |

The marketplace receives only CreatorMagic `BANISHER`. It must not receive
CreatorMagic `CREATOR`, CreatorMagic `ART_POOL_MANAGER`, or FAME `SKIP_MANAGER`.
The fee recipient must remain `skipNFT=true`; the marketplace must remain
`skipNFT=false`.

## Fee recipient preparation

Prepared on Base Sepolia on 2026-07-18:

- Funded with exactly `0.0001 ETH`:
  `0xa6ded7840580cc5ba84869946c442f4db07a1e2eaf8ffc601fa0fb062fff31aa`
- Called `Fame.setSkipNFT(true)` (optional for fee recipients; no longer required):
  `0xf4484234195720d0b2691ed5790319e90299c39f843412002fdc25f3dfcbb77c`
- Fee recipient skipNFT is **not** enforced by marketplace deploy/validate

The private key is stored only as the masked Doppler `dev` secret
`BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_FEE_RECIPIENT_PRIVATE_KEY`.

## Paused deployment

All five deployment-prefix transactions mined successfully in Base Sepolia
block `44,329,992` (`0x5cadeb5022de369a1daa71968a85749b1ed88d08096bc19d177cdb830148c352`):

- Deploy paused marketplace:
  `0xdd850984dea7107ba98e6ec77f66ff94c2bea9146c4759cfc3e15719ef7f2a97`
- Grant CreatorMagic `BANISHER`:
  `0x3f0ab967bee0fecb59c621e33d2f9853e03e580f88546d8b3b3d1903ff616e90`
- Seed shell 4:
  `0x33073de4cdd78c6e5fee2a0b886ee9d0ce9ef85e536ef0f13172b4b1fbd972d4`
- Seed shell 5:
  `0x8766a98d7e4b5b496a335422dca54ef0788a5cf65c2318d2a80ced9359ccab6f`
- Seed shell 6:
  `0x0e5ce6e08d429f47e55c523a8b608eaecd0c7ac61618e92bcd48377a6693dad2`

Independent receipt and contract readback confirmed:

- all five receipts have status `1`;
- owner, dependencies, premium, and fee recipient match this document;
- `paused == true`;
- marketplace inventory is exactly three Society NFT shells;
- the read-only validator and strict paused deployed-address fork pass; and
- deployed runtime bytecode has the same length and every non-immutable byte as
  the local `universal_marketplace` artifact.

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
| Current-head fork | Passed at block `44,330,085` after deployment |
| Deployment dry run | Passed at nonce 31 |
| Mined address and transaction hashes | Passed; recorded above |
| Read-only deployed-state validator | Passed on 2026-07-18 |
| Runtime bytecode attestation | Passed outside compiler-declared immutable slots |
| Explorer source and ABI | Pending; initial broadcast submission mismatched |
| Strict deployed-address fork | Passed on 2026-07-18 with no skips |
| Activation transaction | Pending |
| Post-activation fork | Pending |
| Smoke script rehearsal | Passed locally and on current-head fork |
| Bounded live smoke | Pending |

No `broadcast/` logs are committed. Mined public facts belong in this document
and `config/fame-public.env`; signer material and RPC credentials remain in
Doppler.

The non-broadcast deployment rehearsal at nonce 31 predicted the address that
subsequently mined. The public address is pinned in `config/fame-public.env`;
generated Foundry `broadcast/` records remain uncommitted.

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

The implementation handoff is
`docs/handoffs/base-sepolia-universal-pool-art-marketplace-to-fls-www.md`.

The future frontend integration should use
`0x821ab043a94688aC22C5a1b0113fc33ed4Fb6843` and the explorer-verified ABI for
`UniversalPoolArtMarketplace`. WWW work remains deferred until explorer
verification and marketplace activation are complete.

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
