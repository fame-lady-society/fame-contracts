#!/bin/bash
set -e

source .env

# Function to check if verification should be enabled based on RPC URL
should_verify() {
    local rpc_url=$1
    if [ "$rpc_url" != "http://localhost:8545" ]; then
        echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY"
    fi
}

RPC=${1:-http://localhost:8545}

CHILD_RENDERER_CONTRACT_ADDRESS=`cast call $BASE_FAME_ADDRESS "renderer()(address)" --rpc-url $RPC`

STARTING_TOKEN_ID=645
while true; do
    echo "Checking tokenURI($STARTING_TOKEN_ID)"
    TOKEN_URI=$(cast call $CHILD_RENDERER_CONTRACT_ADDRESS "tokenURI(uint256)(string)" $STARTING_TOKEN_ID --rpc-url $RPC 2>/dev/null || echo "")
    
    if [ -z "$TOKEN_URI" ]; then
        break
    fi
    if [[ "$TOKEN_URI" =~ \"https://www\.fameladysociety\.com ]]; then
        break
    fi

    STARTING_TOKEN_ID=$((STARTING_TOKEN_ID + 1))
done

echo "Starting token ID: $STARTING_TOKEN_ID"

forge create src/CreatorArtistMagic.sol:CreatorArtistMagic \
--rpc-url $RPC \
--private-key $BASE_DEPLOYER_PRIVATE_KEY \
$(should_verify "$RPC") \
--broadcast \
--json \
--constructor-args $CHILD_RENDERER_CONTRACT_ADDRESS $BASE_FAME_ADDRESS $STARTING_TOKEN_ID \
| tee /tmp/deploy.json

CREATOR_ARTIST_MAGIC_CONTRACT_ADDRESS=$(jq -r '.deployedTo' /tmp/deploy.json)
# rm /tmp/deploy.json

cast send $BASE_FAME_ADDRESS "setRenderer(address)" $CREATOR_ARTIST_MAGIC_CONTRACT_ADDRESS --rpc-url $RPC --private-key $BASE_DEPLOYER_PRIVATE_KEY 
cast send $CREATOR_ARTIST_MAGIC_CONTRACT_ADDRESS "grantRoles(address,uint256)" 0xF11Ce547ff948a03570B20Eac4a4d7b648693324 1 --rpc-url $RPC --private-key $BASE_DEPLOYER_PRIVATE_KEY 