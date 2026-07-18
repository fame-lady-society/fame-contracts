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

    enum FulfillmentPath {
        Held,
        MintPool,
        BurnPool
    }

    struct PoolPurchase {
        address buyer;
        address recipient;
        address feeRecipient;
        uint256 shellId;
        uint256 sourceId;
        uint256 premiumAmount;
        uint256 inventoryBefore;
        bytes32 artworkHash;
        bytes32 displacedArtworkHash;
        FulfillmentPath path;
    }

    event PremiumUpdated(uint256 previousPremium, uint256 newPremium);
    event FeeRecipientUpdated(address indexed previousRecipient, address indexed newRecipient);
    event MarketPaused(address indexed account);
    event MarketUnpaused(address indexed account);
    event ArtworkPurchased(
        address indexed buyer,
        address indexed recipient,
        uint256 indexed shellId,
        FulfillmentPath path,
        uint256 sourceId,
        bytes32 artwork,
        uint256 unitAmount,
        uint256 premiumAmount,
        uint256 inventoryBefore,
        uint256 inventoryAfter
    );
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
    error InvalidRecipient();
    error PremiumExceedsMaximum(uint256 currentPremium, uint256 maximumPremium);
    error UnavailableShell(uint256 shellId);
    error ArtworkMismatch(uint256 tokenId, bytes32 expected, bytes32 actual);
    error PaymentTransferFailed();
    error BuyerMirrorBalanceTooLow(uint256 minimum, uint256 actual);
    error InventoryInvariantBroken(uint256 beforeBalance, uint256 afterBalance);
    error SourceEqualsShell(uint256 tokenId);
    error ArtPoolSourceExcluded(uint256 sourceId);
    error IneligiblePoolSource(uint256 sourceId);
    error AmbiguousPoolSource(uint256 sourceId);

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

    function purchaseHeld(
        uint256 shellId,
        bytes32 expectedArtworkHash,
        uint256 maxPremium,
        uint256 minBuyerMirrorBalanceAfter,
        address recipient
    ) external nonReentrant returns (uint256 inventoryBefore, uint256 inventoryAfter) {
        if (paused) revert PurchasesPaused();
        if (recipient == address(0)) revert InvalidRecipient();

        uint256 currentPremium = premium;
        if (currentPremium > maxPremium) {
            revert PremiumExceedsMaximum(currentPremium, maxPremium);
        }

        _requireStack();
        _requireShellArtwork(shellId, expectedArtworkHash);
        address currentFeeRecipient = feeRecipient;
        _requireFeeRecipient(currentFeeRecipient);
        inventoryBefore = inventory();

        _enterSettlement();
        _pullPremium(msg.sender, currentFeeRecipient, currentPremium);

        _requireStack();
        _requireShellArtwork(shellId, expectedArtworkHash);

        uint256 unitAmount = fame.unit();
        _pullFame(msg.sender, address(this), unitAmount);

        _requireStack();
        _requireShellArtwork(shellId, expectedArtworkHash);
        mirror.safeTransferFrom(address(this), recipient, shellId);

        uint256 buyerMirrorBalance = mirror.balanceOf(msg.sender);
        if (buyerMirrorBalance < minBuyerMirrorBalanceAfter) {
            revert BuyerMirrorBalanceTooLow(minBuyerMirrorBalanceAfter, buyerMirrorBalance);
        }

        inventoryAfter = inventory();
        if (inventoryAfter < inventoryBefore) {
            revert InventoryInvariantBroken(inventoryBefore, inventoryAfter);
        }
        _exitSettlement();

        emit ArtworkPurchased(
            msg.sender,
            recipient,
            shellId,
            FulfillmentPath.Held,
            0,
            expectedArtworkHash,
            unitAmount,
            currentPremium,
            inventoryBefore,
            inventoryAfter
        );
    }

    function purchasePool(
        uint256 shellId,
        uint256 sourceId,
        bytes32 expectedArtworkHash,
        uint256 maxPremium,
        uint256 minBuyerMirrorBalanceAfter,
        address recipient
    ) external nonReentrant returns (uint256 inventoryBefore, uint256 inventoryAfter) {
        if (paused) revert PurchasesPaused();
        if (recipient == address(0)) revert InvalidRecipient();
        if (sourceId == shellId) revert SourceEqualsShell(sourceId);

        PoolPurchase memory purchase;
        purchase.premiumAmount = premium;
        if (purchase.premiumAmount > maxPremium) {
            revert PremiumExceedsMaximum(purchase.premiumAmount, maxPremium);
        }

        _requireStack();
        _requireShell(shellId);
        purchase.path = _requirePoolSource(sourceId);
        _requireArtwork(sourceId, expectedArtworkHash);
        purchase.buyer = msg.sender;
        purchase.recipient = recipient;
        purchase.feeRecipient = feeRecipient;
        purchase.shellId = shellId;
        purchase.sourceId = sourceId;
        purchase.artworkHash = expectedArtworkHash;
        purchase.displacedArtworkHash = artworkHash(shellId);
        purchase.inventoryBefore = inventory();
        _requireFeeRecipient(purchase.feeRecipient);

        return _executePoolPurchase(purchase, minBuyerMirrorBalanceAfter);
    }

    function _executePoolPurchase(PoolPurchase memory purchase, uint256 minBuyerMirrorBalanceAfter)
        internal
        returns (uint256 inventoryBefore, uint256 inventoryAfter)
    {
        _enterSettlement();
        _pullPremium(purchase.buyer, purchase.feeRecipient, purchase.premiumAmount);

        _requireStack();
        _requireShell(purchase.shellId);
        if (_requirePoolSource(purchase.sourceId) != purchase.path) {
            revert IneligiblePoolSource(purchase.sourceId);
        }
        _requireArtwork(purchase.sourceId, purchase.artworkHash);
        _requireArtwork(purchase.shellId, purchase.displacedArtworkHash);

        if (purchase.path == FulfillmentPath.MintPool) {
            creatorMagic.banishToMintPool(purchase.shellId, purchase.sourceId);
        } else {
            creatorMagic.banishToBurnPool(purchase.shellId, purchase.sourceId);
        }
        _requireArtwork(purchase.shellId, purchase.artworkHash);
        _requireArtwork(purchase.sourceId, purchase.displacedArtworkHash);

        uint256 unitAmount = fame.unit();
        _pullFame(purchase.buyer, address(this), unitAmount);

        _requireStack();
        _requireShellArtwork(purchase.shellId, purchase.artworkHash);
        _requireArtwork(purchase.sourceId, purchase.displacedArtworkHash);
        mirror.safeTransferFrom(address(this), purchase.recipient, purchase.shellId);

        uint256 buyerMirrorBalance = mirror.balanceOf(purchase.buyer);
        if (buyerMirrorBalance < minBuyerMirrorBalanceAfter) {
            revert BuyerMirrorBalanceTooLow(minBuyerMirrorBalanceAfter, buyerMirrorBalance);
        }

        inventoryAfter = inventory();
        if (inventoryAfter < purchase.inventoryBefore) {
            revert InventoryInvariantBroken(purchase.inventoryBefore, inventoryAfter);
        }
        _exitSettlement();

        emit ArtworkPurchased(
            purchase.buyer,
            purchase.recipient,
            purchase.shellId,
            purchase.path,
            purchase.sourceId,
            purchase.artworkHash,
            unitAmount,
            purchase.premiumAmount,
            purchase.inventoryBefore,
            inventoryAfter
        );
        inventoryBefore = purchase.inventoryBefore;
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

    function _requireStack() internal view {
        if (
            address(creatorMagic.fame()) != address(fame) || address(fame.fameMirror()) != address(mirror)
                || address(fame.renderer()) != address(creatorMagic)
        ) {
            revert StackMismatch();
        }
    }

    function _requireShellArtwork(uint256 shellId, bytes32 expectedArtworkHash) internal view {
        _requireShell(shellId);
        _requireArtwork(shellId, expectedArtworkHash);
    }

    function _requireShell(uint256 shellId) internal view {
        if (mirror.ownerAt(shellId) != address(this)) revert UnavailableShell(shellId);
    }

    function _requireArtwork(uint256 tokenId, bytes32 expectedArtworkHash) internal view {
        bytes32 actualArtworkHash = artworkHash(tokenId);
        if (actualArtworkHash != expectedArtworkHash) {
            revert ArtworkMismatch(tokenId, expectedArtworkHash, actualArtworkHash);
        }
    }

    function _requirePoolSource(uint256 sourceId) internal view returns (FulfillmentPath path) {
        if (sourceId >= creatorMagic.artPoolStartIndex() && sourceId <= creatorMagic.artPoolEndIndex()) {
            revert ArtPoolSourceExcluded(sourceId);
        }

        bool mintEligible = creatorMagic.isTokenInMintPool(sourceId);
        bool burnEligible = creatorMagic.isTokenInBurnedPool(sourceId);
        if (mintEligible && burnEligible) revert AmbiguousPoolSource(sourceId);
        if (mintEligible) return FulfillmentPath.MintPool;
        if (burnEligible) return FulfillmentPath.BurnPool;
        revert IneligiblePoolSource(sourceId);
    }

    function _pullPremium(address buyer, address recipient, uint256 amount) internal {
        if (buyer == recipient) return;
        _requireFeeRecipient(recipient);
        _pullFame(buyer, recipient, amount);
    }

    function _pullFame(address from, address to, uint256 amount) internal {
        if (!fame.transferFrom(from, to, amount)) revert PaymentTransferFailed();
    }

    function _enterSettlement() internal {
        if (_settlementActive) revert SettlementInProgress();
        _settlementActive = true;
    }

    function _exitSettlement() internal {
        _settlementActive = false;
    }

    function _requireContract(address dependency) private view {
        if (dependency == address(0) || dependency.code.length == 0) {
            revert InvalidDependency(dependency);
        }
    }
}
