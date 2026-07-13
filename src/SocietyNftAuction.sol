// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "solady/auth/Ownable.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IERC721} from "@openzeppelin5/contracts/token/ERC721/IERC721.sol";

// ============================================================================
//                    SOCIETY NFT ONE-OFF AUCTION
//                  Built with Love by Flick + ChatGPT
// ============================================================================

/// @title Society NFT One-Off Auction
/// @author Built with Love by Flick + ChatGPT
/// @notice Auctions one Society DN404 mirror NFT for native ETH over three days.
/// @dev This contract intentionally interacts only with the ERC-721 mirror. A successful
///      start is irreversible, only the current highest bid remains refundable, and a failed
///      refund becomes seller proceeds. Ownership carries every seller-side economic right.
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
    /// @notice Prior bids whose bounded refund attempts failed and became seller proceeds.
    uint256 public failedRefundDonations;
    address public settledRecipient;
    /// @notice Settled auction proceeds reserved from any forced ETH excess.
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

    /// @notice Atomically escrows the selected NFT and opens the one-time auction.
    /// @dev The caller must own and approve the token. After success there is no cancellation,
    ///      pause, extension, restart, or unrelated-NFT rescue path.
    /// @param selectedTokenId The Society mirror token to auction.
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
        // Accept only the exact transfer initiated inside start(); unsolicited NFTs are rejected.
        if (
            msg.sender != SOCIETY_NFT || !_expectingReceipt || operator != address(this) || from != _expectedFrom
                || receivedTokenId != _expectedTokenId
        ) revert UnexpectedNftReceipt();

        _receiptObserved = true;
        return this.onERC721Received.selector;
    }

    /// @notice Places a full replacement bid; this is never an incremental top-up.
    /// @dev The current leader may outbid themselves. The displaced bid receives the same bounded
    ///      refund attempt regardless of bidder identity; failure irrevocably donates that bid.
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

    /// @notice Returns the lowest bid currently accepted by `bid()`.
    /// @dev Reverts outside the active bidding window. The 10% increase is rounded up to wei.
    /// @return One wei for the first bid, otherwise `highestBid + ceil(highestBid / 10)`.
    function minimumNextBid() public view returns (uint256) {
        if (lifecycle != Lifecycle.Active || block.timestamp >= endTime) revert BiddingClosed();

        uint256 currentBid = highestBid;
        if (currentBid == 0) return 1;

        uint256 increase = currentBid / TEN_PERCENT_DENOMINATOR;
        if (currentBid % TEN_PERCENT_DENOMINATOR != 0) ++increase;
        return currentBid + increase;
    }

    /// @notice Finalizes the auction after its deadline; callable by anyone.
    /// @dev Uses callback-free ERC-721 transfer semantics so a contract winner cannot veto
    ///      settlement by rejecting `onERC721Received`.
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

    /// @notice Pays the final winning bid plus failed-refund donations to the current owner.
    /// @dev A failed ETH transfer reverts without consuming the owner's claim.
    function withdrawProceeds() external onlyOwner nonReentrant {
        if (lifecycle != Lifecycle.Settled) revert NotSettled();
        uint256 amount = withdrawableProceeds;
        if (amount == 0) revert NoProceeds();

        withdrawableProceeds = 0;
        address currentOwner = owner();
        SafeTransferLib.safeTransferETH(currentOwner, amount);

        emit ProceedsWithdrawn(currentOwner, amount);
    }

    /// @notice Withdraws forced ETH after settlement without consuming reserved proceeds.
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
        // A permanent nonzero owner is required for NFT return and proceeds recovery.
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
