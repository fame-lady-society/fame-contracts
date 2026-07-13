// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SocietyNftAuction} from "../src/SocietyNftAuction.sol";
import {AuctionBidder, ForceEth, MockSocietyNftMirror, RejectingEthOwner} from "./mocks/SocietyNftAuctionActors.sol";

contract SocietyNftAuctionTest is Test {
    address internal constant MIRROR = 0xBB5ED04dD7B207592429eb8d599d103CCad646c4;
    address internal owner = makeAddr("owner");
    address internal nextOwner = makeAddr("nextOwner");
    address internal stranger = makeAddr("stranger");
    uint256 internal constant TOKEN_ID = 42;

    event AuctionStarted(uint256 indexed tokenId, uint256 startTime, uint256 endTime);
    event BidAccepted(address indexed bidder, uint256 amount);
    event BidRefunded(address indexed bidder, uint256 amount);
    event BidRefundDonated(address indexed bidder, uint256 amount);
    event AuctionSettled(address indexed recipient, uint256 winningBid, uint256 proceeds);
    event ProceedsWithdrawn(address indexed owner, uint256 amount);
    event ExcessSwept(address indexed owner, uint256 amount);

    SocietyNftAuction internal auction;
    MockSocietyNftMirror internal mirror;

    function setUp() public {
        MockSocietyNftMirror implementation = new MockSocietyNftMirror();
        vm.etch(MIRROR, address(implementation).code);
        mirror = MockSocietyNftMirror(MIRROR);
        auction = new SocietyNftAuction(owner);
        mirror.mint(owner, TOKEN_ID);
    }

    function testConstructorRejectsZeroOwner() public {
        vm.expectRevert(SocietyNftAuction.ZeroAddress.selector);
        new SocietyNftAuction(address(0));
    }

    function testStartEscrowsExactTokenAndSetsThreeDayWindow() public {
        vm.prank(owner);
        mirror.approve(address(auction), TOKEN_ID);

        uint256 expectedStart = block.timestamp;
        vm.prank(owner);
        auction.start(TOKEN_ID);

        assertEq(uint8(auction.lifecycle()), uint8(SocietyNftAuction.Lifecycle.Active));
        assertEq(auction.tokenId(), TOKEN_ID);
        assertEq(auction.startTime(), expectedStart);
        assertEq(auction.endTime(), expectedStart + 3 days);
        assertEq(mirror.ownerOf(TOKEN_ID), address(auction));
    }

    function testStartSupportsOperatorApproval() public {
        vm.prank(owner);
        mirror.setApprovalForAll(address(auction), true);

        vm.prank(owner);
        auction.start(TOKEN_ID);

        assertEq(mirror.ownerOf(TOKEN_ID), address(auction));
    }

    function testStartRejectsMissingApprovalAtomically() public {
        vm.prank(owner);
        vm.expectRevert(SocietyNftAuction.NotApproved.selector);
        auction.start(TOKEN_ID);

        assertEq(uint8(auction.lifecycle()), uint8(SocietyNftAuction.Lifecycle.Unstarted));
        assertEq(mirror.ownerOf(TOKEN_ID), owner);
        assertEq(auction.startTime(), 0);
        assertEq(auction.endTime(), 0);
    }

    function testStartRejectsNonexistentToken() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(SocietyNftAuction.TokenDoesNotExist.selector, TOKEN_ID + 1));
        auction.start(TOKEN_ID + 1);
    }

    function testStartRejectsWrongTokenOwner() public {
        vm.prank(owner);
        mirror.approve(address(auction), TOKEN_ID);
        vm.prank(owner);
        mirror.transferFrom(owner, stranger, TOKEN_ID);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(SocietyNftAuction.TokenOwnerMismatch.selector, owner, stranger));
        auction.start(TOKEN_ID);
    }

    function testStartRejectsNonOwnerAndRepeatedStart() public {
        vm.prank(stranger);
        vm.expectRevert();
        auction.start(TOKEN_ID);

        vm.prank(owner);
        mirror.approve(address(auction), TOKEN_ID);
        vm.prank(owner);
        auction.start(TOKEN_ID);

        vm.prank(owner);
        vm.expectRevert(SocietyNftAuction.AlreadyStarted.selector);
        auction.start(TOKEN_ID);
    }

    function testReceiverRejectsTransfersOutsideStartContext() public {
        vm.prank(owner);
        mirror.approve(address(this), TOKEN_ID);

        vm.expectRevert(SocietyNftAuction.UnexpectedNftReceipt.selector);
        mirror.safeTransferFrom(owner, address(auction), TOKEN_ID);

        assertEq(mirror.ownerOf(TOKEN_ID), owner);
    }

    function testReceiverRejectsWrongCollectionCaller() public {
        vm.expectRevert(SocietyNftAuction.UnexpectedNftReceipt.selector);
        auction.onERC721Received(address(auction), owner, TOKEN_ID, "");
    }

    function testStartRollsBackOnMalformedOrMissingReceiptCallback() public {
        _assertMalformedCallbackRollsBack(MockSocietyNftMirror.CallbackMode.WrongOperator);
        _assertMalformedCallbackRollsBack(MockSocietyNftMirror.CallbackMode.WrongFrom);
        _assertMalformedCallbackRollsBack(MockSocietyNftMirror.CallbackMode.WrongTokenId);
        _assertMalformedCallbackRollsBack(MockSocietyNftMirror.CallbackMode.MissingCallback);
    }

    function testOwnershipDirectAndTwoStepRemainNonzero() public {
        vm.prank(owner);
        auction.transferOwnership(nextOwner);
        assertEq(auction.owner(), nextOwner);

        vm.prank(owner);
        auction.requestOwnershipHandover();
        vm.prank(nextOwner);
        auction.completeOwnershipHandover(owner);
        assertEq(auction.owner(), owner);

        vm.prank(owner);
        vm.expectRevert();
        auction.transferOwnership(address(0));

        vm.prank(owner);
        vm.expectRevert(SocietyNftAuction.OwnershipRenunciationDisabled.selector);
        auction.renounceOwnership();
    }

    function testOwnershipHandoverCancelMissingAndExpiry() public {
        vm.prank(nextOwner);
        auction.requestOwnershipHandover();
        vm.prank(nextOwner);
        auction.cancelOwnershipHandover();
        vm.prank(owner);
        vm.expectRevert();
        auction.completeOwnershipHandover(nextOwner);

        vm.prank(nextOwner);
        auction.requestOwnershipHandover();
        vm.warp(block.timestamp + 48 hours + 1);
        vm.prank(owner);
        vm.expectRevert();
        auction.completeOwnershipHandover(nextOwner);
    }

    function testOwnershipEntrypointsRejectAttachedEth() public {
        vm.deal(owner, 5 ether);

        vm.prank(owner);
        vm.expectRevert(SocietyNftAuction.UnexpectedEth.selector);
        auction.transferOwnership{value: 1 wei}(nextOwner);

        vm.prank(owner);
        vm.expectRevert(SocietyNftAuction.UnexpectedEth.selector);
        auction.requestOwnershipHandover{value: 1 wei}();

        vm.prank(owner);
        vm.expectRevert(SocietyNftAuction.UnexpectedEth.selector);
        auction.cancelOwnershipHandover{value: 1 wei}();

        vm.prank(nextOwner);
        auction.requestOwnershipHandover();
        vm.prank(owner);
        vm.expectRevert(SocietyNftAuction.UnexpectedEth.selector);
        auction.completeOwnershipHandover{value: 1 wei}(nextOwner);

        vm.prank(owner);
        vm.expectRevert(SocietyNftAuction.UnexpectedEth.selector);
        auction.renounceOwnership{value: 1 wei}();

        assertEq(address(auction).balance, 0);
        assertEq(auction.owner(), owner);
    }

    function testFirstBidAndStrictIncreaseAcrossTimeBoundary() public {
        _startAuction();
        address bidder = makeAddr("bidder");
        vm.deal(bidder, 3 ether);

        vm.prank(bidder);
        auction.bid{value: 1 ether}();
        assertEq(auction.highestBidder(), bidder);
        assertEq(auction.highestBid(), 1 ether);

        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        vm.expectRevert(SocietyNftAuction.BidTooLow.selector);
        auction.bid{value: 1 ether}();

        vm.warp(auction.endTime() - 1);
        vm.prank(bidder);
        auction.bid{value: 2 ether}();
        assertEq(auction.highestBid(), 2 ether);

        vm.warp(auction.endTime());
        vm.deal(bidder, 3 ether);
        vm.prank(bidder);
        vm.expectRevert(SocietyNftAuction.BiddingClosed.selector);
        auction.bid{value: 3 ether}();
    }

    function testMinimumNextBidRoundsUpAndEnforcesTenPercentIncrease() public {
        vm.expectRevert(SocietyNftAuction.BiddingClosed.selector);
        auction.minimumNextBid();
        _startAuction();
        assertEq(auction.minimumNextBid(), 1);

        address bidder = makeAddr("rounding-bidder");
        vm.deal(bidder, 100 wei);
        vm.prank(bidder);
        auction.bid{value: 10 wei}();

        assertEq(auction.minimumNextBid(), 11 wei);

        vm.deal(stranger, 100 wei);
        vm.prank(stranger);
        auction.bid{value: 11 wei}();

        assertEq(auction.minimumNextBid(), 13 wei);

        vm.prank(stranger);
        vm.expectRevert(SocietyNftAuction.BidTooLow.selector);
        auction.bid{value: 12 wei}();

        vm.prank(stranger);
        auction.bid{value: 13 wei}();
        assertEq(auction.highestBid(), 13 wei);
        assertEq(auction.minimumNextBid(), 15 wei);

        vm.warp(auction.endTime());
        vm.expectRevert(SocietyNftAuction.BiddingClosed.selector);
        auction.minimumNextBid();

        auction.settle();
        vm.expectRevert(SocietyNftAuction.BiddingClosed.selector);
        auction.minimumNextBid();
    }

    function testFirstBidRejectsZeroAndAcceptsOneWei() public {
        _startAuction();
        address bidder = makeAddr("one-wei-bidder");
        vm.deal(bidder, 1 wei);

        vm.prank(bidder);
        vm.expectRevert(SocietyNftAuction.BidTooLow.selector);
        auction.bid{value: 0}();

        vm.prank(bidder);
        auction.bid{value: 1 wei}();

        assertEq(auction.highestBidder(), bidder);
        assertEq(auction.highestBid(), 1 wei);
        assertEq(auction.minimumNextBid(), 2 wei);
    }

    function testHighestBidderCanOutbidThemselvesAtMinimumNextBid() public {
        _startAuction();
        address bidder = makeAddr("self-outbidder");
        vm.deal(bidder, 3 ether);

        vm.prank(bidder);
        auction.bid{value: 1 ether}();
        assertEq(auction.minimumNextBid(), 1.1 ether);

        vm.prank(bidder);
        auction.bid{value: 1.1 ether}();

        assertEq(auction.highestBidder(), bidder);
        assertEq(auction.highestBid(), 1.1 ether);
        assertEq(auction.failedRefundDonations(), 0);
        assertEq(address(auction).balance, 1.1 ether);
        assertEq(bidder.balance, 1.9 ether);
    }

    function testRejectingHighestBidderCanSelfOutbidAndDonatePriorBid() public {
        _startAuction();
        AuctionBidder bidder = new AuctionBidder();
        bidder.configure(AuctionBidder.RefundMode.Reject, address(auction), "");

        bidder.placeBid{value: 1 ether}(address(auction));
        bidder.placeBid{value: 1.1 ether}(address(auction));

        assertEq(auction.highestBidder(), address(bidder));
        assertEq(auction.highestBid(), 1.1 ether);
        assertEq(auction.failedRefundDonations(), 1 ether);
        assertEq(address(auction).balance, 2.1 ether);
    }

    function testAcceptingPriorBidderReceivesFullRefundWithBoundedGas() public {
        _startAuction();
        AuctionBidder prior = new AuctionBidder();
        prior.placeBid{value: 1 ether}(address(auction));

        vm.deal(stranger, 2 ether);
        vm.prank(stranger);
        auction.bid{value: 2 ether}();

        assertEq(address(prior).balance, 1 ether);
        assertEq(auction.failedRefundDonations(), 0);
        assertGe(prior.refundGasAtEntry(), auction.REFUND_GAS_STIPEND() - 1_000);
        assertEq(address(auction).balance, 2 ether);
    }

    function testRejectedRefundBecomesDonationWithoutBlockingHigherBid() public {
        _startAuction();
        AuctionBidder prior = new AuctionBidder();
        prior.configure(AuctionBidder.RefundMode.Reject, address(auction), "");
        prior.placeBid{value: 1 ether}(address(auction));

        vm.deal(stranger, 2 ether);
        vm.prank(stranger);
        auction.bid{value: 2 ether}();

        assertEq(auction.highestBidder(), stranger);
        assertEq(auction.highestBid(), 2 ether);
        assertEq(auction.failedRefundDonations(), 1 ether);
        assertEq(address(auction).balance, 3 ether);
    }

    function testGasBurningRefundRecipientCannotBlockHigherBid() public {
        _startAuction();
        AuctionBidder prior = new AuctionBidder();
        prior.configure(AuctionBidder.RefundMode.BurnGas, address(auction), "");
        prior.placeBid{value: 1 ether}(address(auction));

        vm.deal(stranger, 2 ether);
        vm.prank(stranger);
        auction.bid{value: 2 ether}();

        assertEq(auction.highestBidder(), stranger);
        assertEq(auction.failedRefundDonations(), 1 ether);
    }

    function testRefundCallbackCannotReenterAuctionMutations() public {
        _startAuction();
        uint256 baseline = vm.snapshot();
        bytes[] memory calls = new bytes[](7);
        calls[0] = abi.encodeCall(auction.start, (TOKEN_ID));
        calls[1] = abi.encodeCall(auction.bid, ());
        calls[2] = abi.encodeCall(auction.settle, ());
        calls[3] = abi.encodeCall(auction.withdrawProceeds, ());
        calls[4] = abi.encodeCall(auction.sweepExcess, ());
        calls[5] = abi.encodeCall(auction.transferOwnership, (nextOwner));
        calls[6] = abi.encodeCall(auction.completeOwnershipHandover, (nextOwner));

        for (uint256 i; i < calls.length; ++i) {
            assertTrue(vm.revertTo(baseline));
            baseline = vm.snapshot();
            AuctionBidder prior = new AuctionBidder();
            vm.prank(owner);
            auction.transferOwnership(address(prior));
            if (i == 6) {
                vm.prank(nextOwner);
                auction.requestOwnershipHandover();
            }
            uint256 reentryValue = i == 1 ? 3 ether : 0;
            prior.configureReentry(address(auction), calls[i], reentryValue);
            vm.deal(address(prior), reentryValue);
            prior.placeBid{value: 1 ether}(address(auction));

            vm.deal(stranger, 2 ether);
            vm.prank(stranger);
            auction.bid{value: 2 ether}();

            assertFalse(prior.reentrySucceeded(), "reentrant mutation succeeded");
            assertEq(auction.highestBidder(), stranger);
            assertEq(auction.highestBid(), 2 ether);
            assertEq(auction.failedRefundDonations(), 0);
        }
    }

    function testRefundGasBoundaryRollsBackBelowAndCompletesAtOrAboveThreshold() public {
        _startAuction();
        AuctionBidder prior = new AuctionBidder();
        prior.configure(AuctionBidder.RefundMode.BurnGas, address(auction), "");
        prior.placeBid{value: 1 ether}(address(auction));
        vm.deal(stranger, 2 ether);

        uint256 baseline = vm.snapshot();
        uint256 low = 150_000;
        uint256 high = 500_000;
        while (low + 1 < high) {
            uint256 candidate = (low + high) / 2;
            (bool succeeded,) = _tryReplacementBid(candidate);
            assertTrue(vm.revertTo(baseline));
            baseline = vm.snapshot();
            if (succeeded) high = candidate;
            else low = candidate;
        }

        (bool belowSucceeded, bytes memory belowReason) = _tryReplacementBid(high - 1);
        assertFalse(belowSucceeded);
        assertEq(bytes4(belowReason), SocietyNftAuction.InsufficientRefundGas.selector);
        assertEq(auction.highestBidder(), address(prior));
        assertEq(auction.failedRefundDonations(), 0);

        assertTrue(vm.revertTo(baseline));
        baseline = vm.snapshot();
        (bool aboveSucceeded,) = _tryReplacementBid(high + 1);
        assertTrue(aboveSucceeded);
        assertEq(auction.failedRefundDonations(), 1 ether);

        assertTrue(vm.revertTo(baseline));
        (bool atSucceeded,) = _tryReplacementBid(high);
        assertTrue(atSucceeded);
        assertEq(auction.highestBidder(), stranger);
        assertEq(auction.highestBid(), 2 ether);
        assertEq(auction.failedRefundDonations(), 1 ether);
    }

    function testFuzzMinimumIncreaseConservesAccountedEth(uint96 first, uint96 second) public {
        first = uint96(bound(first, 1, 10 ether));
        _startAuction();
        address firstBidder = makeAddr("firstBidder");
        vm.deal(firstBidder, first);
        vm.prank(firstBidder);
        auction.bid{value: first}();

        second = uint96(bound(second, auction.minimumNextBid(), 20 ether));
        vm.deal(stranger, second);
        vm.prank(stranger);
        auction.bid{value: second}();

        assertEq(auction.highestBid(), second);
        assertEq(address(auction).balance, second + auction.failedRefundDonations());
    }

    function testNoBidSettlementAtDeadlineReturnsNftToCurrentOwner() public {
        _startAuction();
        vm.prank(owner);
        auction.transferOwnership(nextOwner);

        vm.warp(auction.endTime() - 1);
        vm.expectRevert(SocietyNftAuction.SettlementUnavailable.selector);
        auction.settle();

        vm.warp(auction.endTime());
        vm.prank(stranger);
        auction.settle();

        assertEq(uint8(auction.lifecycle()), uint8(SocietyNftAuction.Lifecycle.Settled));
        assertEq(auction.settledRecipient(), nextOwner);
        assertEq(mirror.ownerOf(TOKEN_ID), nextOwner);
        assertEq(auction.withdrawableProceeds(), 0);
    }

    function testWinningContractCannotRejectCallbackFreeSettlement() public {
        _startAuction();
        AuctionBidder winner = new AuctionBidder();
        winner.placeBid{value: 1 ether}(address(auction));

        vm.warp(auction.endTime());
        auction.settle();

        assertEq(mirror.ownerOf(TOKEN_ID), address(winner));
        assertEq(auction.withdrawableProceeds(), 1 ether);
    }

    function testMirrorFailureRollsSettlementBack() public {
        _startAuction();
        vm.warp(auction.endTime());
        mirror.setFailTransfers(true);

        vm.expectRevert();
        auction.settle();

        assertEq(uint8(auction.lifecycle()), uint8(SocietyNftAuction.Lifecycle.Active));
        assertEq(auction.withdrawableProceeds(), 0);
        assertEq(mirror.ownerOf(TOKEN_ID), address(auction));
    }

    function testWithdrawalIncludesWinningBidAndRejectedRefundDonation() public {
        _startAuction();
        AuctionBidder rejecting = new AuctionBidder();
        rejecting.configure(AuctionBidder.RefundMode.Reject, address(auction), "");
        rejecting.placeBid{value: 1 ether}(address(auction));
        vm.deal(stranger, 2 ether);
        vm.prank(stranger);
        auction.bid{value: 2 ether}();
        vm.warp(auction.endTime());
        auction.settle();

        assertEq(auction.withdrawableProceeds(), 3 ether);
        uint256 before = owner.balance;
        vm.prank(owner);
        auction.withdrawProceeds();
        assertEq(owner.balance - before, 3 ether);
        assertEq(auction.withdrawableProceeds(), 0);

        vm.prank(owner);
        vm.expectRevert(SocietyNftAuction.NoProceeds.selector);
        auction.withdrawProceeds();
    }

    function testWithdrawalBeforeSettlementRejects() public {
        _startAuction();
        vm.prank(owner);
        vm.expectRevert(SocietyNftAuction.NotSettled.selector);
        auction.withdrawProceeds();
    }

    function testRejectingOwnerCanTransferClaimAndRetry() public {
        _startAuction();
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        auction.bid{value: 1 ether}();
        RejectingEthOwner rejectingOwner = new RejectingEthOwner();
        vm.prank(owner);
        auction.transferOwnership(address(rejectingOwner));
        vm.warp(auction.endTime());
        auction.settle();

        vm.expectRevert();
        rejectingOwner.withdraw(address(auction));
        assertEq(auction.withdrawableProceeds(), 1 ether);

        rejectingOwner.transferAuctionOwnership(address(auction), nextOwner);
        uint256 before = nextOwner.balance;
        vm.prank(nextOwner);
        auction.withdrawProceeds();
        assertEq(nextOwner.balance - before, 1 ether);
    }

    function testForcedEthIsOnlySweepableAfterSettlementAndDoesNotChangeAuctionAccounting() public {
        _startAuction();
        ForceEth force = new ForceEth{value: 2 ether}();
        force.force(payable(address(auction)));
        assertEq(auction.highestBid(), 0);
        assertEq(auction.failedRefundDonations(), 0);

        vm.prank(owner);
        vm.expectRevert(SocietyNftAuction.NotSettled.selector);
        auction.sweepExcess();

        vm.warp(auction.endTime());
        auction.settle();
        uint256 before = owner.balance;
        vm.prank(owner);
        auction.sweepExcess();
        assertEq(owner.balance - before, 2 ether);

        vm.prank(owner);
        vm.expectRevert(SocietyNftAuction.NoExcess.selector);
        auction.sweepExcess();
    }

    function testSweepAndWithdrawalOrderPreserveSeparateBuckets() public {
        _startAuction();
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        auction.bid{value: 1 ether}();
        ForceEth force = new ForceEth{value: 2 ether}();
        force.force(payable(address(auction)));
        vm.warp(auction.endTime());
        auction.settle();

        uint256 before = owner.balance;
        vm.prank(owner);
        auction.sweepExcess();
        assertEq(auction.withdrawableProceeds(), 1 ether);
        vm.prank(owner);
        auction.withdrawProceeds();
        assertEq(owner.balance - before, 3 ether);
        assertEq(address(auction).balance, 0);
    }

    function testWithdrawalThenSweepPreservesSeparateBuckets() public {
        _startAuction();
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        auction.bid{value: 1 ether}();
        ForceEth force = new ForceEth{value: 2 ether}();
        force.force(payable(address(auction)));
        vm.warp(auction.endTime());
        auction.settle();

        uint256 before = owner.balance;
        vm.prank(owner);
        auction.withdrawProceeds();
        vm.prank(owner);
        auction.sweepExcess();
        assertEq(owner.balance - before, 3 ether);
        assertEq(address(auction).balance, 0);
    }

    function testRejectingOwnerCanTransferExcessRightAndRetry() public {
        _startAuction();
        ForceEth force = new ForceEth{value: 1 ether}();
        force.force(payable(address(auction)));
        vm.warp(auction.endTime());
        auction.settle();
        RejectingEthOwner rejectingOwner = new RejectingEthOwner();
        vm.prank(owner);
        auction.transferOwnership(address(rejectingOwner));

        vm.expectRevert();
        rejectingOwner.sweep(address(auction));
        assertEq(address(auction).balance, 1 ether);

        rejectingOwner.transferAuctionOwnership(address(auction), nextOwner);
        vm.prank(nextOwner);
        auction.sweepExcess();
        assertEq(address(auction).balance, 0);
    }

    function testDirectEthAndRepeatedSettlementReject() public {
        (bool sent,) = address(auction).call{value: 1 wei}("");
        assertFalse(sent);

        _startAuction();
        vm.warp(auction.endTime());
        auction.settle();
        vm.expectRevert(SocietyNftAuction.SettlementUnavailable.selector);
        auction.settle();
    }

    function testPublicAuctionEventsExposeCompleteHistory() public {
        vm.prank(owner);
        mirror.approve(address(auction), TOKEN_ID);
        vm.expectEmit(true, false, false, true, address(auction));
        emit AuctionStarted(TOKEN_ID, block.timestamp, block.timestamp + 3 days);
        vm.prank(owner);
        auction.start(TOKEN_ID);

        AuctionBidder accepting = new AuctionBidder();
        vm.expectEmit(true, false, false, true, address(auction));
        emit BidAccepted(address(accepting), 1 ether);
        accepting.placeBid{value: 1 ether}(address(auction));

        vm.deal(stranger, 2 ether);
        vm.expectEmit(true, false, false, true, address(auction));
        emit BidAccepted(stranger, 2 ether);
        vm.expectEmit(true, false, false, true, address(auction));
        emit BidRefunded(address(accepting), 1 ether);
        vm.prank(stranger);
        auction.bid{value: 2 ether}();

        AuctionBidder rejecting = new AuctionBidder();
        rejecting.configure(AuctionBidder.RefundMode.Reject, address(auction), "");
        vm.expectEmit(true, false, false, true, address(auction));
        emit BidAccepted(address(rejecting), 3 ether);
        vm.expectEmit(true, false, false, true, address(auction));
        emit BidRefunded(stranger, 2 ether);
        rejecting.placeBid{value: 3 ether}(address(auction));

        address finalBidder = makeAddr("finalBidder");
        vm.deal(finalBidder, 4 ether);
        vm.expectEmit(true, false, false, true, address(auction));
        emit BidAccepted(finalBidder, 4 ether);
        vm.expectEmit(true, false, false, true, address(auction));
        emit BidRefundDonated(address(rejecting), 3 ether);
        vm.prank(finalBidder);
        auction.bid{value: 4 ether}();

        vm.warp(auction.endTime());
        vm.expectEmit(true, false, false, true, address(auction));
        emit AuctionSettled(finalBidder, 4 ether, 7 ether);
        auction.settle();

        vm.expectEmit(true, false, false, true, address(auction));
        emit ProceedsWithdrawn(owner, 7 ether);
        vm.prank(owner);
        auction.withdrawProceeds();

        ForceEth force = new ForceEth{value: 1 ether}();
        force.force(payable(address(auction)));
        vm.expectEmit(true, false, false, true, address(auction));
        emit ExcessSwept(owner, 1 ether);
        vm.prank(owner);
        auction.sweepExcess();
    }

    function _startAuction() internal {
        vm.prank(owner);
        mirror.approve(address(auction), TOKEN_ID);
        vm.prank(owner);
        auction.start(TOKEN_ID);
    }

    function _assertMalformedCallbackRollsBack(MockSocietyNftMirror.CallbackMode mode) internal {
        vm.startPrank(owner);
        mirror.approve(address(auction), TOKEN_ID);
        mirror.setCallbackMode(mode);
        vm.expectRevert(SocietyNftAuction.UnexpectedNftReceipt.selector);
        auction.start(TOKEN_ID);
        vm.stopPrank();

        assertEq(mirror.ownerOf(TOKEN_ID), owner);
        assertEq(uint8(auction.lifecycle()), uint8(SocietyNftAuction.Lifecycle.Unstarted));
    }

    function _tryReplacementBid(uint256 gasLimit) internal returns (bool succeeded, bytes memory reason) {
        vm.prank(stranger);
        (succeeded, reason) = address(auction).call{value: 2 ether, gas: gasLimit}(abi.encodeCall(auction.bid, ()));
    }
}
