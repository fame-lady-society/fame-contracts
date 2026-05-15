# FAME RELEASE PLAN

## Environment Model

Use a small public config file plus Doppler secrets. Public addresses and chain IDs live in `config/fame-public.env`; RPC URLs, private keys, mnemonics, explorer API keys, upload keys, and snipe keys live in Doppler.

Load public config once in any shell that will run deployment or validation commands:

```sh
set -a
source config/fame-public.env
set +a
```

Then run commands that need secrets with `doppler run -- ...`. Foundry RPC aliases are configured in `foundry.toml`, so prefer `--rpc-url base`, `--rpc-url base_sepolia`, and `--rpc-url sepolia`.

If a command passes a secret as a CLI argument, expand it inside the Doppler process:

```sh
doppler run -- sh -c 'cast wallet address --private-key "$BASE_DEPLOYER_PRIVATE_KEY"'
```

Expected Doppler secrets:

- RPC and explorer: `BASE_RPC`, `BASE_SEPOLIA_RPC`, `SEPOLIA_RPC`, `BASE_ETHERSCAN_API_KEY`, `ETHERSCAN_API_KEY`, and optional `MAINNET_RPC_URL`.
- Deploy/sign: `BASE_DEPLOYER_PRIVATE_KEY`, `BASE_SEPOLIA_DEPLOYER_PRIVATE_KEY`, `SEPOLIA_DEPLOYER_PRIVATE_KEY`, `DEPLOYER_PRIVATE_KEY`, `SIGNER_PRIVATE_KEY`, and any chain-specific signer aliases used by older scripts.
- Safe and one-off workflows: `BASE_MNEMONIC`, `SEPOLIA_MNEMONIC`, `MNEMONIC`, `SNIPE_PRIVATE_KEY`, `SEPOLIA_SNIPE_PRIVATE_KEY`, `ARWEAVE_PRIVATE_KEY`, and `MULTISIG_PRIVATE_KEY`.

`BASE_SEPOLIA_FAME_ADDRESS` is intentionally not set in `config/fame-public.env` yet because the previous local `.env` value had a trailing `.` and is not a valid address. Fill it in after confirming the deployed Base Sepolia FAME token.

## Presale

### Sepolia

```
doppler run -- forge script --chain sepolia script/DeployPresale.sol:DeployPresale --verify --broadcast --rpc-url sepolia
```

## FAME

### Sepolia

Load `config/fame-public.env` for public addresses and use Doppler for `SEPOLIA_RPC`, `ETHERSCAN_API_KEY`, `SEPOLIA_DEPLOYER_PRIVATE_KEY`, and signer keys.

If you want to obtain the CA before deploying:

In one terminal:

```
doppler run -- anvil --fork-url sepolia --block-time 2
```

In another terminal:

```
doppler run -- forge script --chain sepolia script/SepoliaDeployLaunch.sol:DeployLaunch --broadcast --rpc-url http://localhost:8545
```

Note the FAME token address (it will be the first contract deployed)

```
export FAME_ADDRESS=0...
```

Stop the anvil server and get ready to do it for real.

Some useful variables for up ahead:
```
export FAME_ADDRESS=0x...
export WETH_ADDRESS=$SEPOLIA_WETH_ADDRESS
export SWAP_ROUTER=$SEPOLIA_SWAP_ROUTER
export RPC=sepolia
export MULTISIG_ADDRESS=$SEPOLIA_MULTISIG_ADDRESS
```

Now launch the token for the society

```
doppler run -- forge script --chain sepolia script/SepoliaDeployLaunch.sol:DeployLaunch --verify --broadcast --rpc-url $RPC
```

Now do a public launch

```
doppler run -- forge script script/SepoliaPostLaunchAirdrop.sol:DeployLaunch --broadcast --verify --rpc-url $RPC
```

## Base

```
export CHAIN=base
export RPC=base
export SWAP_ROUTER=$BASE_SWAP_ROUTER
export WETH_ADDRESS=$BASE_WETH_ADDRESS
export MULTISIG_ADDRESS=$BASE_MULTISIG_ADDRESS
```

