# Base Universal Pool Art Marketplace production implementation handoff

Status: **ready for fork implementation and full browser rehearsal; no Base
mainnet deployment authorized**

The Base Sepolia marketplace and `fls-www` buyer experience have exercised the
continuous held/Mint/Burn exchange successfully. Production should reuse the
contract and proven frontend model, but the release process is intentionally
more conservative because each FAME unit and Society NFT represents meaningful
value.

The product owner reports that the Base Sepolia WWW completed many purchases.
That is useful product evidence, not a substitute for the production fork gates
below.

The required next milestone is not a mainnet deployment. It is a pinned Base
fork that supports:

- the exact production marketplace deployment and setup sequence;
- the production `fls-www` route reading and writing against that fork;
- a dedicated fork-only browser wallet signing real UI transactions; and
- repeatable held, Mint Pool, Burn Pool, swap-then-purchase, and failure-path
  validation.

Only after that environment is working and its evidence has been reviewed
should a separate conversation define and authorize a real Base deployment.

## Locked production inputs

These values were specified by the product owner or read from Base at block
`48,852,841`
(`0xb79c52084d8888f9b5bde8b66c61769abbc9b420b56ce4cf549d5d873c30eb71`)
on 2026-07-19.

| Item | Value |
| --- | --- |
| Chain | Base (`8453`) |
| FAME name / symbol | `Society` / `FAME` |
| FAME | `0xf307e242BfE1EC1fF01a4Cef2fdaa81b10A52418` |
| Society NFT mirror | `0xBB5ED04dD7B207592429eb8d599d103CCad646c4` |
| CreatorArtistMagic | `0xC8268c2aa571F3C88044C2959F73DdB8eB9e139F` |
| CreatorArtistMagic child renderer | `0x8091D00A25ebE87A2A1Ef19e1d33689FCAdC3fA5` |
| FAME unit | `1,000,000 FAME` |
| FAME unit raw value | `1000000000000000000000000` |
| Starting premium | `30,000 FAME` |
| Starting premium raw value | `30000000000000000000000` |
| Premium percentage of one unit | `3%` |
| Fee recipient | `0xC952C53D8B63919e372caa2E6FEe605ee24E4D3D` |
| Fee-recipient contract posture | Deployed Safe, threshold `7` |
| Fee-recipient DN404 posture | `FAME.getSkipNFT(feeRecipient) == true` |
| Initial marketplace state | Paused |
| Initial marketplace inventory | Three Society NFT shells |
| Marketplace CreatorMagic role | `BANISHER` only |
| Art Pool | Excluded |

The observed Mint Pool range was `559..650`; the Art Pool range was `265..419`.
Burn Pool membership and all pool boundaries remain canonical reads, not
hardcoded production constants.

The pinned block above is suitable as the first implementation fixture. Refresh
and intentionally repin it before the final fork acceptance run if production
state changes during implementation.

Relevant predecessor artifacts:

- `src/UniversalPoolArtMarketplace.sol`
- `docs/handoffs/base-sepolia-universal-pool-art-marketplace-to-fls-www.md`
- `docs/plans/2026-07-17-001-feat-universal-pool-art-marketplace-plan.md`
- `fls-www/docs/plans/2026-07-19-001-feat-universal-pool-art-marketplace-plan.md`

## Decisions still required

Do not quietly turn these into defaults:

1. **Production deployer.** The current CreatorArtistMagic owner is
   `0xD52E2A6bBcEba9673440e4D7843Db6713E9B6FD9`, but this handoff does not
   authorize that account to deploy on Base.
2. **Initial marketplace owner.** Decide whether ownership begins with the
   deployer, the configured Base multisig, or another explicitly named account.
3. **Long-term marketplace owner.** If ownership begins with a deployer for
   launch operations, define the later ownership handoff separately.
4. **Safe seed transaction.** Confirm the fee Safe is the intended source of the
   three FAME units used to generate initial marketplace shells.
5. **Production route exposure.** Decide when `/fame/gallery` becomes visible
   after the contract release gates pass.

The fee recipient and marketplace owner are separate concerns. Do not infer
that the treasury Safe must own the marketplace.

## Live feasibility finding

The testnet deploy script seeds three shells from the deployer's FAME balance.
That assumption does not currently work for production:

