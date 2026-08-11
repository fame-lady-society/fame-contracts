# Marketplace Final Acceptance Review Decisions

**Branch:** `codex/closed-loop-gallery-swap`  
**Review run:** `20260807-093642-41f7e0a0`  
**Started:** 2026-08-07  
**Status:** Decision complete -- accepted work is ready for implementation and
final verification

This record governs findings from the final marketplace and checkout review. It
extends `docs/gallery/marketplace-checkout-review-decisions.md`. When the two
records cover the same behavior, the newer accepted decision in this record is
authoritative.

Decision vocabulary:

| Decision | Meaning |
| --- | --- |
| **Accept** | Implement the stated outcome and acceptance checks |
| **Accept with updates** | Implement the outcome with the recorded adjustment |
| **Discuss** | Product or release behavior is still open |
| **Deferred** | Return to the issue after every other review decision is settled |
| **Reject** | Take no action; preserve the current behavior intentionally |
| **Applied** | The accepted work has landed and passed its required checks |

## Accepted decisions

### FA1. Unsolicited Society NFT custody is a checkout boon

**Review finding:** A raw Society NFT transfer to `FameMarketplaceCheckout`
causes a later purchase to burn that NFT while refunding its underlying FAME,
then revert because the checkout compares its final Society balance with the
nonzero starting balance.

**Decision:** **Accept** (2026-08-07)

Successful purchase checkout must end with zero Society NFTs. An unsolicited
Society NFT and its underlying FAME are a boon to the next successful checkout
buyer. The checkout does not preserve its starting Society balance and does not
return the NFT or FAME to the sender. (session-settled: user-directed -- chosen
over preserving or recovering the unsolicited NFT: the Society NFT and its
underlying FAME are a boon, and checkout only needs to assert a zero final
Society balance.)

Required outcome:

- Replace the starting-versus-final Society balance equality with a strict zero
  final-balance assertion.
- Remove the obsolete starting Society-balance snapshot and the obsolete
  `MirrorBalanceChanged` contract if it has no remaining use.
- Keep the full-balance route-asset boon policy accepted by R1 in the prior
  decision record.
- Fail closed if any Society NFT remains on checkout after settlement.
- Do not add owner rescue, sender recovery, or a separate sweep path for this
  case.

Acceptance checks:

- Raw `mirror.transferFrom` can place one Society NFT on checkout before a held
  purchase, and the held checkout still succeeds.
- The same setup before a pool purchase also succeeds.
- The successful buyer receives the unsolicited NFT's underlying FAME as part
  of the checkout boon.
- Checkout ends with zero Society NFTs, zero FAME, and zero marketplace and
  router allowances.
- Receipt assertions identify the full FAME boon and the purchased shell still
  reaches the intended recipient.
- A bounded multiple-NFT case proves cleanup does not exceed the supported gas
  posture.

**Implementation status:** Accepted, not yet applied.

### FA7. Normalize `ArtworkPurchased` as a gross premium-charge receipt

**Review finding:** `ArtworkPurchased.premiumAmount` can exceed the buyer's net
FAME balance reduction when a premium leg transfers FAME back to the payer,
most visibly when the buyer is also the fee recipient.

**Decision:** **Accept with updates** (2026-08-07)

`ArtworkPurchased` reports normalized marketplace settlement accounting, not
the attributed buyer's net economic cost. Rename `premiumAmount` to
`grossPremiumAmount`. The value is the full configured premium charged through
the marketplace's premium-transfer path. (session-settled: user-directed --
the full amount must always be charged and transferred, including a self-
transfer, for accounting and event normalization.)

Required outcome:

- Rename the event field and corresponding documentation/test terminology to
  `grossPremiumAmount`.
- Always execute the full configured community and provider premium transfer
  legs. Do not waive or net a leg because the payer is also its recipient.
- Count every executed premium leg in `grossPremiumAmount`, including a
  transfer from the payer back to itself.
- Keep `grossPremiumAmount == communityFee + providerFee` for an ordinary
  purchase regardless of buyer, payer, or fee-recipient identity.
- Do not describe this field as the buyer's net debit. Multi-asset input spend,
  refunds, and marketplace charge remain checkout-receipt concerns.

Acceptance checks:

- Direct and checkout purchases emit the same gross premium for the same fee
  configuration.
- A fee-recipient payer still executes the self-transfer, consumes the expected
  allowance, and emits the full gross premium even though that leg has zero net
  balance effect.
- A provider who is also the payer does not receive an implicit self-payment
  waiver.
- Provider/community distribution plus rounding behavior still accounts for
  the entire gross premium.

**Implementation status:** Accepted, not yet applied.

### FA14. Forbid checkout as the marketplace fee recipient

**Review finding:** The marketplace owner can set the authorized checkout as
`feeRecipient`. A checkout purchase then executes the premium self-transfer
from checkout back to checkout, so checkout's balance decreases only by the
Society unit instead of the quoted unit plus premium and settlement reverts on
its measured-charge assertion.

**Decision:** **Accept** (2026-08-07)

Checkout and marketplace fee-recipient roles are mutually exclusive. Enforce
that invariant in the contract, not only in deployment validation.

Required outcome:

- `setFeeRecipient` rejects the current nonzero `authorizedCheckout`.
- `setAuthorizedCheckout` rejects the current `feeRecipient`.
- Preserve both guards so configuration order cannot bypass the invariant.
- Keep the production validator's independent checkout/fee-recipient check.
- Continue allowing an ordinary direct buyer to also be the fee recipient;
  FA7's gross self-transfer accounting governs that supported case.

Acceptance checks:

- Both setter orderings revert with an exact custom-error assertion.
- Clearing or replacing checkout remains possible while paused.
- A valid distinct fee recipient and checkout continue to settle held and pool
  purchases.

**Implementation status:** Accepted, not yet applied.

### FA3. Permit nonempty launch state subject to pool invariants

**Review finding:** The production validator accepts a nonempty internally
consistent market even though the handoff declares exact zero inventory,
providers, and provider units to be a launch requirement.

**Decision:** **Accept with updates; reject the empty-launch premise**
(2026-08-07)

An empty marketplace is not a release-safety requirement. Seeded inventory,
credited provider deposits, raw FAME, and donated Society NFTs may exist before
activation. They do not block launch merely because their balances are
nonzero. (session-settled: user-directed -- the documented empty-launch state
was planner overreach; stakes or donations make no safety difference absent a
specific broken invariant.)

Required outcome:

- Remove exact-empty launch language and no-go assertions from the production
  handoff and related release documentation.
- Do not require a configured inventory count to match live permissionless
  state. Record observed state for operations without treating a donation or
  deposit as release drift.
- Retain and strengthen structural checks: active providers do not exceed the
  cap; every provider has a unique consistent index and nonzero units; summed
  units equal `totalProviderUnits`; inventory covers all credited provider
  units; and marketplace FAME covers all credited unit liabilities.
- Keep checkout cleanliness exact: checkout Society balance, transient asset
  balances, and marketplace/router allowances must be zero outside a
  transaction.
- Keep gas qualification at the fixed 88-provider cap, so any accepted launch
  provider state remains within the proven settlement bound.

Acceptance checks:

- Donation-only inventory, fractional raw FAME, and valid credited provider
  inventory can each pass readiness validation.
- Inconsistent provider indexing, summed units, inventory backing, or FAME
  backing fails validation.
- Dirty checkout custody or allowances still fails validation.

**Implementation status:** Accepted, not yet applied.

### FA4. Complete checkout accounting rollback tests

**Review finding:** The prior decision accepted exact-selector, full-rollback
tests for five checkout accounting guards, but no test directly exercises
those errors.

**Decision:** **Accept with updates** (2026-08-07)

Add direct tests for the four accounting guards that remain after FA1. The
fifth accepted guard, `MirrorBalanceChanged`, is removed by FA1 and is
superseded by the raw-Society-boon held/pool regressions recorded there.

Required test cases:

- `RouterOutputMismatch`
- `MarketplaceChargeMismatch`
- `RefundBalanceMismatch`
- `FameAccountingMismatch`

Every case must pin the exact selector and prove complete transaction rollback,
including buyer funding, route state, router and marketplace allowances,
checkout balances, shell ownership and artwork, marketplace inventory, and
provider/community payments relevant to the induced failure.

**Implementation status:** Accepted, not yet applied.

