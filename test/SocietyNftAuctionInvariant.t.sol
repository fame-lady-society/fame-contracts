// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {SocietyNftAuction} from "../src/SocietyNftAuction.sol";
import {AuctionBidder, ForceEth, MockSocietyNftMirror} from "./mocks/SocietyNftAuctionActors.sol";

contract SocietyNftAuctionOwnerActor {
    SocietyNftAuction public immutable auction;

    constructor(SocietyNftAuction auction_) {
        auction = auction_;
    }

    receive() external payable {}

    function transferOwnership(address newOwner) external {
        auction.transferOwnership(newOwner);
    }

    function requestOwnershipHandover() external {
        auction.requestOwnershipHandover();
    }

    function completeOwnershipHandover(address pendingOwner) external {
        auction.completeOwnershipHandover(pendingOwner);
    }

    function withdrawProceeds() external {
        auction.withdrawProceeds();
    }

    function sweepExcess() external {
        auction.sweepExcess();
    }
}

contract SocietyNftAuctionHandler is Test {
    SocietyNftAuction public immutable auction;
    AuctionBidder public immutable rejectingBidder;
    SocietyNftAuctionOwnerActor public immutable ownerA;
    SocietyNftAuctionOwnerActor public immutable ownerB;
    uint256 public modeledForcedExcess;

    constructor(SocietyNftAuction auction_) {
        auction = auction_;
        rejectingBidder = new AuctionBidder();
        rejectingBidder.configure(AuctionBidder.RefundMode.Reject, address(auction_), "");
        ownerA = new SocietyNftAuctionOwnerActor(auction_);
        ownerB = new SocietyNftAuctionOwnerActor(auction_);
    }

    receive() external payable {}

    function bid(uint96 rawAmount, uint160 rawBidder) external {
        if (auction.lifecycle() != SocietyNftAuction.Lifecycle.Active || block.timestamp >= auction.endTime()) return;
        uint256 minimumBid = auction.minimumNextBid();
        uint256 amount = bound(uint256(rawAmount), minimumBid, minimumBid + 10 ether);
        address bidder = address(rawBidder);
        if (bidder == address(0) || bidder == address(auction)) bidder = address(0xB1D);
        vm.deal(bidder, amount);
        vm.prank(bidder);
        auction.bid{value: amount}();
    }

    function bidFromRejectingRecipient(uint96 rawAmount) external {
        if (auction.lifecycle() != SocietyNftAuction.Lifecycle.Active || block.timestamp >= auction.endTime()) return;
        uint256 minimumBid = auction.minimumNextBid();
        uint256 amount = bound(uint256(rawAmount), minimumBid, minimumBid + 10 ether);
        vm.deal(address(this), amount);
        rejectingBidder.placeBid{value: amount}(address(auction));
    }

    function advanceTime(uint32 secondsForward) external {
        if (auction.lifecycle() != SocietyNftAuction.Lifecycle.Active) return;
        uint256 target = block.timestamp + bound(uint256(secondsForward), 1, 4 days);
        vm.warp(target);
    }

    function settle() external {
        if (auction.lifecycle() == SocietyNftAuction.Lifecycle.Active && block.timestamp >= auction.endTime()) {
            auction.settle();
        }
    }

    function forceEth(uint96 rawAmount) external {
        uint256 amount = bound(uint256(rawAmount), 1, 5 ether);
        vm.deal(address(this), amount);
        ForceEth force = new ForceEth{value: amount}();
        force.force(payable(address(auction)));
        modeledForcedExcess += amount;
    }

    function transferOwnershipDirect(bool toOwnerA) external {
        address target = toOwnerA ? address(ownerA) : address(ownerB);
        address currentOwner = auction.owner();
        if (currentOwner == target) return;

        _transferFromCurrentOwner(currentOwner, target);
    }

    function completeOwnershipHandover(bool toOwnerA) external {
        SocietyNftAuctionOwnerActor pendingOwner = toOwnerA ? ownerA : ownerB;
        address pendingOwnerAddress = address(pendingOwner);
        address currentOwner = auction.owner();
        if (currentOwner == pendingOwnerAddress) return;

        pendingOwner.requestOwnershipHandover();
        if (currentOwner == address(this)) {
            auction.completeOwnershipHandover(pendingOwnerAddress);
        } else if (currentOwner == address(ownerA)) {
            ownerA.completeOwnershipHandover(pendingOwnerAddress);
        } else if (currentOwner == address(ownerB)) {
            ownerB.completeOwnershipHandover(pendingOwnerAddress);
        }
    }

    function regainOwnership() external {
        address currentOwner = auction.owner();
        if (currentOwner == address(ownerA)) {
            ownerA.transferOwnership(address(this));
        } else if (currentOwner == address(ownerB)) {
            ownerB.transferOwnership(address(this));
        }
    }

    function withdraw() external {
        if (auction.lifecycle() == SocietyNftAuction.Lifecycle.Settled && auction.withdrawableProceeds() != 0) {
            _withdrawAsCurrentOwner();
        }
    }

    function sweep() external {
        if (
            auction.lifecycle() == SocietyNftAuction.Lifecycle.Settled
                && address(auction).balance > auction.withdrawableProceeds()
        ) {
            _sweepAsCurrentOwner();
            modeledForcedExcess = 0;
        }
    }

    function _transferFromCurrentOwner(address currentOwner, address newOwner) private {
        if (currentOwner == address(this)) {
            auction.transferOwnership(newOwner);
        } else if (currentOwner == address(ownerA)) {
            ownerA.transferOwnership(newOwner);
        } else if (currentOwner == address(ownerB)) {
            ownerB.transferOwnership(newOwner);
        }
    }

    function _withdrawAsCurrentOwner() private {
        address currentOwner = auction.owner();
        if (currentOwner == address(this)) {
            auction.withdrawProceeds();
        } else if (currentOwner == address(ownerA)) {
            ownerA.withdrawProceeds();
        } else if (currentOwner == address(ownerB)) {
            ownerB.withdrawProceeds();
        }
    }

    function _sweepAsCurrentOwner() private {
        address currentOwner = auction.owner();
        if (currentOwner == address(this)) {
            auction.sweepExcess();
        } else if (currentOwner == address(ownerA)) {
            ownerA.sweepExcess();
        } else if (currentOwner == address(ownerB)) {
            ownerB.sweepExcess();
        }
    }
}