| Account | Observed FAME balance | Three-unit seed |
| --- | ---: | --- |
| Candidate CreatorMagic owner/deployer `0xD52E...6FD9` | About `44,908 FAME` | Insufficient |
| Fee Safe `0xC952...D3D` | About `34,000,432 FAME` | Sufficient |

Three production units require `3,000,000 FAME`.

Production setup should therefore be split:

1. Deploy the marketplace paused.
2. Grant only CreatorMagic `BANISHER` through the current CreatorMagic owner
   path.
3. Prepare a Safe transaction transferring exactly three FAME units to the
   marketplace.
4. Execute the Safe transfer.
5. Validate that the non-skip marketplace generated exactly three Society NFT
   shells and remains paused.

This is safer and more accurate than forcing an undocumented treasury transfer
to the deployer or pretending the testnet deployer's balance model still
applies.

## Contract behavior being promoted

`UniversalPoolArtMarketplace` is the intended production bytecode.

- One global premium applies to held, Mint Pool, and Burn Pool purchases.
- `maxPremium` protects buyer consent when the premium changes.
- The contract accepts only FAME.
- Existing swap infrastructure acquires FAME from ETH, WETH, or USDC before
  marketplace settlement.
- Marketplace-held artwork uses `purchaseHeld`.
- Mint/Burn artwork uses `purchasePool`, atomically moving selected metadata
  into a marketplace-held shell.
- The buyer receives `shellId`, not the pool `sourceId`.
- A FAME unit transferred into the non-skip marketplace replenishes Society NFT
  inventory before the selected shell leaves.
- Settlement reverts unless `inventoryAfter >= inventoryBefore`.
- Art Pool sources are rejected.
- Ownership renunciation and core-asset rescue are disabled.

The production implementation must not reintroduce listings, per-token
premiums, operator rotation, an off-chain order book, or periodic automation.

## Required `fame-contracts` work

### 1. Add production public configuration

Add a production namespace to `config/fame-public.env`:

```sh
BASE_UNIVERSAL_MARKETPLACE_PINNED_BLOCK=48852841
BASE_UNIVERSAL_MARKETPLACE_PINNED_BLOCK_HASH=0xb79c52084d8888f9b5bde8b66c61769abbc9b420b56ce4cf549d5d873c30eb71
BASE_UNIVERSAL_MARKETPLACE_FEE_RECIPIENT=0xC952C53D8B63919e372caa2E6FEe605ee24E4D3D
BASE_UNIVERSAL_MARKETPLACE_PREMIUM=30000000000000000000000
BASE_UNIVERSAL_MARKETPLACE_MINIMUM_INVENTORY=3
BASE_UNIVERSAL_MARKETPLACE_EXPECTED_PAUSED=true
```

Leave these unset until their decisions or chain facts are known:

```sh
# BASE_UNIVERSAL_MARKETPLACE_DEPLOYER=
# BASE_UNIVERSAL_MARKETPLACE_OWNER=
# BASE_UNIVERSAL_MARKETPLACE_EXPECTED_DEPLOYER_NONCE=
# BASE_UNIVERSAL_MARKETPLACE_ADDRESS=
```

Public addresses, blocks, hashes, and amounts belong in this file. RPC URLs,
private keys, wallet seeds, and explorer keys remain in Doppler.

### 2. Add production deployment tooling

Create production-specific deployment tooling rather than weakening the
Base Sepolia script's canonical checks:

- `script/DeployBaseUniversalPoolArtMarketplace.s.sol`
- `script/ValidateBaseUniversalPoolArtMarketplace.s.sol`
- `script/ActivateBaseUniversalPoolArtMarketplace.s.sol`
- `test/UniversalPoolArtMarketplaceDeploymentValidationBase.t.sol`

The deployment script must:

- require chain ID `8453`;
- validate the exact FAME, mirror, and active CreatorArtistMagic identities;
- validate FAME name, symbol, unit, renderer, and CreatorMagic back-reference;
- validate the configured deployer, owner, and fee recipient without requiring
  the owner to equal the deployer;
- require the starting premium to equal `30,000 FAME`;
- require the fee recipient to have `skipNFT=true`;
- deploy with marketplace `skipNFT=false`;
- begin paused;
- grant only CreatorMagic `BANISHER` when the deployer is canonically
  authorized to do so, otherwise stop after deployment and emit the exact role
  transaction for the CreatorMagic owner path;