### FA5. Remove the stale Base Sepolia smoke premium waiver

**Review finding:** The Base Sepolia smoke funds and approves only three
Society units when its buyer is also the marketplace fee recipient. The
accepted no-waiver behavior still executes three premium self-transfers and
consumes their allowance, so the focused smoke test reverts with
`InsufficientAllowance()`.

**Decision:** **Accept** (2026-08-07)

The three-purchase smoke always funds and approves three complete marketplace
charges, regardless of buyer or fee-recipient identity.

Required outcome:

- Set the smoke requirement to `3 * (unit + premium)` unconditionally.
- Remove the buyer/fee-recipient funding and allowance waiver.
- Preserve the result validator's correct net-balance special case: premium
  self-transfers have zero net FAME balance effect even though they are charged
  and consume allowance.
- Rename the misleading test that says a fee-recipient buyer uses only three
  units.
- Align smoke event assertions with FA7's full `grossPremiumAmount` semantics.

Acceptance checks:

- Both ordinary-buyer and fee-recipient-buyer smoke cases execute held,
  mint-pool, and burn-pool purchases.
- Each purchase reports the full gross premium.
- Final marketplace allowance is zero and result accounting matches the
  buyer's actual net balance.

**Superseding decision:** FA8 removes the Base Sepolia marketplace smoke and
its deployment track entirely. Do not implement the funding correction in a
script that will be deleted. The underlying gross-charge behavior remains
covered by FA7's chain-independent contract tests.

**Implementation status:** Superseded by FA8; delete instead of repairing.

### FA6. Pin the production ownership handoff to the Society Safe

**Review finding:** The ownership-transfer script accepts any nonzero address
other than the current owner, even though transferring ownership is the
irreversible production handoff and the deployment contract already identifies
the intended Society Safe.

**Decision:** **Accept** (2026-08-07)

The production ownership-transfer script must accept only the exact Society
Safe at `0xC952C53D8B63919e372caa2E6FEe605ee24E4D3D`. A caller-supplied arbitrary
future owner is not a supported production path.

Required outcome:

- Pin the expected future owner to
  `0xC952C53D8B63919e372caa2E6FEe605ee24E4D3D`.
- Reject a zero address, the current owner, or any address other than that
  exact Safe before broadcast.
- Require deployed code at the Safe address before transferring ownership.
- Preserve the existing paused-state, current-owner, signer-authority, and
  post-transfer ownership checks.

Acceptance checks:

- The exact configured Society Safe passes preflight when it has code.
- An arbitrary nonzero contract or EOA fails before broadcast.
- A code-less address fails even if it equals a supplied environment value.
- The post-transfer assertion proves that the marketplace owner is the exact
  pinned Safe.

**Implementation status:** Accepted, not yet applied.

### FA16. Harden checkout receipt and exact-revert coverage

**Review finding:** Fork tests recognize `CheckoutSettled` primarily by its
topic rather than asserting its complete payload, and two checkout tests use a
bare `expectRevert` despite having deterministic failure contracts.

**Decision:** **Accept** (2026-08-07)

Checkout tests must prove the normalized settlement receipt and identify the
exact intended failure. `ArtworkPurchased` gross-premium receipt semantics are
covered separately by FA7 and are not duplicated here.

Required outcome:

- Decode and assert every `CheckoutSettled` field for representative held and
  pool checkout paths: buyer, input asset, shell ID, route hash, fulfillment
  path, source ID, artwork, input amount, input refund, router FAME output,
  marketplace FAME charge, and FAME refund.
- Replace the rejecting native-refund recipient's bare revert assertion with
  the exact `SafeTransferLib.ETHTransferFailed` selector.
- Replace the late-failure fuzz test's bare revert assertion with the exact
  `BuyerMirrorBalanceTooLow(2, 1)` payload.
- Preserve the existing full transaction-rollback assertions in both failure
  cases.

Acceptance checks:

- Held and pool receipts prove their complete accounting and fulfillment
  payloads, not only event presence.
- Both formerly bare reverts fail if a different error becomes the terminal
  failure.
- Rollback coverage continues to include buyer and venue balances, allowances,
  router state, marketplace inventory, shell ownership, and fee transfers
  applicable to each case.

