# Base Society provider-cap benchmark

The production active-provider cap in `config/fame-public.env` is `88`, selected from the passing latest-head Base qualification run recorded below. Rerun both lanes before deployment if the implementation, configured fees, live FAME stack, or intended release head changes materially.

## Required lanes

- `FameMarketplaceCheckoutForkBaseTest::testBenchmarkLatestBaseCandidateCapCheckoutMintsForEveryProviderPayout` deploys the candidate-cap marketplace against the live FAME/CreatorMagic stack, fills every provider slot, positions every provider one payout below a full Society unit, and executes a held checkout through the deployed Base router. It asserts one DN404 mint per provider, exact position and inventory preservation, cleared checkout balances/allowance, and configured gas headroom.
- `UniversalPoolArtMarketplaceForkBaseTest::testBenchmarkLatestBaseFreeExitTraversesFull888IdScan` derives a `prevrandao` fixture whose bounded scan begins immediately after the only market-owned ID, forcing all 888 ownership probes before the free exit succeeds. It asserts the selected ID and configured gas headroom.

## Command

Load public configuration first, then obtain the Base RPC from Doppler without printing it:

```sh
set -a
source config/fame-public.env
set +a
doppler run --config prd -- sh -c 'BASE_RPC="$RPC_URL" forge test --isolate --match-test "testBenchmarkLatestBase(CandidateCapCheckoutMintsForEveryProviderPayout|FreeExitTraversesFull888IdScan)" -vv'
```

`--isolate` is mandatory. It executes top-level calls in separate EVM transaction contexts so fixture accesses do not warm the measured checkout or free-exit storage paths.

Record the UTC timestamp, Base block number/hash emitted by each test, candidate cap, both gas measurements, configured budgets, block gas limit, and pass/fail result. A skipped test or unavailable RPC is `not executed`, not a passing gate.

## Release decision

If either lane fails, reduce the candidate cap or revise the inventory-selection design and rerun both lanes. Only after both pass may `BASE_UNIVERSAL_MARKETPLACE_ACTIVE_PROVIDER_CAP` be set to the candidate and the deploy/validate/activation/handoff rehearsal proceed.

## Recorded passing run

- UTC: `2026-08-02T18:30:59Z`
- Base block: `49453056`
- Base block hash: `0x6d27e1db6da96842bdbb0230ee9bb9be7fbaee9d6f74aec1729fa6504264b099`
- Candidate active-provider cap: `16`
- All-provider auto-mint checkout: `1,492,118` gas against a `15,000,000` gas budget
- Full 888-ID free exit: `2,805,973` gas against a `10,000,000` gas budget
- Base block gas limit: `400,000,000`
- Result: both isolated benchmark lanes passed. Candidate `16` was qualified but later superseded by the passing `88`-provider qualification run.

## Recorded 88-provider qualification run

- UTC: `2026-08-02T19:02:49Z`
- Base block: `49454011`
- Base block hash: `0x26866564b0d20bbf92bf6f318e94da65c2499d0211d33665b0ebccf46220ec06`
- Candidate active-provider cap: `88`
- All-provider auto-mint checkout: `3,790,891` gas against a `15,000,000` gas budget
- Full 888-ID free exit: `2,805,973` gas against a `10,000,000` gas budget
- Base per-transaction gas maximum: `16,777,216`
- Base block gas limit: `400,000,000`
- Result: both isolated benchmark lanes passed with candidate `88` loaded directly from public configuration. It is qualified by the required Base gas gate and selected as the fixed production cap.

## Post-batch-bytecode requalification

The immutable marketplace bytecode changed when the bounded provider batch
entrypoint was added, so both mandatory lanes were rerun rather than inheriting
the earlier qualification:

- UTC: `2026-08-03T00:44:15Z`
- Base block: `49464230`
- Base block hash: `0xcf6a0ae219eb7f0f41d082b257e9e01f41e37dcef49c93ae167296339d56a0e6`
- Candidate active-provider cap: `88`
- All-provider auto-mint checkout: `3,790,903` gas against a `15,000,000` gas budget
- Full 888-ID free exit: `2,805,985` gas against a `10,000,000` gas budget
- Base block gas limit: `400,000,000`
- Result: both isolated benchmark lanes passed against the changed bytecode.
  The release lifecycle independently credited one maximum eight-token batch,
  validated, activated, re-paused, handed ownership to the Safe, and validated
  the post-handoff state on the same latest-Base release run.
