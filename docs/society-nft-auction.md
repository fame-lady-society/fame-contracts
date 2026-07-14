# Society NFT one-off auction

This contract auctions one NFT from the Society DN404 mirror on Base. It uses only the mirror's ERC-721 surface at `0xBB5ED04dD7B207592429eb8d599d103CCad646c4`; the DN404 ERC-20 side is deliberately irrelevant.

The auction has no reserve and runs for exactly three days after the owner atomically transfers the selected NFT into custody. Bids use native ETH. The first bid must be nonzero; every later bid must be at least 10% greater than the current bid, rounded up to the next wei. While bidding is active, `minimumNextBid()` exposes the exact accepted floor for wallets and interfaces; it reverts with `BiddingClosed` outside that window. The current leader may outbid themselves and receives the same bounded refund attempt as any other displaced bid. When an outbid recipient rejects or exhausts that 100,000-gas refund attempt, the complete prior bid becomes an irrevocable seller donation. Only the current top bid remains a bidder obligation.

## Irreversible boundary

Deployment is replaceable while the contract is pristine. A failed `start` reverts atomically. A successful `start` cannot be paused, cancelled, extended, restarted, or rescued; verify every public value and simulate the exact call before signing it. There is no rollback transaction after activation. Ownership remains transferable and carries the no-bid NFT return, proceeds, donations, and forced-ETH excess.

## Configure public values

Set these public values in `config/fame-public.env` only after independent confirmation:

- `BASE_SOCIETY_NFT_AUCTION_OWNER`
- `BASE_SOCIETY_NFT_AUCTION_TOKEN_ID`
- `BASE_SOCIETY_NFT_AUCTION_ADDRESS` after deployment

RPC URLs and signing material remain in Doppler.

Load the public configuration before every command:

```sh
set -a
source config/fame-public.env
set +a
```

## Local Base fork for webpage development

Run one command from this repository:

```sh
./script/start-society-nft-auction-fork.sh
```

The launcher loads `config/fame-public.env`, enters Doppler's `prd` config for the Base-mainnet RPC and deployer key, and then:

1. starts an Anvil Base fork on `http://127.0.0.1:8545`;
2. verifies the configured deployer owns the configured Society NFT at the fork block;
3. deploys the auction only to the local fork;
4. approves the local auction for the configured token;
5. runs the read-only deployment validator; and
6. writes public frontend values to the ignored `.society-nft-auction-fork.env` file.

The launcher owns the Anvil process and remains in the foreground. Keep that terminal open while developing; Ctrl-C stops the fork and removes that invocation's generated environment file. A new run creates a fresh fork and local deployment, so consume the address written by that run instead of hardcoding an old local address.

To launch the fork with an already-active local auction:

```sh
./script/start-society-nft-auction-fork.sh --start
```

Useful overrides:

```sh
./script/start-society-nft-auction-fork.sh --port 8546
./script/start-society-nft-auction-fork.sh --block-number 48549412
./script/start-society-nft-auction-fork.sh --env-file /path/to/fls-www/.env.auction-fork.local
```

The launcher overwrites files carrying its generated-file marker, but refuses to overwrite an existing unmarked file. Even with that guard, use a dedicated output path rather than an application's primary `.env.local`. The generated file contains no RPC secret or signing material. The default localhost RPC and local deployment are disposable and must never be copied into production configuration.

## Deploy and validate

1. Confirm the owner is nonzero, Base chain ID is `8453`, and the intended token ID is correct. This emergency one-off deployment requires the address derived from `BASE_DEPLOYER_PRIVATE_KEY` to equal `BASE_SOCIETY_NFT_AUCTION_OWNER`; the deployment script rejects any mismatch before broadcast.
2. Dry-run without `--broadcast`:

   ```sh
   doppler run -- forge script script/DeploySocietyNftAuction.s.sol --chain base --rpc-url base -vvv
   ```

3. Review the predicted address and pristine state. Broadcast only the deployment when those values match:

   ```sh
   doppler run -- forge script script/DeploySocietyNftAuction.s.sol --chain base --rpc-url base --broadcast -vvv
   ```

4. Add the resulting public address to `config/fame-public.env`. Do not commit `broadcast/` output.
5. Approve the deployed auction for the exact token, either with token approval or operator approval.
6. Run the read-only validator. It checks chain, runtime bytecode, owner, fixed mirror, pristine lifecycle/economics, intended token ownership, and approval:

   ```sh
   doppler run -- forge script script/ValidateSocietyNftAuctionBase.s.sol --chain base --rpc-url base -vvv
   ```

## Pre-start flight check

Simulate the exact owner call without broadcasting:

```sh
doppler run -- cast call "$BASE_SOCIETY_NFT_AUCTION_ADDRESS" \
  "start(uint256)" "$BASE_SOCIETY_NFT_AUCTION_TOKEN_ID" \
  --from "$BASE_SOCIETY_NFT_AUCTION_OWNER" --rpc-url base
```

Stop if validation or simulation reverts, if the owner or token differs, if approval is stale, or if the auction is not pristine. Once confirmed, submit the same `start(uint256)` call with the configured owner signer. Success requires:

- `AuctionStarted(tokenId, startTime, endTime)` for the intended token;
- `ownerOf(tokenId)` equal to the auction address;
- `endTime == startTime + 3 days`.

Publish the exact end timestamp. Bidding is open only while `startTime <= block.timestamp < endTime`.

## Monitor and finish

- `BidAccepted` identifies the current leader and full bid.
- `BidRefunded` means the prior bid left the contract.
- `BidRefundDonated` means the prior refund failed and is permanently seller proceeds.
- Anyone may call `settle()` at or after `endTime`. `AuctionSettled` records the winner or current owner for a no-bid auction.
- Only the current owner may call `withdrawProceeds()`. A rejecting owner leaves the claim intact; transfer ownership to a payable owner and retry.
- Only the current owner may call `sweepExcess()` after settlement. It moves forced ETH only and cannot consume `withdrawableProceeds`.

After settlement, independently confirm the NFT owner, `settledRecipient`, and `withdrawableProceeds` before withdrawing. `settle()` never transfers ETH and therefore cannot be blocked by the owner's payable behavior.
