# FAME RELEASE PLAN

## Presale

### Sepolia

```
source.env
forge script --chain sepolia script/DeployPresale.sol:DeployPresale --verify --broadcast --rpc-url $SEPOLIA_RPC
```

## FAME

### Sepolia

you'll need an .env file with the following:

```
SEPOLIA_WETH_ADDRESS=0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9
SEPOLIA_SWAP_ROUTER=0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E
ETHERSCAN_API_KEY=
SEPOLIA_RPC=
SEPOLIA_DEPLOYER_PRIVATE_KEY=
```

If you want to obtain the CA before deploying:

In one terminal:

```

source .env
anvil --fork-url $SEPOLIA_RPC --block-time 2

```

In another terminal:

```
source .env
DEPLOYER_PRIVATE_KEY=$SEPOLIA_DEPLOYER_PRIVATE_KEY SIGNER_PRIVATE_KEY=$SEPOLIA_SIGNER_PRIVATE_KEY forge script --chain sepolia script/SepoliaDeployLaunch.sol:DeployLaunch --broadcast --rpc-url http://localhost:8545

```

Note the FAME token address (it will be the first contract deployed)

```
export FAME_ADDRESS=0...

Stop the anvil server and get ready to do it for real.

Some useful variables for up ahead:
```

source .env
export FAME_ADDRESS=0x...
export WETH_ADDRESS=$SEPOLIA_WETH_ADDRESS
export SWAP_ROUTER=$SEPOLIA_SWAP_ROUTER
export RPC=$SEPOLIA_RPC
export MULTISIG_ADDRESS=$SEPOLIA_MULTISIG_ADDRESS

Now launch the token for the society

```
forge script --chain sepolia script/DeployLaunchSepolia.sol:DeployLaunch --verify --broadcast --rpc-url $RPC
```

Now do a public launch

```
DEPLOYER_PRIVATE_KEY=$SEPOLIA_DEPLOYER_PRIVATE_KEY SIGNER_PRIVATE_KEY=$SEPOLIA_SIGNER_PRIVATE_KEY forge script script/SepoliaPostLaunchAirdrop.sol:DeployLaunch --broadcast --verify --rpc-url $RPC
```

## Base

```
source .env
export CHAIN=base
export RPC=$BASE_RPC
export SWAP_ROUTER=$BASE_SWAP_ROUTER
export WETH_ADDRESS=$BASE_WETH_ADDRESS
export MULTISIG_ADDRESS=$BASE_MULTISIG_ADDRESS
export SIGNER_PRIVATE_KEY=$BASE_SIGNER_PRIVATE_KEY
export DEPLOYER_PRIVATE_KEY=$BASE_DEPLOYER_PRIVATE_KEY
```

```
anvil --fork-url $RPC --block-time 2
```

## Fair Reveal

deploy:

```
forge create "src/FairReveal.sol:FairReveal" --rpc-url $RPC --private-key $DEPLOYER_PRIVATE_KEY --verify --etherscan-api-key $ETHERSCAN_API_KEY --constructor-args $FAME_ADDRESS  https://www.fameladysociety.com/fame/metadata/ 888
```

Now, put all of the art into a single folder `.metadata/incoming'. If the art is just an image, put it as-is into the folder. If the token has an image and an animation_url that is an ".mp4" file, then put those 2 files into a directory inside this folder. The names of the files does not matter, they will all be renamed to a hash.

```
yarn nodets js/metadata/nameFiles.ts .metadata/incoming .metadata/staging/
```

There should be a folder full of images and folders named very long numbers at .metadata/staging

Upload these to ARWEAVE

```
source .env
export ARWEAVE_NETWORK=mainnet
export ARWEAVE_TOKEN=base-eth
export ARWEAVE_PRIVATE_KEY=$BASE_DEPLOYER_PRIVATE_KEY
export ARWEAVE_RPC=$BASE_RPC
yarn nodets js/metadata/upload.ts
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
cast send --rpc-url $RPC --private-key $DEPLOYER_PRIVATE_KEY $FAME_ADDRESS $(cast calldata "setRenderer(address)" $FAIR_REVEAL_ADDRESS)
```

And now run the reveal:

```
export BASE_URI="https://gateway.irys.xyz/${ARWEAVE_ID}/"
export TOTAL_AVAILABLE_ART=333
export REVEAL_AMOUNT=264
export SALT=0
cast send --rpc-url $RPC --private-key $DEPLOYER_PRIVATE_KEY $FAIR_REVEAL_ADDRESS $(cast calldata "reveal(string,uint256,uint16,uint16)" $BASE_URI $SALT $REVEAL_AMOUNT $TOTAL_AVAILABLE_ART)
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
source .env
export ARWEAVE_NETWORK=mainnet
export ARWEAVE_TOKEN=base-eth
export ARWEAVE_PRIVATE_KEY=$BASE_DEPLOYER_PRIVATE_KEY
export ARWEAVE_RPC=$BASE_RPC
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
export RPC=$BASE_RPC
export BATCH_SIZE=$(cat .metadata/$BATCH_RELEASE_DATE-metadata-manifest.json | jq -r '.paths | length')
cast send --rpc-url $RPC --private-key $BASE_DEPLOYER_PRIVATE_KEY --etherscan-api-key $BASE_ETHERSCAN_API_KEY 0xA50C9a918C110CA159fb187F4a55896A4d063878 "pushBatch(uint256,uint256,string)" $SALT $BATCH_SIZE $METADATA_BASE_URI
```

## Vesting

deploy:

```