### FAME Router

Router deployment is gated by `docs/router/fame-router-validation.md`. Do not transfer ownership to the Base multisig until pinned fork fixture coverage, fresh Base validation, deployed `getSkipNFT(router) == true`, and `www` schema parity all pass. Public router constants live in `config/fame-public.env`; set `BASE_FAME_ROUTER_ADDRESS` there after deployment. The validation script checks router config, manifest-required venue enablement, current Base pool metadata, skip-NFT, schema version, fixture snapshot hash, and manifest launchability.

```
doppler run -- forge test --match-path test/router/FameRouter.t.sol
doppler run -- forge test --match-path test/router/FameRouterDeploymentValidation.t.sol
doppler run -- forge script --chain base script/DeployFameRouter.s.sol:DeployFameRouter --verify --broadcast --rpc-url base
doppler run -- forge script --chain base script/ValidateFameRouterBase.s.sol:ValidateFameRouterBase --rpc-url base
```

```
doppler run -- anvil --fork-url base --block-time 2
```

## Fair Reveal

deploy:

```
doppler run -- sh -c 'forge create "src/FairReveal.sol:FairReveal" --rpc-url "$RPC" --private-key "$DEPLOYER_PRIVATE_KEY" --verify --etherscan-api-key "$ETHERSCAN_API_KEY" --constructor-args "$FAME_ADDRESS" https://www.fameladysociety.com/fame/metadata/ 888'
```

Now, put all of the art into a single folder `.metadata/incoming'. If the art is just an image, put it as-is into the folder. If the token has an image and an animation_url that is an ".mp4" file, then put those 2 files into a directory inside this folder. The names of the files does not matter, they will all be renamed to a hash.

```
yarn nodets js/metadata/nameFiles.ts .metadata/incoming .metadata/staging/
```

There should be a folder full of images and folders named very long numbers at .metadata/staging

Upload these to ARWEAVE

```
doppler run -- bash -c 'export ARWEAVE_NETWORK=mainnet ARWEAVE_TOKEN=base-eth ARWEAVE_PRIVATE_KEY=$BASE_DEPLOYER_PRIVATE_KEY ARWEAVE_RPC=$BASE_RPC; yarn nodets js/metadata/upload.ts'
```

The cost estimate doesn't really work for folders, you may need to run it a couple of times to have enough funds for the upload

Generate metadata for these assets

```
yarn nodets js/metadata/generateMetadata.ts --salt 0
```

Upload that

```
yarn nodets js/metadata/upload.ts .metadata/staging-metadata/
```

Check the `.metadata/staging-metadata-id.txt` for the `id`

Use that generate the base URL: `https://gateway.irys.xyz/{id}/`

Get the FairReveal contract address and update the FAME renderer

```
doppler run -- sh -c 'cast send --rpc-url "$RPC" --private-key "$DEPLOYER_PRIVATE_KEY" "$FAME_ADDRESS" "$(cast calldata "setRenderer(address)" "$FAIR_REVEAL_ADDRESS")"'
```

And now run the reveal:

```
export BASE_URI="https://gateway.irys.xyz/${ARWEAVE_ID}/"
export TOTAL_AVAILABLE_ART=333
export REVEAL_AMOUNT=264
export SALT=0
doppler run -- sh -c 'cast send --rpc-url "$RPC" --private-key "$DEPLOYER_PRIVATE_KEY" "$FAIR_REVEAL_ADDRESS" "$(cast calldata "reveal(string,uint256,uint16,uint16)" "$BASE_URI" "$SALT" "$REVEAL_AMOUNT" "$TOTAL_AVAILABLE_ART")"'
```

## Batch Reveal

The batch reveal was built to replace the on-chain reveal after an issue with one token causing a revert on read due to out of gas.

unzip the new files to a folder

```
export BATCH_RELEASE_DATE=YYYY-MM-DD
unzip $BATCH_RELEASE_DATE.zip -d .metadata/$BATCH_RELEASE_DATE
```

prepare environment