**Implementation status:** Accepted, not yet applied.

### FA8. Remove the Base Sepolia gallery and marketplace track

**Review finding:** Repository handoffs and scripts treat an obsolete Base
Sepolia marketplace deployment as an integration or replacement-deployment
target even though Base Sepolia is not a canonical product environment.

**Decision:** **Accept with expanded scope** (2026-08-07)

Base Sepolia is not a canonical marketplace environment. Remove the gallery
and marketplace deployment track and its repository artifacts rather than
retiring, pausing, replacing, or documenting the old deployment. The immutable
on-chain contracts receive no further operational action and are not a product
or integration surface. (session-settled: user-directed -- remove Base
Sepolia, its tests, deployment scripts, and related artifacts, and proceed as
though the deployment never happened.)

Required outcome:

- Delete the Base Sepolia marketplace and gallery deployment, activation,
  validation, smoke, and result-validation scripts.
- Delete the Base Sepolia marketplace fork and smoke tests; preserve equivalent
  chain-independent and canonical Base coverage where it already exists.
- Delete the `fls-www` Base Sepolia handoff and Base Sepolia gallery/marketplace
  deployment documents.
- Remove marketplace/gallery-specific Base Sepolia public configuration and
  references from active plans, handoffs, commands, and release gates.
- Delete earlier Base Sepolia gallery launch artifacts that exist only for this
  discarded product track. Do not remove unrelated chain support merely
  because it shares the Base Sepolia chain ID.
- Do not leave a retired-address manifest, compatibility path, replacement
  deployment requirement, or operational pause task.
- Treat canonical Base deployment and validation as the only marketplace
  release target.

Acceptance checks:

- No active script, test, handoff, config entry, or plan instructs an operator
  or frontend to deploy, validate, smoke, activate, or integrate this
  marketplace on Base Sepolia.
- No release gate depends on a Base Sepolia RPC, address, contract, or receipt.
- Canonical Base and local/fork contract coverage remains sufficient for the
  accepted marketplace and checkout behavior.

**Related decisions:** FA5 is superseded: its obsolete smoke is deleted rather
than repaired. FA9, FA11, and FA12 are resolved by removal: there is no Base
Sepolia `fls-www` handoff to complete, marketplace CreatorMagic input to add,
or fictional global-premium admin request to map.

**Implementation status:** Accepted, not yet applied.

### FA10. Make the governing documents consistent with the boon policy

**Review finding:** The authoritative checkout plan and its durable solution
still contain delta-only purchase-refund requirements alongside the later
accepted full-balance boon policy.

**Decision:** **Accept** (2026-08-07)

The accepted boon policy is the sole accounting contract. Remove obsolete
language that requires pre-existing checkout balances to survive a successful
purchase or describes transfer of the checkout's remaining snapshotted balance
as an anti-pattern.

Required outcome:

- State that ambient balances cannot satisfy the caller's required input or
  the marketplace charge.
- After successful purchase or redemption settlement, transfer the full
  remaining balance of every snapshotted route asset to the successful caller,
  including ambient balances and transaction-local surplus.
- Preserve complete rollback on any failed settlement or refund.
- Align Society custody with FA1: successful checkout ends with zero Society
  NFTs, and unsolicited Society backing FAME participates in the boon.
- Reconcile requirement lists, examples, diagrams, rejected-pattern sections,
  and summaries in the governing plan and solution; do not leave both policies
  presented as path-specific alternatives.

Acceptance checks:

- Searches for delta-only, pre-call-baseline, and pre-existing-balance language
  find no active requirement contradicting the boon policy.
- Accounting equations distinguish transaction funding from post-settlement
  boon distribution.
- The plan, solution, decision records, contract behavior, and tests describe
  the same successful and reverting outcomes.

**Implementation status:** Accepted, not yet applied.

### FA13. Upgrade and pin the production compiler profile

**Review finding:** Production deployment and validation examples omit the
dedicated Foundry profile, and that profile still pins Solidity `0.8.28`, a
release from October 2024 rather than the current stable compiler.

**Decision:** **Accept with updates** (2026-08-07)

Upgrade the marketplace release profile to the current stable Solidity
compiler, `0.8.36`, and require that exact profile throughout release work.
Compiler freshness does not permit floating build settings: the compiler, EVM
target, optimizer, and pipeline remain explicit and reproducible.