export ETHERSCAN_API_KEY=$BASE_ETHERSCAN_API_KEY
forge create "src/FameVesting.sol:FameVesting" --rpc-url $RPC --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY --verify --constructor-args $FAME_ADDRESS

```

get the fame vesting contract address and set

```

export FAME_VESTING_CONTRACT_ADDRESS=0x....

```

allow the multisig to create vesting schedule

```

export RPC=$BASE_RPC
export MULTISIG_ADDRESS=$BASE_MULTISIG_ADDRESS
export DEPLOYER_PRIVATE_KEY=$BASE_DEPLOYER_PRIVATE_KEY
cast send --rpc-url $RPC --private-key $DEPLOYER_PRIVATE_KEY $FAME_VESTING_ADDRESS $(cast calldata "transferOwnership(address)" $MULTISIG_ADDRESS)

```

Now run this script to generate and submit the multisig transaction to run the presale cliff airdrop and the liner vesting:

```

export FAME_ADDRESS=$BASE_FAME_ADDRESS
export MULTISIG_PRIVATE_KEY=$DEPLOYER_PRIVATE_KEY
export MULTISIG_RPC=$BASE_RPC
export CLAIM_TO_FAME_ADDRESS=$BASE_CLAIM_TO_FAME_ADDRESS
export MULTISIG_CHAIN_ID=8453
yarn nodets js/presale/generate-vesting-transactions.ts

```

# Governance

## Localnet

### GovSociety

Set the Manager Address

```
export DAO_MANAGER_ADDRESS=0x1318454B32ea883dB5a729eA59783d9fAfA74908
export RPC=$SEPOLIA_RPC
export DEPLOYER_PRIVATE_KEY=$SEPOLIA_DEPLOYER_PRIVATE_KEY
export FAME_NFT_ADDRESS=$SEPOLIA_FAME_ADDRESS
export ETHERSCAN_API_KEY=$MAINNET_ETHERSCAN_API_KEY
```

Some versions of forge don't like the recent etherscan API changes. To verify off mainnet you may need to use the following:

```
--verifier-api-key $MAINNET_ETHERSCAN_API_KEY --verifier custom --verifier-url https://api-sepolia.etherscan.io/api
```

Deploy the GovSociety

```
export GOV_SOCIETY_ADDRESS=$(forge create --broadcast --json --verify src/GovSociety.sol:GovSociety --rpc-url $RPC --private-key $DEPLOYER_PRIVATE_KEY --constructor-args $FAME_NFT_ADDRESS $DAO_MANAGER_ADDRESS | jq -r .deployedTo)
echo Deployed GovSociety to $GOV_SOCIETY_ADDRESS
```

### FAMEusTimelockController

```
export FAMEUS_TIMELOCK_CONTROLLER_ADDRESS=`forge create --broadcast --json --verify src/FameusTimelockController.sol:FAMEusTimelockController --rpc-url $RPC --private-key $DEPLOYER_PRIVATE_KEY --constructor-args 0 "[$DAO_MANAGER_ADDRESS]" "[$DAO_MANAGER_ADDRESS]" $DAO_MANAGER_ADDRESS | jq -r .deployedTo`
echo Deployed FAMEusGovernor to $FAMEUS_TIMELOCK_CONTROLLER_ADDRESS
```

### FAMEusGovernor

```
export FAMEUS_GOVERNOR=`forge create --broadcast --json --verify --verifier-api-key $MAINNET_ETHERSCAN_API_KEY --verifier custom --verifier-url https://api-sepolia.etherscan.io/api src/FameusGoverner.sol:FAMEusGovernor --rpc-url $RPC --private-key $DEPLOYER_PRIVATE_KEY --constructor-args $GOV_SOCIETY_ADDRESS $FAMEUS_TIMELOCK_CONTROLLER_ADDRESS | jq -r .deployedTo`
echo Deployed FAMEusGovernor to $FAMEUS_GOVERNOR
```

## Sepolia

Setup the deployer address

```
export SEPOLIA_DEPLOYER_ADDRESS=0x1318454B32ea883dB5a729eA59783d9fAfA74908
```

should match the private key of SEPOLIA_DEPLOYER_PRIVATE_KEY

We will need the renderer address from the Fame contract

```
export SEPOLIA_RENDERER_ADDRESS=$(cast abi-decode "renderer()(address)" $(cast call $SEPOLIA_FAME_ADDRESS "renderer()" --rpc-url $SEPOLIA_RPC))
```

### GovSociety

```bash
# Deploy
export GOV_SOCIETY_ADDRESS=$(forge create src/GovSociety.sol:GovSociety --broadcast --json --rpc-url $SEPOLIA_RPC --private-key $SEPOLIA_DEPLOYER_PRIVATE_KEY --constructor-args $SEPOLIA_FAME_NFT_ADDRESS $SEPOLIA_DEPLOYER_ADDRESS $SEPOLIA_RENDERER_ADDRESS | jq -r .deployedTo)
echo Deployed GovSociety to $GOV_SOCIETY_ADDRESS