```
export ARWEAVE_NETWORK=mainnet
export ARWEAVE_TOKEN=base-eth
export ARWEAVE_RPC=base
```

Name the image files.

```
yarn nodets js/metadata/nameFiles.ts .metadata/$BATCH_RELEASE_DATE .metadata/$BATCH_RELEASE_DATE-images
```

Upload the files to arweave

```
yarn nodets js/metadata/upload.ts .metadata/$BATCH_RELEASE_DATE-images
```

Generate metadata for these assets

Before generating metadata, pick a number (any positive integer). This is the salt.

```
export SALT=0
```

```
yarn nodets js/metadata/generateMetadata.ts --salt $SALT .metadata/$BATCH_RELEASE_DATE-images-manifest.json .metadata/$BATCH_RELEASE_DATE-images-id.txt .metadata/$BATCH_RELEASE_DATE-metadata
```

Upload that

```
yarn nodets js/metadata/upload.ts .metadata/$BATCH_RELEASE_DATE-metadata
```

Now get the transaction id from the upload

```
export ARWEAVE_TRANSACTION_ID=$(cat .metadata/$BATCH_RELEASE_DATE-metadata-id.txt | jq -r .id)
export METADATA_BASE_URI="https://gateway.irys.xyz/${ARWEAVE_TRANSACTION_ID}/"
echo $METADATA_BASE_URI
```

Now Deploy the batch reveal

```
export RPC=base
export BATCH_SIZE=$(cat .metadata/$BATCH_RELEASE_DATE-metadata-manifest.json | jq -r '.paths | length')
doppler run -- sh -c 'cast send --rpc-url "$RPC" --private-key "$BASE_DEPLOYER_PRIVATE_KEY" --etherscan-api-key "$BASE_ETHERSCAN_API_KEY" 0xa50c9a918c110ca159fb187f4a55896a4d063878 "pushBatch(uint256,uint256,string)" "$SALT" "$BATCH_SIZE" "$METADATA_BASE_URI"'
```

## Vesting

deploy:

```

doppler run -- sh -c 'forge create "src/FameVesting.sol:FameVesting" --rpc-url "$RPC" --private-key "$DEPLOYER_PRIVATE_KEY" --etherscan-api-key "$BASE_ETHERSCAN_API_KEY" --verify --constructor-args "$FAME_ADDRESS"'

```

get the fame vesting contract address and set

```

export FAME_VESTING_CONTRACT_ADDRESS=0x....

```

allow the multisig to create vesting schedule

```

export RPC=base
export MULTISIG_ADDRESS=$BASE_MULTISIG_ADDRESS
doppler run -- sh -c 'cast send --rpc-url "$RPC" --private-key "$BASE_DEPLOYER_PRIVATE_KEY" "$FAME_VESTING_ADDRESS" "$(cast calldata "transferOwnership(address)" "$MULTISIG_ADDRESS")"'

```

Now run this script to generate and submit the multisig transaction to run the presale cliff airdrop and the liner vesting:

```

export FAME_ADDRESS=$BASE_FAME_ADDRESS
export MULTISIG_RPC=base
export CLAIM_TO_FAME_ADDRESS=$BASE_CLAIM_TO_FAME_ADDRESS
export MULTISIG_CHAIN_ID=8453
doppler run -- yarn nodets js/presale/generate-vesting-transactions.ts

```

# Governance

## Sepolia

### GovSociety

Set the Manager Address

```
export MULTISIG_ADDRESS=$SEPOLIA_MULTISIG_ADDRESS
export RPC=sepolia
export FAME_NFT_ADDRESS=$SEPOLIA_FAME_NFT_ADDRESS
export FAME_ADDRESS=$SEPOLIA_FAME_ADDRESS
export RENDERER_ADDRESS=$(doppler run -- cast call $FAME_ADDRESS "renderer()(address)" --rpc-url $RPC)
```

These commands use the custom verifier URL because some Forge versions do not handle the recent explorer API changes cleanly.

Deploy the GovSociety

