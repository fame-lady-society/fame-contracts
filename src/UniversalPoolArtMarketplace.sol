// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "solady/auth/Ownable.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {CreatorArtistMagic} from "./CreatorArtistMagic.sol";
import {Fame} from "./Fame.sol";
import {FameMirror} from "./FameMirror.sol";

interface IERC721MarketplaceRescue {
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

contract UniversalPoolArtMarketplace is Ownable, ReentrancyGuard {
    using SafeTransferLib for address;

    bytes4 private constant ERC721_RECEIVED = 0x150b7a02;

    Fame public immutable fame;
    FameMirror public immutable mirror;
    CreatorArtistMagic public immutable creatorMagic;

    uint96 public premium;
    address public feeRecipient;
    bool public paused = true;

    bool internal _settlementActive;

    event PremiumUpdated(uint256 previousPremium, uint256 newPremium);
    event FeeRecipientUpdated(address indexed previousRecipient, address indexed newRecipient);
    event MarketPaused(address indexed account);
    event MarketUnpaused(address indexed account);
    event RescueERC20(address indexed token, address indexed to, uint256 amount);
    event RescueERC721(address indexed token, address indexed to, uint256 indexed tokenId);

    error ZeroAddress();
    error InvalidDependency(address dependency);
    error StackMismatch();
    error ZeroPremium();
    error PremiumTooLarge(uint256 premium);
    error InvalidFeeRecipient(address recipient);
    error FeeRecipientNotSkippingNFT(address recipient);
    error PurchasesPaused();
    error MarketNotPaused();
    error MarketAlreadyPaused();
    error SettlementInProgress();
    error OwnershipRenunciationDisabled();
    error UnsupportedNFT(address token);
    error CoreAssetRescueBlocked();

    modifier noActiveSettlement() {
        if (_settlementActive) revert SettlementInProgress();
        _;
    }

    modifier onlyPaused() {
        if (!paused) revert MarketNotPaused();
        _;
    }

    constructor(
        address payable fame_,
        address creatorMagic_,
        uint256 initialPremium,
        address initialFeeRecipient,
        address initialOwner
    ) payable {
        if (initialOwner == address(0)) revert ZeroAddress();
        _requireContract(fame_);
        _requireContract(creatorMagic_);
        _requirePremium(initialPremium);

        Fame fameContract = Fame(fame_);
        FameMirror mirrorContract = fameContract.fameMirror();
        _requireContract(address(mirrorContract));

        CreatorArtistMagic creatorMagicContract = CreatorArtistMagic(creatorMagic_);
        if (address(creatorMagicContract.fame()) != fame_ || address(fameContract.renderer()) != creatorMagic_) {
            revert StackMismatch();
        }

        fame = fameContract;
        mirror = mirrorContract;
        creatorMagic = creatorMagicContract;

        _requireFeeRecipient(initialFeeRecipient);
        premium = uint96(initialPremium);
        feeRecipient = initialFeeRecipient;

        fameContract.setSkipNFT(false);
        _initializeOwner(initialOwner);

        emit PremiumUpdated(0, initialPremium);
        emit FeeRecipientUpdated(address(0), initialFeeRecipient);
        emit MarketPaused(msg.sender);
    }

    function inventory() public view returns (uint256) {
        return mirror.balanceOf(address(this));
    }

    function artworkHash(uint256 tokenId) public view returns (bytes32) {
        return keccak256(bytes(creatorMagic.tokenURI(tokenId)));
    }

    function setPremium(uint256 newPremium) external onlyOwner noActiveSettlement {
        _requirePremium(newPremium);
        uint256 previousPremium = premium;
        premium = uint96(newPremium);
        emit PremiumUpdated(previousPremium, newPremium);
    }

    function setFeeRecipient(address newFeeRecipient) external onlyOwner noActiveSettlement {
        _requireFeeRecipient(newFeeRecipient);
        address previousRecipient = feeRecipient;
        feeRecipient = newFeeRecipient;
        emit FeeRecipientUpdated(previousRecipient, newFeeRecipient);
    }

    function pause() external onlyOwner noActiveSettlement {
        if (paused) revert MarketAlreadyPaused();
        paused = true;
        emit MarketPaused(msg.sender);
    }

    function unpause() external onlyOwner noActiveSettlement {
        if (!paused) revert MarketNotPaused();
        paused = false;
        emit MarketUnpaused(msg.sender);
    }

    function transferOwnership(address newOwner) public payable override onlyOwner noActiveSettlement {
        super.transferOwnership(newOwner);
    }

    function renounceOwnership() public payable override {
        revert OwnershipRenunciationDisabled();
    }

    function requestOwnershipHandover() public payable override noActiveSettlement {
        super.requestOwnershipHandover();
    }

    function cancelOwnershipHandover() public payable override noActiveSettlement {
        super.cancelOwnershipHandover();
    }

    function completeOwnershipHandover(address pendingOwner) public payable override onlyOwner noActiveSettlement {
        super.completeOwnershipHandover(pendingOwner);
    }

    function rescueERC20(address token, address to, uint256 amount)
        external
        onlyOwner
        nonReentrant
        noActiveSettlement
        onlyPaused
    {
        if (token == address(0) || to == address(0)) revert ZeroAddress();
        if (token == address(fame)) revert CoreAssetRescueBlocked();
        token.safeTransfer(to, amount);
        emit RescueERC20(token, to, amount);
    }

    function rescueERC721(address token, address to, uint256 tokenId)
        external
        onlyOwner
        nonReentrant
        noActiveSettlement
        onlyPaused
    {
        if (token == address(0) || to == address(0)) revert ZeroAddress();
        if (token == address(mirror)) revert CoreAssetRescueBlocked();
        IERC721MarketplaceRescue(token).safeTransferFrom(address(this), to, tokenId);
        emit RescueERC721(token, to, tokenId);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        if (msg.sender != address(mirror)) revert UnsupportedNFT(msg.sender);
        return ERC721_RECEIVED;
    }

    function _requirePremium(uint256 candidate) internal pure {
        if (candidate == 0) revert ZeroPremium();
        if (candidate > type(uint96).max) revert PremiumTooLarge(candidate);
    }

    function _requireFeeRecipient(address candidate) internal view {
        if (candidate == address(0) || candidate == address(this)) {
            revert InvalidFeeRecipient(candidate);
        }
        if (!fame.getSkipNFT(candidate)) revert FeeRecipientNotSkippingNFT(candidate);
    }

    function _requireContract(address dependency) private view {
        if (dependency == address(0) || dependency.code.length == 0) {
            revert InvalidDependency(dependency);
        }
    }
}
