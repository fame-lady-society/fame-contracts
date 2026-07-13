// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "solady/auth/Ownable.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IERC721} from "@openzeppelin5/contracts/token/ERC721/IERC721.sol";

contract SocietyNftAuction is Ownable, ReentrancyGuard {
    address public constant SOCIETY_NFT = 0xBB5ED04dD7B207592429eb8d599d103CCad646c4;
    uint256 public constant AUCTION_DURATION = 3 days;
    uint256 public constant REFUND_GAS_STIPEND = 100_000;
    uint256 public constant MIN_GAS_BEFORE_REFUND = 175_000;
    uint256 private constant TEN_PERCENT_DENOMINATOR = 10;

    enum Lifecycle {
        Unstarted,
        Active,
        Settled
    }

    Lifecycle public lifecycle;
    uint256 public tokenId;
    uint256 public startTime;
    uint256 public endTime;
    address public highestBidder;
    uint256 public highestBid;
    uint256 public failedRefundDonations;
    address public settledRecipient;
    uint256 public withdrawableProceeds;

    bool private _expectingReceipt;
    bool private _receiptObserved;
    address private _expectedFrom;
    uint256 private _expectedTokenId;

    event AuctionStarted(uint256 indexed tokenId, uint256 startTime, uint256 endTime);
    event BidAccepted(address indexed bidder, uint256 amount);
    event BidRefunded(address indexed bidder, uint256 amount);
    event BidRefundDonated(address indexed bidder, uint256 amount);
    event AuctionSettled(address indexed recipient, uint256 winningBid, uint256 proceeds);
    event ProceedsWithdrawn(address indexed owner, uint256 amount);
    event ExcessSwept(address indexed owner, uint256 amount);

    error AlreadyStarted();
    error BiddingClosed();
    error BidTooLow();
    error InsufficientRefundGas();
    error NoExcess();
    error NoProceeds();
    error NotSettled();
    error NotApproved();
    error OwnershipRenunciationDisabled();
    error SettlementUnavailable();
    error TokenDoesNotExist(uint256 tokenId);
    error TokenOwnerMismatch(address expected, address actual);
    error UnexpectedEth();
    error UnexpectedNftReceipt();
    error ZeroAddress();

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert ZeroAddress();
        _initializeOwner(initialOwner);
    }

    receive() external payable {
        revert UnexpectedEth();
    }

    function start(uint256 selectedTokenId) external onlyOwner nonReentrant {
        if (lifecycle != Lifecycle.Unstarted) revert AlreadyStarted();

        address auctionOwner = owner();
        address currentOwner;
        try IERC721(SOCIETY_NFT).ownerOf(selectedTokenId) returns (address tokenOwner) {
            currentOwner = tokenOwner;
        } catch {
            revert TokenDoesNotExist(selectedTokenId);
        }
        if (currentOwner != auctionOwner) revert TokenOwnerMismatch(auctionOwner, currentOwner);

        bool approved = IERC721(SOCIETY_NFT).getApproved(selectedTokenId) == address(this)
            || IERC721(SOCIETY_NFT).isApprovedForAll(currentOwner, address(this));
        if (!approved) revert NotApproved();

        _expectingReceipt = true;
        _receiptObserved = false;
        _expectedFrom = currentOwner;
        _expectedTokenId = selectedTokenId;

        IERC721(SOCIETY_NFT).safeTransferFrom(currentOwner, address(this), selectedTokenId);

        if (!_receiptObserved) revert UnexpectedNftReceipt();
        address custodyOwner = IERC721(SOCIETY_NFT).ownerOf(selectedTokenId);
        if (custodyOwner != address(this)) revert TokenOwnerMismatch(address(this), custodyOwner);

        delete _expectingReceipt;
        delete _receiptObserved;
        delete _expectedFrom;
        delete _expectedTokenId;

        tokenId = selectedTokenId;
        startTime = block.timestamp;
        endTime = block.timestamp + AUCTION_DURATION;
        lifecycle = Lifecycle.Active;

        emit AuctionStarted(selectedTokenId, startTime, endTime);
    }

    function onERC721Received(address operator, address from, uint256 receivedTokenId, bytes calldata)
        external
        returns (bytes4)
    {
        if (
            msg.sender != SOCIETY_NFT || !_expectingReceipt || operator != address(this) || from != _expectedFrom
                || receivedTokenId != _expectedTokenId
        ) revert UnexpectedNftReceipt();

        _receiptObserved = true;
        return this.onERC721Received.selector;
    }

    function bid() external payable nonReentrant {
        if (msg.value < minimumNextBid()) revert BidTooLow();

        address priorBidder = highestBidder;
        uint256 priorBid = highestBid;

        highestBidder = msg.sender;
        highestBid = msg.value;
        emit BidAccepted(msg.sender, msg.value);

        if (priorBid == 0) return;
        if (gasleft() < MIN_GAS_BEFORE_REFUND) revert InsufficientRefundGas();

        bool refunded = SafeTransferLib.trySafeTransferETH(priorBidder, priorBid, REFUND_GAS_STIPEND);
        if (refunded) {
            emit BidRefunded(priorBidder, priorBid);
        } else {
            failedRefundDonations += priorBid;
            emit BidRefundDonated(priorBidder, priorBid);
        }
    }

    function minimumNextBid() public view returns (uint256) {
        if (lifecycle != Lifecycle.Active || block.timestamp >= endTime) revert BiddingClosed();

        uint256 currentBid = highestBid;
        if (currentBid == 0) return 1;

        uint256 increase = currentBid / TEN_PERCENT_DENOMINATOR;
        if (currentBid % TEN_PERCENT_DENOMINATOR != 0) ++increase;
        return currentBid + increase;
    }

    function settle() external nonReentrant {
        if (lifecycle != Lifecycle.Active || block.timestamp < endTime) revert SettlementUnavailable();

        address recipient = highestBidder == address(0) ? owner() : highestBidder;
        uint256 proceeds = highestBid + failedRefundDonations;

        lifecycle = Lifecycle.Settled;
        settledRecipient = recipient;
        withdrawableProceeds = proceeds;

        IERC721(SOCIETY_NFT).transferFrom(address(this), recipient, tokenId);

        emit AuctionSettled(recipient, highestBid, proceeds);
    }

    function withdrawProceeds() external onlyOwner nonReentrant {
        if (lifecycle != Lifecycle.Settled) revert NotSettled();
        uint256 amount = withdrawableProceeds;
        if (amount == 0) revert NoProceeds();

        withdrawableProceeds = 0;
        address currentOwner = owner();
        SafeTransferLib.safeTransferETH(currentOwner, amount);

        emit ProceedsWithdrawn(currentOwner, amount);
    }

    function sweepExcess() external onlyOwner nonReentrant {
        if (lifecycle != Lifecycle.Settled) revert NotSettled();
        uint256 amount = address(this).balance - withdrawableProceeds;
        if (amount == 0) revert NoExcess();

        address currentOwner = owner();
        SafeTransferLib.safeTransferETH(currentOwner, amount);

        emit ExcessSwept(currentOwner, amount);
    }

    function transferOwnership(address newOwner) public payable override onlyOwner nonReentrant {
        _rejectEth();
        super.transferOwnership(newOwner);
    }

    function renounceOwnership() public payable override onlyOwner {
        _rejectEth();
        revert OwnershipRenunciationDisabled();
    }

    function requestOwnershipHandover() public payable override {
        _rejectEth();
        super.requestOwnershipHandover();
    }

    function cancelOwnershipHandover() public payable override {
        _rejectEth();
        super.cancelOwnershipHandover();
    }

    function completeOwnershipHandover(address pendingOwner) public payable override onlyOwner nonReentrant {
        _rejectEth();
        super.completeOwnershipHandover(pendingOwner);
    }

    function _rejectEth() private view {
        if (msg.value != 0) revert UnexpectedEth();
    }
}