```
export GOV_SOCIETY_ADDRESS=$(doppler run -- sh -c 'forge create --broadcast --json --verify --verifier-api-key "$ETHERSCAN_API_KEY" --verifier custom --verifier-url https://api-sepolia.etherscan.io/api src/GovSociety.sol:GovSociety --rpc-url "$RPC" --private-key "$SEPOLIA_DEPLOYER_PRIVATE_KEY" --constructor-args "$FAME_NFT_ADDRESS" "$MULTISIG_ADDRESS" "$RENDERER_ADDRESS"' | jq -r .deployedTo)
echo Deployed GovSociety to $GOV_SOCIETY_ADDRESS
```

### FAMEusTimelockController

```
export TIMELOCK_DELAY=$((60 * 60 * 24))
export CANCELLER=$MULTISIG_ADDRESS
export VOTING_DELAY=$((60 * 60 * 24))
export VOTING_PERIOD=$((60 * 60 * 24 * 3))
export PROPOSAL_THRESHOLD=8
export FAMEUS_TIMELOCK_CONTROLLER_ADDRESS=`doppler run -- sh -c 'forge create --broadcast --json --verify --verifier-api-key "$ETHERSCAN_API_KEY" --verifier custom --verifier-url https://api-sepolia.etherscan.io/api src/FameusTimelockController.sol:FAMEusTimelockController --rpc-url "$RPC" --private-key "$SEPOLIA_DEPLOYER_PRIVATE_KEY" --constructor-args "$GOV_SOCIETY_ADDRESS" "$TIMELOCK_DELAY" "$CANCELLER" "$VOTING_DELAY" "$VOTING_PERIOD" "$PROPOSAL_THRESHOLD"' | jq -r .deployedTo`
echo Deployed FAMEusGovernor to $FAMEUS_TIMELOCK_CONTROLLER_ADDRESS
export FAMEUS_GOVERNOR=$(cast call $FAMEUS_TIMELOCK_CONTROLLER_ADDRESS "governor()(address)")
echo Deployed FAMEusGovernor to $FAMEUS_GOVERNOR
```

```
doppler run -- sh -c 'forge verify-contract "$FAMEUS_GOVERNOR" src/FameusGovernor.sol:FAMEusGovernor --verifier-api-key "$ETHERSCAN_API_KEY" --verifier custom --verifier-url https://api-sepolia.etherscan.io/api --constructor-args "$(cast abi-encode "constructor(address,address,uint48,uint32,uint256)" "$GOV_SOCIETY_ADDRESS" "$FAMEUS_TIMELOCK_CONTROLLER_ADDRESS" "$VOTING_DELAY" "$VOTING_PERIOD" "$PROPOSAL_THRESHOLD")"'
```

## Base

### GovSociety

Set the Manager Address

```
export MULTISIG_ADDRESS=$BASE_MULTISIG_ADDRESS
export RPC=base
export FAME_NFT_ADDRESS=$BASE_FAME_NFT_ADDRESS
export FAME_ADDRESS=$BASE_FAME_ADDRESS
export RENDERER_ADDRESS=$(doppler run -- cast call $FAME_ADDRESS "renderer()(address)" --rpc-url $RPC)
```

Verify that all of these variable have been set:

```
#!/bin/bash

# Array of required environment variables
required_vars=(
    "MULTISIG_ADDRESS"
    "RPC"
    "BASE_DEPLOYER_PRIVATE_KEY"
    "FAME_NFT_ADDRESS"
    "FAME_ADDRESS"
    "BASE_ETHERSCAN_API_KEY"
    "RENDERER_ADDRESS"
)

# Flag to track if any variables are missing
missing_vars=0

# Check each variable
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "❌ Error: $var is not set or empty"
        missing_vars=1
    else
        echo "✅ $var is set"
    fi
done

# Exit with error if any variables are missing
if [ $missing_vars -eq 1 ]; then
    echo -e "\n❌ Some required environment variables are missing!"
    exit 1
else
    echo -e "\n✅ All required environment variables are set!"
fi
```

These commands use the custom verifier URL because some Forge versions do not handle the recent explorer API changes cleanly.

