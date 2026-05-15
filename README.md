# FAME Contracts

Smart contracts, deployment scripts, and release notes for FAME.

## Environment

Public addresses live in `config/fame-public.env`. Secrets live in Doppler.

Before running scripts that need deployed addresses:

```sh
set -a
source config/fame-public.env
set +a
```

Run commands that need RPC URLs, explorer keys, private keys, mnemonics, upload keys, or snipe keys through Doppler:

```sh
doppler setup
doppler run -- forge test
```

Foundry chain aliases are configured in `foundry.toml`, so prefer `--rpc-url base`, `--rpc-url base_sepolia`, or `--rpc-url sepolia` over raw RPC URLs. The expected Doppler secrets are:

- `BASE_RPC`, `BASE_SEPOLIA_RPC`, `SEPOLIA_RPC`, and optional `MAINNET_RPC_URL`
- `BASE_ETHERSCAN_API_KEY` and `ETHERSCAN_API_KEY`
- deployer/signer keys such as `BASE_DEPLOYER_PRIVATE_KEY`, `BASE_SEPOLIA_DEPLOYER_PRIVATE_KEY`, `SEPOLIA_DEPLOYER_PRIVATE_KEY`, `DEPLOYER_PRIVATE_KEY`, and `SIGNER_PRIVATE_KEY`
- workflow-specific secrets such as `BASE_MNEMONIC`, `SEPOLIA_MNEMONIC`, `MNEMONIC`, `SNIPE_PRIVATE_KEY`, `SEPOLIA_SNIPE_PRIVATE_KEY`, `ARWEAVE_PRIVATE_KEY`, and `MULTISIG_PRIVATE_KEY`

If a value is a public contract address, add it to `config/fame-public.env` instead of Doppler.

When a command passes a secret as a CLI argument, expand it inside Doppler:

```sh
doppler run -- sh -c 'cast wallet address --private-key "$BASE_DEPLOYER_PRIVATE_KEY"'
```

## Documentation

- [Foundry Book](https://book.getfoundry.sh/)
- [FAME Release Plan](./docs/fame-release-plan.md)

## Usage

### Build

```shell
forge build
```

### Test

Unit tests:

```shell
forge test
```

Fork tests require Doppler-provided RPC secrets:

```shell
doppler run -- forge test --fork-url sepolia --fork-block-number 5937091
```

### Format

```shell
forge fmt
```

### Gas Snapshots

```shell
forge snapshot
```

### Anvil

```shell
anvil
```

### Deploy

Load public config once per shell, then let Doppler provide secrets:

```shell
set -a
source config/fame-public.env
set +a
doppler run -- forge script --chain base script/DeployFameRouter.s.sol:DeployFameRouter --verify --broadcast --rpc-url base
```

### Cast

```shell
cast <subcommand>
```

### Help

```shell
forge --help
anvil --help
cast --help
```