Required outcome:

- Change `profile.universal_marketplace.solc_version` from `0.8.28` to exactly
  `0.8.36`.
- Keep `evm_version = "cancun"`, optimizer enabled with 200 runs, and
  `via_ir = false`; do not inherit the newer compiler's default EVM target or
  enable experimental code generation.
- Require `FOUNDRY_PROFILE=universal_marketplace` for every marketplace and
  checkout build, size check, unit/fuzz/invariant/fork campaign, script test,
  deployment simulation, verification, live deployment, validation,
  activation, and ownership-handoff command.
- Record the exact Forge version, Solidity version, profile settings, source
  commit, creation-bytecode hash, runtime-bytecode hash, ABI hash, and deployed
  size in release evidence.
- Immediately before production broadcast, verify that `0.8.36` remains the
  latest stable compiler. If a newer stable release exists, do not silently
  change the pin: upgrade and rerun this complete compiler-verification gate.

Compiler-upgrade verification gate:

- Review intervening Solidity release notes and known-bug fixes for relevance
  to the contracts and their dependencies.
- Require clean compilation with all new warnings either fixed or explicitly
  dispositioned.
- Diff ABI, storage layout, creation bytecode, runtime bytecode, deployed size,
  and gas evidence against the `0.8.28` baseline; explain every change.
- Run the complete scoped unit, fuzz, invariant, deployment-script, Base fork,
  checkout receipt, accounting rollback, provider-cap gas, and selected-exit
  gas campaigns under `0.8.36` with no required skip.
- Rehearse the exact no-broadcast production command and confirm its artifact
  hashes match the reviewed release artifacts before seeking broadcast
  authorization.

**Implementation status:** Accepted, not yet applied.

### FA15. Make production deployment prefix-aware and resumable

**Review finding:** Marketplace deployment submits three sequential
transactions--marketplace creation, checkout creation, and checkout
authorization--but provides no safe recovery contract when only a prefix is
mined. Replaying the whole script can create duplicate contracts or wire a
different stack.

**Decision:** **Accept** (2026-08-07)

Production deployment must be an explicit, receipt-aware state machine. Any
uncertain or partial outcome stops automatic execution. Recovery inspects the
canonical chain and resumes only from the first unexecuted step; it never
replays a confirmed prefix.

Required outcome:

- Before broadcast, pin the chain ID, deployer, starting nonce, predicted
  marketplace and checkout addresses, source commit, compiler/profile, ABI and
  bytecode hashes, constructor inputs, and authorization calldata.
- Require the deployer nonce and predicted-address code state to match the
  untouched preflight state before submitting the first transaction.
- Persist a deployment manifest containing each expected nonce, transaction
  purpose, predicted address or target, calldata hash, submitted transaction
  hash, replacement history, receipt status, block, and observed result.
- After each transaction, verify its receipt and the relevant code hash,
  immutable dependencies, owner/configuration, or checkout authorization before
  advancing.
- On a dropped, replaced, reverted, timed-out, or otherwise uncertain
  transaction, stop. Reconcile the canonical receipt, current nonce, code, and
  contract state before choosing a recovery step.
- Provide step-specific recovery paths for the four valid prefixes: nothing
  mined; marketplace only; marketplace plus checkout; and the fully authorized
  stack. A recovery path must consume the recorded addresses and must not
  redeploy an already confirmed contract.
- Treat any unexpected code, nonce consumption, bytecode hash, constructor
  dependency, ownership, or authorization state as a no-go requiring manual
  disposition.
- Apply the same receipt discipline to later activation and ownership-handoff
  operations, while keeping their separate authorization requirements.

Acceptance checks:

- Fork rehearsals force interruption after every prefix and prove that each
  resume path converges on the one predicted marketplace-plus-checkout stack.
- Replaying a completed deployment or resuming with mismatched addresses,
  nonces, artifacts, or configuration fails before broadcast.
- Replacement and reverted transaction fixtures cannot be mistaken for a
  successful step.
- Final validation binds the manifest's addresses and hashes to canonical Base
  state before activation or frontend configuration.

**Implementation status:** Accepted, not yet applied.