Deploy the GovSociety

```
export GOV_SOCIETY_ADDRESS=$(doppler run -- sh -c 'forge create --broadcast --json --verify --verifier-api-key "$BASE_ETHERSCAN_API_KEY" --verifier custom --verifier-url https://api.basescan.org/api src/GovSociety.sol:GovSociety --rpc-url "$RPC" --private-key "$BASE_DEPLOYER_PRIVATE_KEY" --constructor-args "$FAME_NFT_ADDRESS" "$MULTISIG_ADDRESS" "$RENDERER_ADDRESS"' | jq -r .deployedTo)
echo Deployed GovSociety to $GOV_SOCIETY_ADDRESS
```

In case GovSociety verification fails, run this:

```
doppler run -- sh -c 'forge verify-contract "$GOV_SOCIETY_ADDRESS" src/GovSociety.sol:GovSociety --verifier-api-key "$BASE_ETHERSCAN_API_KEY" --verifier custom --verifier-url https://api.basescan.org/api --constructor-args "$(cast abi-encode "constructor(address,address,address)" "$FAME_NFT_ADDRESS" "$MULTISIG_ADDRESS" "$RENDERER_ADDRESS")"'
```

### FAMEusTimelockController

```
export TIMELOCK_DELAY=$((1 * 60 * 60 * 24))
export CANCELLER=$MULTISIG_ADDRESS
export VOTING_DELAY=$((1 * 60 * 60 * 24))
export VOTING_PERIOD=$((3 * 60 * 60 * 24 * 3))
export PROPOSAL_THRESHOLD=8
export FAMEUS_TIMELOCK_CONTROLLER_ADDRESS=`doppler run -- sh -c 'forge create --broadcast --json --verify --verifier-api-key "$BASE_ETHERSCAN_API_KEY" --verifier custom --verifier-url https://api.basescan.org/api src/FameusTimelockController.sol:FAMEusTimelockController --rpc-url "$RPC" --private-key "$BASE_DEPLOYER_PRIVATE_KEY" --constructor-args "$GOV_SOCIETY_ADDRESS" "$TIMELOCK_DELAY" "$CANCELLER" "$VOTING_DELAY" "$VOTING_PERIOD" "$PROPOSAL_THRESHOLD"' | jq -r .deployedTo`
echo Deployed FAMEusTimelockController to $FAMEUS_TIMELOCK_CONTROLLER_ADDRESS
export FAMEUS_GOVERNOR=$(cast call --rpc-url $RPC $FAMEUS_TIMELOCK_CONTROLLER_ADDRESS "governor()(address)")
echo Deployed FAMEusGovernor to $FAMEUS_GOVERNOR
```

If the verification fails, run this:

```
doppler run -- sh -c 'forge verify-contract "$FAMEUS_TIMELOCK_CONTROLLER_ADDRESS" src/FameusTimelockController.sol:FAMEusTimelockController --verifier-api-key "$BASE_ETHERSCAN_API_KEY" --verifier custom --verifier-url https://api.basescan.org/api --constructor-args "$(cast abi-encode "constructor(address,uint256,address,int48,uint32,uint256)" "$GOV_SOCIETY_ADDRESS" "$TIMELOCK_DELAY" "$CANCELLER" "$VOTING_DELAY" "$VOTING_PERIOD" "$PROPOSAL_THRESHOLD")"'
```

And you will always need to verify the governor, since it was created within the timelock controller:

```
doppler run -- sh -c 'forge verify-contract "$FAMEUS_GOVERNOR" src/FameusGovernor.sol:FAMEusGovernor --verifier-api-key "$BASE_ETHERSCAN_API_KEY" --verifier custom --verifier-url https://api.basescan.org/api --constructor-args "$(cast abi-encode "constructor(address,address,uint48,uint32,uint256)" "$GOV_SOCIETY_ADDRESS" "$FAMEUS_TIMELOCK_CONTROLLER_ADDRESS" "$VOTING_DELAY" "$VOTING_PERIOD" "$PROPOSAL_THRESHOLD")"'
```