# Verify
forge verify-contract $GOV_SOCIETY_ADDRESS src/GovSociety.sol:GovSociety --chain-id 11155111 --constructor-args $(cast abi-encode "constructor(address,address,address)" $SEPOLIA_FAME_NFT_ADDRESS $SEPOLIA_DEPLOYER_ADDRESS $SEPOLIA_RENDERER_ADDRESS) --etherscan-api-key $MAINNET_ETHERSCAN_API_KEY
```

### FAMEusTimelockController

```bash
# Deploy
export FAMEUS_TIMELOCK_CONTROLLER_ADDRESS=`forge create src/FameusTimelockController.sol:FAMEusTimelockController --rpc-url $SEPOLIA_RPC --private-key $SEPOLIA_DEPLOYER_PRIVATE_KEY --constructor-args 0 '[$SEPOLIA_DEPLOYER_ADDRESS]' '[$SEPOLIA_DEPLOYER_ADDRESS]' $SEPOLIA_DEPLOYER_ADDRESS --legacy --json | jq -r .deployedTo`
echo Deployed FAMEusTimelockController to $FAMEUS_TIMELOCK_CONTROLLER_ADDRESS

# Verify
forge verify-contract $FAMEUS_TIMELOCK_CONTROLLER_ADDRESS src/FameusTimelockController.sol:FAMEusTimelockController --chain-id 11155111 --constructor-args $(cast abi-encode "constructor(uint256,address[],address[],address)" 0 '[$SEPOLIA_DEPLOYER_ADDRESS]' '[$SEPOLIA_DEPLOYER_ADDRESS]' $SEPOLIA_DEPLOYER_ADDRESS) --etherscan-api-key $MAINNET_ETHERSCAN_API_KEY
```

### FAMEusGovernor

```bash
# Deploy
export FAMEUS_GOVERNOR=$(forge create src/FameusGoverner.sol:FAMEusGovernor --rpc-url $SEPOLIA_RPC --private-key $SEPOLIA_DEPLOYER_PRIVATE_KEY --constructor-args $GOV_SOCIETY_ADDRESS $FAMEUS_TIMELOCK_CONTROLLER_ADDRESS --legacy --json | jq -r .deployedTo)
echo Deployed FAMEusGovernor to $FAMEUS_GOVERNOR

# Verify
forge verify-contract $FAMEUS_GOVERNOR src/FameusGoverner.sol:FAMEusGovernor --chain-id 11155111 --constructor-args $(cast abi-encode "constructor(address,address)" $GOV_SOCIETY_ADDRESS $FAMEUS_TIMELOCK_CONTROLLER_ADDRESS) --etherscan-api-key $MAINNET_ETHERSCAN_API_KEY
```
