// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721Receiver} from "@openzeppelin5/contracts/token/ERC721/IERC721Receiver.sol";

interface ISocietyNftAuctionActions {
    function bid() external payable;
    function withdrawProceeds() external;
    function sweepExcess() external;
    function transferOwnership(address newOwner) external payable;
}

contract MockSocietyNftMirror {
    enum CallbackMode {
        Valid,
        WrongOperator,
        WrongFrom,
        WrongTokenId,
        MissingCallback
    }

    mapping(uint256 => address) internal _owners;
    mapping(uint256 => address) internal _approvals;
    mapping(address => mapping(address => bool)) internal _operators;
    CallbackMode public callbackMode;
    bool public failTransfers;

    error NotAuthorized();
    error NonexistentToken();
    error UnsafeRecipient();
    error WrongOwner();
    error ZeroAddress();

    function mint(address to, uint256 tokenId) external {
        if (to == address(0)) revert ZeroAddress();
        if (_owners[tokenId] != address(0)) revert WrongOwner();
        _owners[tokenId] = to;
    }

    function setCallbackMode(CallbackMode mode) external {
        callbackMode = mode;
    }

    function setFailTransfers(bool fail) external {
        failTransfers = fail;
    }

    function ownerOf(uint256 tokenId) external view returns (address tokenOwner) {
        tokenOwner = _owners[tokenId];
        if (tokenOwner == address(0)) revert NonexistentToken();
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        if (_owners[tokenId] == address(0)) revert NonexistentToken();
        return _approvals[tokenId];
    }

    function isApprovedForAll(address tokenOwner, address operator) external view returns (bool) {
        return _operators[tokenOwner][operator];
    }

    function approve(address spender, uint256 tokenId) external {
        address tokenOwner = _owners[tokenId];
        if (msg.sender != tokenOwner && !_operators[tokenOwner][msg.sender]) revert NotAuthorized();
        _approvals[tokenId] = spender;
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operators[msg.sender][operator] = approved;
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        if (failTransfers) revert UnsafeRecipient();
        address tokenOwner = _owners[tokenId];
        if (tokenOwner == address(0)) revert NonexistentToken();
        if (tokenOwner != from) revert WrongOwner();
        if (to == address(0)) revert ZeroAddress();
        if (msg.sender != from && _approvals[tokenId] != msg.sender && !_operators[from][msg.sender]) {
            revert NotAuthorized();
        }
        _owners[tokenId] = to;
        delete _approvals[tokenId];
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        transferFrom(from, to, tokenId);
        if (to.code.length != 0) {
            if (callbackMode == CallbackMode.MissingCallback) return;
            address operator = callbackMode == CallbackMode.WrongOperator ? address(0xBEEF) : msg.sender;
            address callbackFrom = callbackMode == CallbackMode.WrongFrom ? address(0xCAFE) : from;
            uint256 callbackTokenId = callbackMode == CallbackMode.WrongTokenId ? tokenId + 1 : tokenId;
            bytes4 result = IERC721Receiver(to).onERC721Received(operator, callbackFrom, callbackTokenId, "");
            if (result != IERC721Receiver.onERC721Received.selector) revert UnsafeRecipient();
        }
    }
}

contract RejectingEthOwner {
    function withdraw(address auction) external {
        ISocietyNftAuctionActions(auction).withdrawProceeds();
    }

    function sweep(address auction) external {
        ISocietyNftAuctionActions(auction).sweepExcess();
    }

    function transferAuctionOwnership(address auction, address newOwner) external {
        ISocietyNftAuctionActions(auction).transferOwnership(newOwner);
    }

    receive() external payable {
        revert();
    }
}

contract AuctionBidder {
    enum RefundMode {
        Accept,
        Reject,
        BurnGas,
        Reenter
    }

    RefundMode public refundMode;
    address public auction;
    bytes public reentryCall;
    uint256 public reentryValue;
    bool public reentrySucceeded;
    uint256 public refundGasAtEntry;

    function configure(RefundMode mode, address auction_, bytes calldata reentryCall_) external {
        refundMode = mode;
        auction = auction_;
        reentryCall = reentryCall_;
        reentryValue = 0;
        reentrySucceeded = false;
    }

    function configureReentry(address auction_, bytes calldata reentryCall_, uint256 value) external {
        refundMode = RefundMode.Reenter;
        auction = auction_;
        reentryCall = reentryCall_;
        reentryValue = value;
        reentrySucceeded = false;
    }

    function placeBid(address auction_) external payable {
        ISocietyNftAuctionActions(auction_).bid{value: msg.value}();
    }

    receive() external payable {
        refundGasAtEntry = gasleft();
        if (refundMode == RefundMode.Reject) revert();
        if (refundMode == RefundMode.BurnGas) {
            while (gasleft() > 5_000) {}
            revert();
        }
        if (refundMode == RefundMode.Reenter) {
            (reentrySucceeded,) = auction.call{value: reentryValue}(reentryCall);
        }
    }
}

contract ForceEth {
    constructor() payable {}

    function force(address payable target) external {
        selfdestruct(target);
    }
}
