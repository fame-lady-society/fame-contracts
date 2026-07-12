// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {IERC721} from "@openzeppelin5/contracts/token/ERC721/IERC721.sol";
import {SocietyNftAuction} from "../src/SocietyNftAuction.sol";

contract ValidateSocietyNftAuctionBase is Script {
    uint256 public constant BASE_CHAIN_ID = 8453;
    address public constant EXPECTED_SOCIETY_NFT = 0xBB5ED04dD7B207592429eb8d599d103CCad646c4;

    error AuctionNotConfigured();
    error ChainIdMismatch(uint256 expected, uint256 actual);
    error EconomicStateNotPristine();
    error LifecycleNotPristine();
    error LotNotApproved();
    error LotOwnerMismatch(address expected, address actual);
    error MirrorMismatch(address expected, address actual);
    error OwnerMismatch(address expected, address actual);
    error RuntimeCodeMismatch();
    error TimingStateNotPristine();

    function run() external view {
        address auctionAddress = vm.envAddress("BASE_SOCIETY_NFT_AUCTION_ADDRESS");
        address expectedOwner = vm.envAddress("BASE_SOCIETY_NFT_AUCTION_OWNER");
        uint256 intendedTokenId = vm.envUint("BASE_SOCIETY_NFT_AUCTION_TOKEN_ID");
        if (auctionAddress == address(0) || expectedOwner == address(0)) revert AuctionNotConfigured();

        SocietyNftAuction auction = SocietyNftAuction(payable(auctionAddress));
        validateAuction(auction, expectedOwner);
        validateIntendedLot(auction, intendedTokenId);
    }

    function validateAuction(SocietyNftAuction auction, address expectedOwner) public view {
        if (block.chainid != BASE_CHAIN_ID) revert ChainIdMismatch(BASE_CHAIN_ID, block.chainid);
        if (address(auction).codehash != keccak256(type(SocietyNftAuction).runtimeCode)) {
            revert RuntimeCodeMismatch();
        }
        address actualOwner = auction.owner();
        if (actualOwner != expectedOwner) revert OwnerMismatch(expectedOwner, actualOwner);
        address actualMirror = auction.SOCIETY_NFT();
        if (actualMirror != EXPECTED_SOCIETY_NFT) revert MirrorMismatch(EXPECTED_SOCIETY_NFT, actualMirror);
        if (auction.lifecycle() != SocietyNftAuction.Lifecycle.Unstarted) revert LifecycleNotPristine();
        if (auction.startTime() != 0 || auction.endTime() != 0) revert TimingStateNotPristine();
        if (
            auction.highestBidder() != address(0) || auction.highestBid() != 0 || auction.failedRefundDonations() != 0
                || auction.settledRecipient() != address(0) || auction.withdrawableProceeds() != 0
        ) revert EconomicStateNotPristine();
    }

    function validateIntendedLot(SocietyNftAuction auction, uint256 intendedTokenId) public view {
        IERC721 mirror = IERC721(auction.SOCIETY_NFT());
        address expectedOwner = auction.owner();
        address tokenOwner = mirror.ownerOf(intendedTokenId);
        if (tokenOwner != expectedOwner) revert LotOwnerMismatch(expectedOwner, tokenOwner);
        bool approved = mirror.getApproved(intendedTokenId) == address(auction)
            || mirror.isApprovedForAll(expectedOwner, address(auction));
        if (!approved) revert LotNotApproved();
    }
}
