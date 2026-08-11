# FAME Contracts

Smart contracts and migration infrastructure for Fame Lady Society, including FAME token/NFT systems, wrapping and remapping flows, metadata/rendering contracts, airdrop and vesting tooling, DAO/governance contracts, launch scripts, and the FAME swap router.

This repository is technical infrastructure for a public onchain community project. It is not a marketing site and it does not include private deployment keys or unpublished operational material.

## What This Solves

Fame Lady Society needed contract infrastructure for a messy real-world onchain lifecycle: preserving community identity, supporting migration/wrapping paths, distributing assets, generating metadata, coordinating launch mechanics, and giving users routeable liquidity paths across Base venues.

The repo covers that work as deployable Solidity contracts plus Foundry tests, deployment scripts, public address config, generated router fixtures, and TypeScript tooling.

## Contract Architecture

Major areas in the source tree:

- **FAME token and mirror systems** - `Fame.sol`, `FameMirror.sol`, DN404-related contracts, and launch helpers.
- **Wrapping/remapping and migration** - `ClaimToFame.sol`, `FameSquadRemapper.sol`, `FameSale.sol`, `FameSaleToken.sol`, and holder/migration scripts.
- **Metadata and rendering** - `FameRenderer.sol`, `SimpleOffchainReveal.sol`, `FAMEusMagazineReissue.sol`, presale renderers, JS metadata generation/upload utilities, and art patcher contracts.
- **Airdrops and vesting** - `AirdropHelper.sol`, post-launch airdrop scripts, `FameVesting.sol`, and presale/vesting transaction tooling.
- **DAO/governance** - `FameusGovernor.sol`, `FameusGovernorQuorum.sol`, `FameusTimelockController.sol`, and `GovSociety.sol`.
- **FAME router** - `FameRouter.sol`, typed route schema, venue adapters, generated route fixtures, pinned-fork tests, and Base deployment/validation scripts.

### CreatorArtistMagic pool classification

`CreatorArtistMagic` deliberately retains V2's live-supply classifier. The Burn Pool is an unowned token at or below `FAME.totalNFTSupply()`, and the Mint Pool is an unowned token above that live supply but below `nextTokenId`; both exclude the Art Pool.

`nextTokenId` is a metadata release cursor, not an ownership boundary. `releaseArtwork` may assign new metadata when that Society token has already been minted and is owned; it leaves ownership unchanged and advances the release cursor exactly once.

This is a best-effort classification, not an exact historical mint ledger. It automatically advances when DN404 creates fresh sequential NFT IDs, but `totalNFTSupply()` can move backward after burns. Until those burned IDs are reminted, a historically minted high ID can therefore appear in the Mint Pool. The deployed FAME contract does not expose DN404's private historical next-ID frontier, so `CreatorArtistMagic` cannot make both behaviors exact by reading FAME.

Do not replace this with a migration-time constant such as `592`. A frozen frontier fixes one observed burn state but becomes stale as soon as fresh IDs mint. Marketplace and web clients should use the contract's `isTokenInBurnedPool`, `isTokenInMintPool`, and `getMintPoolStart` views at a consistent block rather than reconstructing or caching a permanent boundary. See [the pool-classification decision note](docs/solutions/architecture-patterns/creator-artist-magic-best-effort-pool-classification.md).

## Router and Liquidity Tooling

The FAME router accepts schema-versioned exact-input routes and enforces custody, minimum-output, fee, settlement, venue-family, and venue-target rules onchain. The route-discovery and quote-quality work remains offchain.

Relevant docs:

- [Router schema](docs/router/fame-router-schema.md)
- [Router validation and launch gate](docs/router/fame-router-validation.md)
- [TypeScript router package](router-ts/README.md)

The checked-in tests include unit coverage, generated artifact checks, and pinned Base fork tests for configured venue families and targets.

## Public Configuration and Deployments

Public contract addresses and non-secret settings live in [`config/fame-public.env`](config/fame-public.env). Secrets such as RPC URLs, deployer keys, explorer keys, mnemonics, upload keys, and private signing keys are expected to come from Doppler or another secret manager and are not stored in this repository.

Foundry chain aliases are configured in [`foundry.toml`](foundry.toml), so commands prefer `--rpc-url base`, `--rpc-url base_sepolia`, or `--rpc-url sepolia` over raw private RPC URLs.

## Development

Load public config when scripts need public addresses:

```sh
set -a
source config/fame-public.env
set +a
```

Run commands that require secrets through Doppler:

```sh
doppler setup
doppler run -- forge test
```

Common commands:

```sh
forge build
forge test
forge fmt
forge snapshot
```

Router package checks:

```sh
bun run router:generate:check
bun run router:typecheck
bun run router:test
bun run router:verify
```

Deploy the router with public config and Doppler-provided secrets:

```sh
set -a
source config/fame-public.env
set +a
doppler run -- forge script --chain base script/DeployFameRouter.s.sol:DeployFameRouter --verify --broadcast --rpc-url base
```

## Security Assumptions and Risks

- Public addresses belong in `config/fame-public.env`; private keys, RPC credentials, explorer keys, mnemonics, upload keys, and signing keys do not.
- Router route quality is intentionally offchain; the contract validates schema, custody, enabled venues/targets, settlement, fees, and minimum output.
- Fork tests and generated fixtures are evidence for specific pinned states, not permanent claims about external liquidity venues.
- Deployment scripts can broadcast irreversible transactions; inspect target chain, public config, and signer before use.
- CreatorArtistMagic's V2-compatible Mint/Burn split is intentionally best-effort because deployed FAME exposes live supply, not its historical DN404 next-ID frontier.
- No audit claim is made by this README.

## Maintenance Status

The repository contains both historical Fame Lady Society contract work and actively maintained FAME router work. The README avoids implying every contract here is currently deployed or actively changed; check scripts, public config, release docs, and recent commits for the current operational path.

## Documentation

- [FAME release plan](docs/fame-release-plan.md)
- [Router schema](docs/router/fame-router-schema.md)
- [Router validation](docs/router/fame-router-validation.md)
- [Foundry Book](https://book.getfoundry.sh/)