### FA17. Scope deployment-size gates to deployable release contracts

**Review finding:** The literal repository-wide `forge build --sizes` command
fails because legacy `FameLadySocietyOwners`, `OnChainCheckGasOwners`, and
`OnChainGasOwners` exceed EIP-170, although they are local scripts and are not
deployment targets for this release.

**Decision:** **Accept** (2026-08-07)

Do not modify the unrelated local-only scripts. Contract-size readiness applies
to the contracts whose bytecode this release can actually deploy, while normal
repository compilation and tests remain a separate regression gate.

Required outcome:

- Scope the release size gate to `UniversalPoolArtMarketplace` and
  `FameMarketplaceCheckout` plus any newly introduced deployable helper owned
  by this release.
- Under the pinned Solidity `0.8.36` profile, enforce the EIP-170 deployed
  runtime limit and the EIP-3860 initcode limit for each release target.
- Record exact runtime size, initcode size, applicable limit, and remaining
  headroom in the release evidence.
- Keep the full-repository compile and test regression gates, but do not use a
  repository-wide size command whose exit status is determined by local-only,
  non-deployed legacy scripts.
- Do not refactor, suppress, or otherwise alter the three unrelated oversized
  local scripts as part of marketplace acceptance.

Acceptance checks:

- The target-scoped size command fails when either release contract exceeds an
  applicable deployment limit.
- The same command is unaffected by the known local-only script sizes.
- Final `0.8.36` evidence replaces the earlier `0.8.28` observations of 16,469
  bytes for checkout and 15,066 bytes for marketplace.

**Implementation status:** Accepted, not yet applied.

### FA2. Replace random withdrawal with a 24-hour selected-exit boon

**Review finding:** The nominally random free withdrawal can be wrapped by a
contract that rejects unwanted results and retries, allowing a sophisticated
provider to grind toward a chosen pooled shell without paying the selected-exit
premium. Onchain randomness, a two-phase oracle flow, and forced fulfillment
would add substantial cost, liveness, callback-gas, and operational complexity
without improving the core pool accounting.

**Decision:** **Accept with replacement design** (2026-08-07)

Remove random withdrawal. Every provider unit is an explicit claim on one
currently pooled Society NFT of the provider's choosing. Exercising that claim
costs a premium that decays with that unit's age and becomes free after 24
hours. The mature selected exit is an intentional boon to providers. It does
not promise return of the deposited token. (session-settled: user-directed --
accept the bounded ability to select a marketplace-held token after 24 hours in
exchange for a substantially simpler design.)

Required outcome:

- Remove the pseudo-random `withdrawInventory()` path, `withdrawalNonce`,
  `withdrawalCursor`, scan-step accounting, random-start hashing, and their
  obsolete tests and documentation.
- Keep one selected withdrawal entrypoint that accepts `tokenId` and
  `maxPremium`. Rename it to the simple canonical withdrawal name rather than
  retaining obsolete random-versus-selected compatibility surfaces.
- Give every deposited provider unit its own deposit timestamp. Batch-deposited
  units share their actual batch timestamp; a new deposit must not reset or
  borrow the age of existing units.
- Consume the provider's oldest unit first.
- Compute the required premium from the current configured gross premium and
  the consumed unit's age: full at deposit, linearly decaying, rounded up while
  any time remains, and exactly zero at age greater than or equal to 24 hours.
- Preserve the caller's `maxPremium` consent bound against fee changes and
  time/rounding computation.
- Remove the exiting unit from provider liabilities before distributing a
  nonzero premium, so it does not rebate itself. Apply FA7's gross charge and
  transfer normalization to every executed premium leg.
- Require the marketplace to own the selected Society token at execution, then
  atomically call the mirror's safe transfer from the marketplace to the
  provider. The DN404 transfer moves the exact shell and its underlying FAME
  unit together.
- Keep provider exit available while the market is paused.
- Add no VRF, oracle subscription, keeper, commit/reveal, callback, randomness,
  contract-caller restriction, or compatibility path.

Product and race contract:

- A mature provider unit is a delayed any-shell claim limited to NFTs currently
  held by the marketplace.
- The selected NFT remains publicly purchasable until the withdrawal
  transaction lands. A purchase that wins first makes withdrawal revert with
  no premium or unit consumed; a withdrawal that wins first makes a competing
  purchase fail its availability check.