- reject `CREATOR`, `ART_POOL_MANAGER`, and FAME `SKIP_MANAGER`;
- predict and validate the deployer nonce-derived address;
- recognize exact partial prefix states; and
- stop after deployment and role setup without assuming the deployer can seed
  three FAME units.

Deployment, CreatorMagic role grant, marketplace ownership, and treasury
seeding are separate authority boundaries. The tooling may combine transactions
only when the same configured signer genuinely controls those boundaries.

Do not add a Base broadcast command to this handoff. Real broadcast remains a
future, explicitly authorized release step.

### 3. Add Safe seed preparation and validation

Create a read-only Safe seed planner that outputs and validates the exact Safe
transaction:

```solidity
FAME.transfer(marketplace, 3_000_000 ether)
```

The planner must freeze:

- chain ID;
- Safe address and Safe nonce;
- marketplace address;
- FAME address;
- transfer calldata;
- exact amount;
- Safe FAME balance;
- marketplace pre-seed inventory;
- marketplace `skipNFT=false`;
- fee Safe `skipNFT=true`; and
- an expiry or explicit regeneration requirement.

The production tool should prepare transaction data for the Safe interface. It
must not store Safe owner keys, fabricate signatures, or broadcast from the Safe.

After execution, the validator must prove:

- Safe FAME decreased by exactly three units;
- marketplace FAME increased by exactly three units;
- marketplace Society NFT inventory increased by exactly three;
- the generated shells are owned by the marketplace;
- marketplace roles remain BANISHER-only; and
- the marketplace remains paused.

### 4. Add production fork tests

Create `test/UniversalPoolArtMarketplaceForkBase.t.sol` with independent modes:

1. Pinned Base integration against the configured block/hash.
2. Current-head ephemeral deployment.
3. Exact deployed-address validation for the local Anvil deployment.
4. Post-activation validation for the local Anvil deployment.

The fork suite must discover usable shells and Mint/Burn sources from canonical
state. It must not hardcode mutable production token IDs.

Coverage must include:

- paused deployment and exact configuration;
- Safe fee recipient code and `skipNFT=true`;
- marketplace `skipNFT=false`;
- BANISHER-only authority;
- three-shell seed;
- held purchase;
- Mint Pool purchase;
- Burn Pool purchase;
- Art Pool rejection;
- premium increase above `maxPremium`;
- premium decrease below `maxPremium`;
- metadata/artwork drift;
- stale shell custody;
- buyer pre-mint of the selected target;
- inventory nondecrease;
- exact premium destination;
- buyer/recipient separation;
- receipt/event reconciliation; and
- pause after activation.

Pinned and current-head cases must fail when the RPC or required environment is
missing. A skipped integration test is not a green release gate.

### 5. Add a foreground fork launcher

Create:

```text
script/start-universal-pool-art-marketplace-base-fork.sh
```

Use `script/start-society-nft-auction-fork.sh` as the operational precedent,
with marketplace-specific behavior.

The launcher must:

- load `config/fame-public.env` before Doppler `prd`;
- start Anvil from the exact configured Base block;
- require the configured block hash;
- use chain ID `8453`;
- use a dedicated port or reject an occupied port;
- enable auto-impersonation for setup only;
- place Foundry broadcast/cache output in a temporary directory;
- clean up temporary output and generated runtime files on exit;
- never write a private key into a generated frontend environment file; and
- stay in the foreground so stopping it destroys the disposable environment.

No storage surgery is allowed for FAME, CreatorMagic, pool membership, roles, or
marketplace state.

## Exact fork setup

### Phase A: attest the pinned production stack

Before deployment, verify:

- chain ID and pinned block hash;
- code at FAME, mirror, CreatorMagic, and fee Safe;
- `FAME.fameMirror() == configured mirror`;
- `FAME.renderer() == configured CreatorMagic`;
- `CreatorMagic.fame() == FAME`;
- FAME unit is exactly `1,000,000 FAME`;
- fee Safe `getSkipNFT == true`;
- CreatorMagic ownership and role authority needed for BANISHER grant;
- current Mint, Burn, and Art Pool predicates; and
- the selected deployer nonce and expected deployment address.

Record the source commit and both repository SHAs before mutation.
Compile with the pinned `universal_marketplace` profile and record the creation
bytecode hash, deployed-bytecode hash, ABI hash, and constructor arguments.

### Phase B: deploy paused

On the fork:

