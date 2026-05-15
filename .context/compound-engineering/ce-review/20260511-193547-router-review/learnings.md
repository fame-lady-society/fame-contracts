## Institutional Learnings Search Results

### Search Context
- **Feature/Task**: CE review for FAME Solidity multi-leg swap router: route-local accounting, external venue adapters, Foundry fork fixtures, and Base validation.
- **Keywords Used**: router, route, swap, multi-leg, adapter, venue, accounting, Foundry, fork, fixture, Base, validation, Solidity, FAME, Universal Router, native ETH, WETH, Slipstream.
- **Files Scanned**: 6 files under `docs/`; 10 CE review artifacts under `.context/compound-engineering/ce-review/`; 0 files under `docs/solutions/` because that directory is absent.
- **Relevant Matches**: 10 high-signal matches.

### Critical Patterns
- No `docs/solutions/patterns/critical-patterns.md` or equivalent critical-pattern file is present.

### Relevant Matches

#### Router Schema And Launch Boundary
- **Files**: `docs/router/fame-router-schema.md`, `docs/router/fame-router-validation.md`
- **Key Insight**: The documented contract boundary is deterministic exact-input settlement, not route discovery. Route-local balance deltas, final-output fee accounting, native ETH as `address(0)`, and `www` schema parity are core invariants.
- **Gotcha**: The current docs explicitly say production Base fixture snapshots, live venue payload formats, and all-pool/all-route fork fixtures remain launch-blocking.

#### Requirements And Planning Corpus
- **Files**: `docs/brainstorms/2026-05-11-fame-multi-leg-router-requirements.md`, `docs/plans/2026-05-11-001-feat-fame-multi-leg-router-plan.md`, `docs/ideation/2026-05-10-fame-multi-leg-router-ideation.md`
- **Key Insight**: Full-venue v1 launch requires frozen Base fixtures for Scale/Equalizer V2, Uniswap V2, Slipstream, Slipstream 2 / Gauge Caps, Uniswap V3, and Uniswap V4. Partial venue launch was explicitly rejected unless the v1 snapshot is revised.
- **Gotcha**: "Validated" is split: `www` quote/calldata validation is not contract execution validation. Contract readiness requires pinned Base fork execution plus fresh live Base validation.

#### Venue Adapter Warnings
- **Files**: `.context/compound-engineering/ce-review/20260511-193754-fame-router-review/review.md`, `.context/compound-engineering/ce-review/20260511-193547-router-review/security.json`, `correctness.json`, `api-contract.json`, `maintainability.json`
- **Key Insight**: Multiple reviewers converged on the same P1: current adapter libraries use a generic `IRouterLegExecutor.executeLeg` scaffold, not real Solidly, Uniswap V2, Slipstream, or Universal Router ABIs.
- **Gotcha**: A schema-following `www` client that passes real venue router targets and venue calldata will not match the current adapter ABI. Either the schema must document Fame adapter targets, or the code must implement real per-family venue adapters.

#### Universal Router And V4 Constraints
- **Files**: `docs/ideation/2026-05-10-fame-multi-leg-router-ideation.md`, `docs/plans/2026-05-11-001-feat-fame-multi-leg-router-plan.md`, `.context/.../api-contract.json`, `.context/.../security.json`
- **Key Insight**: Raw Universal Router passthrough was rejected. V3/V4 support needs structured command construction or strict allowlists covering Permit2, payer, recipient, sweep/take/settle, wrap/unwrap, PoolKey, hooks, and hook-data boundaries.
- **Gotcha**: V4 ZORA/ETH is native ETH-backed, not WETH-only. Native ETH and WETH must stay distinct in schema, tests, settlement, and frontend UX.

#### Fixture And Validation Gaps
- **Files**: `.context/.../testing.json`, `.context/.../correctness.json`, `.context/.../2026-05-11-fame-router-autofix/review.md`, `docs/fame-release-plan.md`
- **Key Insight**: Existing router tests prove a useful mock-backed skeleton, but not launch readiness. The Base fork harness is currently smoke/placeholder evidence until nonzero pinned blocks, pool metadata, and route fixture execution are filled in.
- **Gotcha**: `script/ValidateFameRouterBase.s.sol` is currently documented as a config/manifest guard. It still needs pool metadata checks, route execution or simulation, deployed skip-NFT confirmation, and `www` schema/fixture parity before ownership transfer.

### Recommendations
- Treat generic `executeLeg` adapters as test scaffolding only; require typed per-family adapters or explicitly documented Fame adapter targets before calling the schema production-ready.
- Keep route-local accounting as a non-negotiable invariant: no ambient balances for leg spend, leg minimums, final minimums, fee settlement, or `BalanceBps`/`All` modes.
- Do not downgrade the launch gate without an explicit product decision: every frozen v1 venue family needs buy/sell fixture evidence on a pinned Base fork.
- Expand `fame-router-schema.md` with canonical enum wire values, amount-mode ranges/rounding, ignored `All.amount`, payload schemas, route identity/event expectations, and venue target semantics.
- Expand live Base validation before deploy/ownership transfer: chain ID, fee config, enabled target parity, fixture manifest launchability, pool metadata, route simulation/execution, skip-NFT state, and `www` snapshot/schema parity.
- Add negative tests around Universal Router commands, V4 PoolKey/hooks, unexpected recipients/payers, approval cleanup, fee-on-transfer or malicious tokens, intermediate native ETH, and native ETH/WETH leftover separation.
