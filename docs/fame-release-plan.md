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

For interested parties that want to buy early.... First obtain the token address. It will be the first CA that shows up in anvil or script logs

Some useful variables for up ahead:
```

source .env
export FAME_ADDRESS=0x...
export WETH_ADDRESS=$SEPOLIA_WETH_ADDRESS
export SWAP_ROUTER=$SEPOLIA_SWAP_ROUTER
export RPC=$SEPOLIA_RPC
export MULTISIG_ADDRESS=$SEPOLIA_MULTISIG_ADDRESS

First deposit and approve WETH on the swap router:

```
SNIPE_AMOUNT=0.001 SNIPE_PRIVATE_KEY=$SEPOLIA_SNIPE1_PRIVATE_KEY node --loader ts-node/esm src/launch/deposit.ts
```

This will continually attempt to execute a swap until it succeeds

```
SNIPE_PRIVATE_KEY=$SEPOLIA_SNIPE1_PRIVATE_KEY node --loader ts-node/esm src/launch/snipe.ts
```

Now launch the token for the society

```
forge script --chain sepolia script/DeployLaunchSepolia.sol:DeployLaunch --verify --broadcast --rpc-url $RPC
```

Now do a public launch

```
DEPLOYER_PRIVATE_KEY=$SEPOLIA_DEPLOYER_PRIVATE_KEY SIGNER_PRIVATE_KEY=$SEPOLIA_SIGNER_PRIVATE_KEY forge script script/SepoliaPostLaunchAirdrop.sol:DeployLaunch --broadcast --verify --rpc-url $RPC
```