1. Deploy `UniversalPoolArtMarketplace` with:
   - production FAME;
   - production CreatorMagic;
   - `30,000 FAME` premium;
   - the fee Safe;
   - the explicitly selected initial owner.
2. Grant the marketplace CreatorMagic `BANISHER`.
3. Confirm no broader CreatorMagic or FAME role.
4. Confirm `paused == true`.
5. Confirm marketplace `skipNFT == false`.

Compare the local fork runtime with the compiled artifact after substituting the
three compiler-declared immutable addresses. Every non-immutable byte must
match. Generate and retain the standard JSON verification input for later
review, but do not submit it to an explorer during a local fork rehearsal.

The fork deployment should use the exact intended production deployer and nonce
through Anvil impersonation or unlocked fork execution. Do not import a
production deployment key into the browser wallet.

Execute the BANISHER grant through the exact intended CreatorMagic owner path.
If the deployer and CreatorMagic owner differ, keep the transactions separate
and prove both prefix states independently.

### Phase C: execute the Safe seed path

The fork must exercise the Safe contract path, not merely send a transaction
with `from = Safe`.

Preferred rehearsal:

1. Build the exact Safe transaction for the three-unit FAME transfer.
2. Use fork-only impersonation of the Safe owners to approve the Safe
   transaction hash.
3. Execute through the Safe's `execTransaction`.
4. Verify the Safe nonce advanced and the three-unit transfer occurred.
5. Validate the three resulting marketplace shells.

Directly impersonating the Safe address may be used for fixture funding
elsewhere, but it does not prove the production seed transaction is valid.

### Phase D: activate on the fork

Activation remains a separate transaction after paused validation.

On the fork only:

1. Simulate `unpause`.
2. Execute it from the selected owner path.
3. Re-run the validator expecting `paused == false`.
4. Run the post-activation fork suite.

If the intended production owner is a Safe, rehearse its actual Safe execution
path as well. An unlocked transaction pretending to originate from the Safe is
not equivalent evidence.

## Fork-connected `fls-www`

The current gallery implementation is on
`codex/feat-base-sepolia-test-gallery`; at handoff time its head was
`ea94545`.

It already contains:

- `UniversalPoolArtMarketplace` wagmi bindings;
- artwork-first held/Mint/Burn fulfillment;
- global premium and pause handling;
- exact approval and one-button purchase queue;
- receipt-backed `ArtworkPurchased` verification;
- canonical ownership and artwork readback;
- admin premium, fee-recipient, pause, and unpause actions; and
- tested purchase and recovery states.

Production work should add deployment variation points, not rewrite that
feature.

### Production manifest

Add a Base production manifest with:

- chain ID `8453`;
- production FAME, mirror, and CreatorMagic;
- the local fork marketplace address during rehearsal;
- production URL metadata strategy;
- collection bounds;
- fork block/hash diagnostics; and
- explorer base URL for later real deployment.

The production route should be `/fame/gallery`. The existing
`/fame/gallery/test` route remains test infrastructure.

Do not make a runtime network selector. The fork launcher should provide a
generated public environment file that points the production route's Base RPC
and marketplace address at the local fork for that invocation.

### Browser wallet

Use a dedicated browser profile and a dedicated fork-only wallet key.

- Configure its Base (`8453`) RPC to the local Anvil endpoint.
- Never import the production deployer, Safe owner, or treasury key.
- Fund gas with `anvil_setBalance`.
- Fund FAME through actual fork transfers or the real swap path.
- Verify both the app RPC and wallet RPC return the pinned fork ancestry and
  deployed marketplace code before signing.
- Remove or restore the custom Base RPC after the rehearsal.

Using chain ID `8453` is necessary for production-shaped wagmi behavior, but it
creates an obvious footgun: a wallet can silently point back to public Base.
The fork-only key makes that mistake harmless. The browser smoke must still show
the current local marketplace address and fork block before each campaign.

This fork identity check is test harness evidence, not a production wallet
eligibility rule.

## Browser acceptance campaign

Run the campaign against one pinned fork, then restart from the same pinned block
for destructive or race scenarios.

### Catalog and reads

- Production URL metadata renders across held, Mint, and Burn artwork.
- Art Pool entries are absent.
- Held, Mint, and Burn availability matches canonical contract reads.
- Global premium displays as `30,000 FAME` and `3%`.
- Total direct marketplace cost displays as `1,030,000 FAME`.
- Paused and active states are distinguishable.
- No idle-tab polling is introduced.