contract SocietyNftAuctionInvariantTest is StdInvariant, Test {
    address internal constant MIRROR = 0xBB5ED04dD7B207592429eb8d599d103CCad646c4;
    uint256 internal constant TOKEN_ID = 42;

    SocietyNftAuction internal auction;
    MockSocietyNftMirror internal mirror;
    SocietyNftAuctionHandler internal handler;

    function setUp() public {
        MockSocietyNftMirror implementation = new MockSocietyNftMirror();
        vm.etch(MIRROR, address(implementation).code);
        mirror = MockSocietyNftMirror(MIRROR);
        auction = new SocietyNftAuction(address(this));
        mirror.mint(address(this), TOKEN_ID);
        mirror.approve(address(auction), TOKEN_ID);
        auction.start(TOKEN_ID);

        handler = new SocietyNftAuctionHandler(auction);
        auction.transferOwnership(address(handler));
        targetContract(address(handler));
    }

    function invariantOwnerNeverZero() public view {
        assertTrue(auction.owner() != address(0));
    }

    function invariantBidDonationAndForcedEthAccountingMatchesBalance() public view {
        uint256 expectedBalance = handler.modeledForcedExcess();
        if (auction.lifecycle() == SocietyNftAuction.Lifecycle.Active) {
            expectedBalance += auction.highestBid() + auction.failedRefundDonations();
        } else {
            expectedBalance += auction.withdrawableProceeds();
        }
        assertEq(address(auction).balance, expectedBalance);
    }

    function invariantBidderAndBidStayPaired() public view {
        assertEq(auction.highestBidder() == address(0), auction.highestBid() == 0);
    }

    function invariantAuctionCustodyMatchesLifecycle() public view {
        SocietyNftAuction.Lifecycle currentLifecycle = auction.lifecycle();
        address tokenOwner = mirror.ownerOf(TOKEN_ID);
        if (currentLifecycle == SocietyNftAuction.Lifecycle.Active) {
            assertEq(tokenOwner, address(auction));
        } else if (currentLifecycle == SocietyNftAuction.Lifecycle.Settled) {
            assertTrue(tokenOwner != address(auction));
            assertEq(tokenOwner, auction.settledRecipient());
        }
    }

    function invariantLifecycleNeverReturnsToUnstarted() public view {
        assertTrue(auction.lifecycle() != SocietyNftAuction.Lifecycle.Unstarted);
    }
}