- Each successful withdrawal consumes exactly one provider unit and transfers
  exactly one selected pooled Society NFT plus its FAME backing. It cannot
  withdraw an external token, mint an extra claim, or reduce pool solvency.

Acceptance checks:

- Premium tests cover age zero, intermediate decay, one second before maturity
  with upward rounding, exactly 24 hours, and later than 24 hours.
- Multi-unit and batch tests prove oldest-first consumption and independent
  aging across later deposits.
- Zero- and nonzero-premium paths assert exact gross transfers, provider-unit
  accounting, active-provider removal, inventory, NFT ownership, and FAME
  balances.
- Purchase-versus-withdrawal contention proves atomic winner/loser behavior and
  complete rollback.
- Rejecting NFT recipients, unavailable IDs, insufficient provider units, and
  exceeded premium consent preserve custody, liabilities, fees, and timestamps.
- No random-withdrawal state, ABI, tests, gas gate, or product promise remains.

**Implementation status:** Accepted, not yet applied.

## Decision queue complete

All findings and residual review issues have a recorded disposition. Accepted
items remain unimplemented until the implementation and verification pass.

## Changelog

| Date | Change |
| --- | --- |
| 2026-08-07 | Accepted FA2 with a replacement design: remove random withdrawal and make each provider unit an explicit selected-shell claim whose premium decays to zero after 24 hours. The mature selected exit is an intentional provider boon. |
| 2026-08-07 | Accepted FA17: enforce runtime and initcode limits only for deployable release contracts; leave the unrelated oversized local scripts untouched. |
| 2026-08-07 | Accepted FA15: require predicted-address, nonce-pinned, receipt-aware production deployment with tested step-specific recovery for every partially mined prefix. |
| 2026-08-07 | Accepted FA13 with updates: upgrade the pinned compiler from Solidity `0.8.28` to current stable `0.8.36`, retain an explicit Cancun/optimizer/non-IR profile, and require a complete compiler-delta verification before broadcast. |
| 2026-08-07 | Resolved FA12 through FA8 removal: the nonexistent global-premium admin request existed only in the deleted Base Sepolia handoff and does not create a production-admin deliverable. |
| 2026-08-07 | Accepted FA10: remove delta-only contradictions and make successful full-balance boon distribution, transaction funding isolation, and failure rollback consistent across governing documents. |
| 2026-08-07 | Accepted FA8 with expanded scope: remove the noncanonical Base Sepolia gallery/marketplace track as though it never happened; FA5 is superseded and FA9/FA11 are resolved by deletion. |
| 2026-08-07 | Accepted FA16: fully assert held and pool `CheckoutSettled` receipts, pin the two deterministic revert contracts, and preserve complete rollback coverage. |
| 2026-08-07 | Accepted FA6: restrict the irreversible production ownership transfer to the exact deployed Society Safe and reject arbitrary future owners before broadcast. |
| 2026-08-07 | Accepted FA5: always fund and approve three full marketplace charges in the Base Sepolia smoke while preserving the fee-recipient buyer's net-balance accounting. |
| 2026-08-07 | Accepted FA4 with updates: add exact-selector, full-rollback tests for the four surviving checkout accounting guards; FA1 supersedes the obsolete `MirrorBalanceChanged` case. |
| 2026-08-07 | Accepted FA3 with updates and rejected the exact-empty premise: nonempty seeded, donated, or provider-backed launch state is valid when pool solvency, provider structure, checkout cleanliness, and gas bounds hold. |
| 2026-08-07 | Accepted FA14: enforce checkout/marketplace-fee-recipient separation in both setter directions and retain the independent deployment guard. |
| 2026-08-07 | Accepted FA7 with updates: rename the event field to `grossPremiumAmount`, always transfer the full configured premium, and treat it as normalized gross settlement accounting rather than buyer net debit. |
| 2026-08-07 | Deferred FA2 and its MEV-resistant random-withdrawal design until every other review decision is settled. |
| 2026-08-07 | Created the final-acceptance decision record. Accepted FA1: unsolicited Society NFT and underlying FAME are a boon; successful checkout must assert zero final Society balance. |