### Direct-FAME purchases

- Existing sufficient allowance skips approval.
- Insufficient allowance queues exact approval, one confirmation, and purchase.
- Held artwork delivers the selected shell.
- Mint Pool artwork moves into a marketplace shell and delivers that shell.
- Burn Pool artwork moves into a marketplace shell and delivers that shell.
- The completed modal shows delivered shell ID, selected source ID/path,
  artwork, recipient, unit, premium, and transaction hash.

### Swap-then-purchase

Use the existing production swap infrastructure on the fork:

- ETH to FAME to marketplace purchase;
- USDC to FAME to marketplace purchase; and
- WETH to FAME to marketplace purchase where the existing route supports it.

The marketplace call still accepts only FAME. The UI queue must make the swap,
approval, and marketplace stages legible without pretending they are one
transaction.

After the swap, refresh target ownership, pool eligibility, shell custody,
artwork hash, balance, allowance, unit, and premium before simulating the
marketplace call.

### DN404 pre-mint short circuit

Create a deterministic fork case where acquiring FAME mints the exact Society
NFT/artwork the buyer selected.

The UI must:

1. detect post-swap ownership;
2. stop the marketplace queue;
3. show that the buyer already received the selected NFT; and
4. avoid charging the premium or submitting a marketplace purchase.

This is a successful shortcut, not an error.

### Failure and recovery

- Premium above frozen `maxPremium` stops before purchase.
- A lower premium succeeds and transfers the lower amount.
- Pausing between preparation and submission stops the purchase.
- A stale shell or pool source refreshes routing.
- Metadata hash changes require refreshed buyer consent.
- Wallet rejection stops the queue without submitting later stages.
- A mined purchase with failed follow-up reads remains confirmed and retries
  verification.
- Transaction replacement uses wagmi/viem behavior already established by the
  feature.

## Fork evidence to preserve

Create a curated fork report outside Foundry `broadcast/` output containing:

- Base block number and hash;
- `fame-contracts` and `fls-www` commits;
- compiler, EVM, optimizer, and `via_ir` settings;
- constructor arguments;
- intended deployer, nonce, and predicted address;
- local deployed address and runtime code hash;
- marketplace owner and fee recipient;
- premium and unit;
- Safe seed calldata, Safe nonce, and fork transaction hash;
- generated shell IDs and artwork hashes;
- final role masks and skip-NFT posture;
- activation transaction hash;
- held, Mint, Burn, ETH, USDC, and WETH purchase hashes where applicable;
- `ArtworkPurchased` and mirror transfer reconciliation;
- fee Safe balance deltas;
- inventory before/after values;
- screenshots or concise browser notes for the completed buyer flows; and
- every skipped or blocked scenario with its reason.

Generated Anvil and Foundry broadcast logs remain temporary and uncommitted.

## Go/no-go review before discussing Base deployment

The fork milestone is complete only when:

1. Local unit, 10,000-case fuzz, and 512 x 128 invariant campaigns pass.
2. Pinned and current-head Base fork suites execute with zero required skips.
3. The production deployment script leaves the contract paused and correctly
   permissioned.
4. The Safe seed transaction executes through the Safe path and creates three
   marketplace shells.
5. The paused validator passes.
6. Fork activation and post-activation validation pass.
7. `fls-www` and the browser wallet both use the same local Base fork.
8. Held, Mint, and Burn purchases pass through the real UI.
9. At least ETH and USDC swap-then-purchase paths pass; WETH must pass when its
   production route is available.
10. The DN404 pre-mint short circuit passes.
11. Receipt/event/ownership/artwork/inventory/fee verification passes.
12. The fork report is reviewed with no unexplained state drift.
13. Production deployer and owner are explicitly selected.
14. Fork runtime bytecode and ABI match the pinned build artifacts, and the
    future explorer verification input is reproducible.

Passing this checklist does not authorize deployment. It creates the evidence
needed for a separate production deployment decision.

## Explicitly out of scope

- Any Base mainnet broadcast.
- Any production Safe signature collection or transaction submission.
- Any ownership transfer on Base.
- Any public `/fame/gallery` launch.
- Any change to the locked 30,000 FAME starting premium.
- Any Art Pool marketplace support.
- Any rewrite of the working `fls-www` gallery transaction system.
