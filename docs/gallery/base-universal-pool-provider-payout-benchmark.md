# Base Society provider-cap benchmark

The production active-provider cap in `config/fame-public.env` is `88`, selected from the passing latest-head Base qualification run recorded below. Rerun the payout lane before deployment if the implementation, configured fees, live FAME stack, or intended release head changes materially.

## Required lane

- `FameMarketplaceCheckoutForkBaseTest::testBenchmarkLatestBaseCandidateCapCheckoutMintsForEveryProviderPayout` deploys the candidate-cap marketplace against the live FAME/CreatorMagic stack, fills every provider slot, positions every provider one payout below a full Society unit, and executes a held checkout through the deployed Base router. It asserts one DN404 mint per provider, exact position and inventory preservation, cleared checkout balances/allowance, and configured gas headroom.

Provider withdrawal is an explicit `withdrawInventory(tokenId, maxPremium)`
claim with timestamped 24-hour premium decay. It has no inventory scan and no
separate withdrawal gas release gate.

## Command

Load public configuration first, then obtain the Base RPC from Doppler without printing it:

```sh
set -a
source config/fame-public.env
set +a
doppler run --config prd -- sh -c 'BASE_RPC="$RPC_URL" forge test --isolate --match-test "testBenchmarkLatestBaseCandidateCapCheckoutMintsForEveryProviderPayout" -vv'
```

`--isolate` is mandatory. It executes top-level calls in separate EVM transaction contexts so fixture accesses do not warm the measured checkout storage paths.

Record the UTC timestamp, Base block number/hash emitted by the test, candidate cap, checkout gas measurement, configured budget, block gas limit, and pass/fail result. A skipped test or unavailable RPC is `not executed`, not a passing gate.

## Release decision

If the lane fails, reduce the candidate cap or revise payout distribution and rerun it. Only after it passes may `BASE_UNIVERSAL_MARKETPLACE_ACTIVE_PROVIDER_CAP` be set to the candidate and the deploy/validate/activation/handoff rehearsal proceed.

## Recorded passing run

- UTC: `2026-08-02T18:30:59Z`
- Base block: `49453056`
- Base block hash: `0x6d27e1db6da96842bdbb0230ee9bb9be7fbaee9d6f74aec1729fa6504264b099`
- Candidate active-provider cap: `16`
- All-provider auto-mint checkout: `1,492,118` gas against a `15,000,000` gas budget
- Base block gas limit: `400,000,000`
- Result: the isolated payout benchmark passed. Candidate `16` was qualified but later superseded by the passing `88`-provider qualification run.

## Recorded 88-provider qualification run

- UTC: `2026-08-02T19:02:49Z`
- Base block: `49454011`
- Base block hash: `0x26866564b0d20bbf92bf6f318e94da65c2499d0211d33665b0ebccf46220ec06`
- Candidate active-provider cap: `88`
- All-provider auto-mint checkout: `3,790,891` gas against a `15,000,000` gas budget
- Base per-transaction gas maximum: `16,777,216`
- Base block gas limit: `400,000,000`
- Result: the isolated payout benchmark passed with candidate `88` loaded directly from public configuration. It is qualified by the required Base payout gas gate and selected as the fixed production cap.

## Post-batch-bytecode requalification

The immutable marketplace bytecode changed when the bounded provider batch
entrypoint was added, so the mandatory payout lane was rerun rather than inheriting
the earlier qualification:

- UTC: `2026-08-03T00:44:15Z`
- Base block: `49464230`
- Base block hash: `0xcf6a0ae219eb7f0f41d082b257e9e01f41e37dcef49c93ae167296339d56a0e6`
- Candidate active-provider cap: `88`
- All-provider auto-mint checkout: `3,790,903` gas against a `15,000,000` gas budget
- Base block gas limit: `400,000,000`
- Result: the isolated payout benchmark passed against the changed bytecode.
  The release lifecycle at that point still used pre-activation inventory and
  was superseded by the release-lifecycle rehearsal below.

## Post-release-lifecycle requalification

The provider bytecode did not change for the release-lifecycle update, but the
complete latest-Base release suite was rerun so the cap benchmarks and the
new lifecycle share current fork evidence:

- UTC: `2026-08-03T19:26Z`
- Base benchmark block: `49497889`
- Base benchmark block hash: `0xcf32e4f4ea7e9f7d26ab531f21e8fb4463e3479f1e77f0a83c94c6f95ff9048b`
- Deployer-owned lifecycle block: `49497895`
- Deployer-owned lifecycle block hash: `0xbc1e27dc636377937a317b85a0a0e7aa1e30c93a547123ead56085f0968675a9`
- Candidate active-provider cap: `88`
- All-provider auto-mint checkout: `3,790,903` gas against a `15,000,000` gas budget
- Base block gas limit: `400,000,000`
- Result: the recorded release suite passed. The lifecycle deployed and
  validated the fresh deployment's observed empty state, activated from the
  deployer, rejected checkout while empty before buyer funding, accepted an
  eight-token credited provider batch, and completed a real configured
  checkout. Empty state was observed in this run, not qualified as a release
  requirement. No fork ownership transfer occurred.
