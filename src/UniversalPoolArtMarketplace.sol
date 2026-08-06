// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "solady/auth/Ownable.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IERC721} from "@openzeppelin5/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin5/contracts/token/ERC721/IERC721Receiver.sol";
import {CreatorArtistMagic} from "./CreatorArtistMagic.sol";
import {Fame} from "./Fame.sol";
import {FameMirror} from "./FameMirror.sol";

contract UniversalPoolArtMarketplace is Ownable, ReentrancyGuard {
    using SafeTransferLib for address;

    uint256 internal constant SOCIETY_TOKEN_ID_START = 1;
    uint256 internal constant SOCIETY_TOKEN_ID_COUNT = 888;
    uint256 public constant MAX_INVENTORY_BATCH_SIZE = 8;

    Fame public immutable fame;
    FameMirror public immutable mirror;
    CreatorArtistMagic public immutable creatorMagic;

    uint96 public communityFee;
    uint96 public providerFee;
    address public feeRecipient;
    address public authorizedCheckout;
    uint256 public immutable activeProviderCap;
    uint256 public totalProviderUnits;
    uint256 public withdrawalNonce;
    uint256 public withdrawalCursor;
    bool public paused = true;

    bool internal _settlementActive;

    struct ProviderPosition {
        uint32 unitCount;
        uint32 indexPlusOne;
    }

    mapping(address => ProviderPosition) internal _providerPositions;
    address[] internal _activeProviders;

    enum FulfillmentPath {
        Held,
        MintPool,
        BurnPool
    }

    struct PoolPurchase {
        address payer;
        address buyer;
        address recipient;
        uint256 shellId;
        uint256 sourceId;
        uint256 premiumAmount;
        uint256 inventoryBefore;
        bytes32 artworkHash;
        bytes32 displacedArtworkHash;
        FulfillmentPath path;
    }

    event CommunityFeeUpdated(uint256 previousFee, uint256 newFee);
    event ProviderFeeUpdated(uint256 previousFee, uint256 newFee);
    event FeeRecipientUpdated(address indexed previousRecipient, address indexed newRecipient);
    event AuthorizedCheckoutChanged(address indexed previousCheckout, address indexed newCheckout);
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
    event InventoryDeposited(address indexed provider, uint256 indexed tokenId, uint256 providerUnits);
    event InventoryBatchDeposited(address indexed provider, uint256[] tokenIds, uint256 providerUnits);
    event InventoryWithdrawn(
        address indexed provider,
        uint256 indexed tokenId,
        bool selected,
        uint256 providerUnits,
        uint256 premiumAmount,
        uint256 scanSteps
    );

    error ZeroAddress();
    error InvalidDependency(address dependency);
    error StackMismatch();
    error FeeTooLarge(uint256 fee, uint256 maximum);
    error InvalidActiveProviderCap(uint256 cap);
    error InvalidInventoryBatchSize(uint256 size, uint256 maximum);
    error DuplicateInventoryToken(uint256 tokenId);
    error ActiveProviderCapReached(uint256 cap);
    error NoProviderPosition(address provider);
    error NoPooledInventory();
    error InvalidFeeRecipient(address recipient);
    error PurchasesPaused();
    error MarketNotPaused();
    error MarketAlreadyPaused();
    error SettlementInProgress();
    error OwnershipRenunciationDisabled();
    error UnsupportedNFT(address token);
    error CoreAssetRescueBlocked();
    error InvalidRecipient();
    error UnauthorizedCheckout(address caller);
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

    modifier onlyAuthorizedCheckout() {
        if (msg.sender != authorizedCheckout) revert UnauthorizedCheckout(msg.sender);
        _;
    }

    constructor(
        address payable fame_,
        address creatorMagic_,
        uint256 initialCommunityFee,
        uint256 initialProviderFee,
        address initialFeeRecipient,
        address initialOwner,
        uint256 activeProviderCap_
    ) {
        if (initialOwner == address(0)) revert ZeroAddress();
        _requireContract(fame_);
        _requireContract(creatorMagic_);

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

        if (activeProviderCap_ == 0 || activeProviderCap_ > SOCIETY_TOKEN_ID_COUNT) {
            revert InvalidActiveProviderCap(activeProviderCap_);
        }
        activeProviderCap = activeProviderCap_;

        _requireFee(initialCommunityFee);
        _requireFee(initialProviderFee);

        _requireFeeRecipient(initialFeeRecipient);
        communityFee = uint96(initialCommunityFee);
        providerFee = uint96(initialProviderFee);
        feeRecipient = initialFeeRecipient;

        fameContract.setSkipNFT(false);
        _initializeOwner(initialOwner);

        emit CommunityFeeUpdated(0, initialCommunityFee);
        emit ProviderFeeUpdated(0, initialProviderFee);
        emit FeeRecipientUpdated(address(0), initialFeeRecipient);
        emit MarketPaused(msg.sender);
    }

    function inventory() public view returns (uint256) {
        return mirror.balanceOf(address(this));
    }

    function premium() public view returns (uint256) {
        return uint256(communityFee) + uint256(providerFee);
    }

    function providerPosition(address provider) external view returns (uint256 unitCount, uint256 indexPlusOne) {
        ProviderPosition memory position = _providerPositions[provider];
        return (position.unitCount, position.indexPlusOne);
    }

    function activeProviderCount() public view returns (uint256) {
        return _activeProviders.length;
    }

    function activeProviderAt(uint256 index) external view returns (address) {
        return _activeProviders[index];
    }

    function artworkHash(uint256 tokenId) public view returns (bytes32) {
        return keccak256(bytes(creatorMagic.tokenURI(tokenId)));
    }

    function setCommunityFee(uint256 newFee) external onlyOwner noActiveSettlement {
        _requireFee(newFee);
        uint256 previousFee = communityFee;
        communityFee = uint96(newFee);
        emit CommunityFeeUpdated(previousFee, newFee);
    }

    function setProviderFee(uint256 newFee) external onlyOwner noActiveSettlement {
        _requireFee(newFee);
        uint256 previousFee = providerFee;
        providerFee = uint96(newFee);
        emit ProviderFeeUpdated(previousFee, newFee);
    }

    /// @dev `buyer` is retained for ABI stability; charge does not depend on buyer identity.
    function purchaseCharge(address) external view returns (uint256) {
        return fame.unit() + uint256(providerFee) + uint256(communityFee);
    }

    function depositInventory(uint256 tokenId) external nonReentrant {
        _requireInventoryTokenId(tokenId);
        ProviderPosition storage position = _providerPositionForDeposit(msg.sender);
        _enterSettlement();
        _transferInventoryToken(msg.sender, tokenId);
        ++position.unitCount;
        ++totalProviderUnits;
        _exitSettlement();

        emit InventoryDeposited(msg.sender, tokenId, position.unitCount);
    }

    function depositInventoryBatch(uint256[] calldata tokenIds) external nonReentrant {
        uint256 count = tokenIds.length;
        if (count == 0 || count > MAX_INVENTORY_BATCH_SIZE) {
            revert InvalidInventoryBatchSize(count, MAX_INVENTORY_BATCH_SIZE);
        }

        for (uint256 i; i < count; ++i) {
            uint256 tokenId = tokenIds[i];
            _requireInventoryTokenId(tokenId);
            for (uint256 j; j < i; ++j) {
                if (tokenIds[j] == tokenId) revert DuplicateInventoryToken(tokenId);
            }
        }

        ProviderPosition storage position = _providerPositionForDeposit(msg.sender);
        uint256 resultingProviderUnits = uint256(position.unitCount) + count;
        _enterSettlement();
        for (uint256 i; i < count; ++i) {
            _transferInventoryToken(msg.sender, tokenIds[i]);
        }
        position.unitCount = uint32(resultingProviderUnits);
        totalProviderUnits += count;
        _exitSettlement();

        emit InventoryBatchDeposited(msg.sender, tokenIds, resultingProviderUnits);
    }

    function withdrawInventory() external nonReentrant returns (uint256 tokenId) {
        ProviderPosition storage position = _providerPositions[msg.sender];
        if (position.unitCount == 0) revert NoProviderPosition(msg.sender);

        uint256 nonce = withdrawalNonce++;
        uint256 startOffset = uint256(keccak256(abi.encode(block.prevrandao, msg.sender, nonce, withdrawalCursor)))
            % SOCIETY_TOKEN_ID_COUNT;
        uint256 scanSteps;
        uint256 candidate = SOCIETY_TOKEN_ID_START + startOffset;
        for (uint256 offset; offset < SOCIETY_TOKEN_ID_COUNT; ++offset) {
            if (mirror.ownerAt(candidate) == address(this)) {
                tokenId = candidate;
                scanSteps = offset + 1;
                withdrawalCursor = candidate;
                break;
            }
            ++candidate;
            if (candidate == SOCIETY_TOKEN_ID_START + SOCIETY_TOKEN_ID_COUNT) {
                candidate = SOCIETY_TOKEN_ID_START;
            }
        }
        if (tokenId == 0) revert NoPooledInventory();

        _enterSettlement();
        uint256 remainingUnits = _removeProviderUnit(msg.sender);
        mirror.safeTransferFrom(address(this), msg.sender, tokenId);
        _exitSettlement();

        emit InventoryWithdrawn(msg.sender, tokenId, false, remainingUnits, 0, scanSteps);
    }

    function withdrawInventorySelected(uint256 tokenId, uint256 maxPremium) external nonReentrant {
        if (_providerPositions[msg.sender].unitCount == 0) revert NoProviderPosition(msg.sender);
        if (mirror.ownerAt(tokenId) != address(this)) revert UnavailableShell(tokenId);

        uint256 currentPremium = premium();
        if (currentPremium > maxPremium) revert PremiumExceedsMaximum(currentPremium, maxPremium);

        _enterSettlement();
        uint256 remainingUnits = _removeProviderUnit(msg.sender);
        _distributePremium(msg.sender, msg.sender);
        mirror.safeTransferFrom(address(this), msg.sender, tokenId);
        _exitSettlement();

        emit InventoryWithdrawn(msg.sender, tokenId, true, remainingUnits, currentPremium, 0);
    }

    function setFeeRecipient(address newFeeRecipient) external onlyOwner noActiveSettlement {
        _requireFeeRecipient(newFeeRecipient);
        address previousRecipient = feeRecipient;
        feeRecipient = newFeeRecipient;
        emit FeeRecipientUpdated(previousRecipient, newFeeRecipient);
    }

    function setAuthorizedCheckout(address newCheckout) external onlyOwner noActiveSettlement onlyPaused {
        if (newCheckout != address(0)) _requireContract(newCheckout);
        address previousCheckout = authorizedCheckout;
        authorizedCheckout = newCheckout;
        emit AuthorizedCheckoutChanged(previousCheckout, newCheckout);
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
        return _purchaseHeld(
            msg.sender, msg.sender, recipient, shellId, expectedArtworkHash, maxPremium, minBuyerMirrorBalanceAfter
        );
    }

    function purchaseHeldFor(
        address buyer,
        uint256 shellId,
        bytes32 expectedArtworkHash,
        uint256 maxPremium,
        uint256 minBuyerMirrorBalanceAfter
    ) external onlyAuthorizedCheckout nonReentrant returns (uint256 inventoryBefore, uint256 inventoryAfter) {
        return
            _purchaseHeld(
                msg.sender, buyer, buyer, shellId, expectedArtworkHash, maxPremium, minBuyerMirrorBalanceAfter
            );
    }

    function _purchaseHeld(
        address payer,
        address buyer,
        address recipient,
        uint256 shellId,
        bytes32 expectedArtworkHash,
        uint256 maxPremium,
        uint256 minBuyerMirrorBalanceAfter
    ) internal returns (uint256 inventoryBefore, uint256 inventoryAfter) {
        if (paused) revert PurchasesPaused();
        if (buyer == address(0) || recipient == address(0)) revert InvalidRecipient();

        uint256 currentPremium = premium();
        if (currentPremium > maxPremium) {
            revert PremiumExceedsMaximum(currentPremium, maxPremium);
        }

        _requireStack();
        _requireShellArtwork(shellId, expectedArtworkHash);
        inventoryBefore = inventory();

        _enterSettlement();
        _distributePremium(payer, address(0));

        _requireStack();
        _requireShellArtwork(shellId, expectedArtworkHash);

        uint256 unitAmount = fame.unit();
        _pullFame(payer, address(this), unitAmount);

        _requireStack();
        _requireShellArtwork(shellId, expectedArtworkHash);
        mirror.safeTransferFrom(address(this), recipient, shellId);

        uint256 buyerMirrorBalance = mirror.balanceOf(buyer);
        if (buyerMirrorBalance < minBuyerMirrorBalanceAfter) {
            revert BuyerMirrorBalanceTooLow(minBuyerMirrorBalanceAfter, buyerMirrorBalance);
        }

        inventoryAfter = inventory();
        if (inventoryAfter < inventoryBefore) {
            revert InventoryInvariantBroken(inventoryBefore, inventoryAfter);
        }
        _exitSettlement();

        emit ArtworkPurchased(
            buyer,
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
        return _purchasePool(
            msg.sender,
            msg.sender,
            recipient,
            shellId,
            sourceId,
            expectedArtworkHash,
            maxPremium,
            minBuyerMirrorBalanceAfter
        );
    }

    function purchasePoolFor(
        address buyer,
        uint256 shellId,
        uint256 sourceId,
        bytes32 expectedArtworkHash,
        uint256 maxPremium,
        uint256 minBuyerMirrorBalanceAfter
    ) external onlyAuthorizedCheckout nonReentrant returns (uint256 inventoryBefore, uint256 inventoryAfter) {
        return _purchasePool(
            msg.sender, buyer, buyer, shellId, sourceId, expectedArtworkHash, maxPremium, minBuyerMirrorBalanceAfter
        );
    }

    function _purchasePool(
        address payer,
        address buyer,
        address recipient,
        uint256 shellId,
        uint256 sourceId,
        bytes32 expectedArtworkHash,
        uint256 maxPremium,
        uint256 minBuyerMirrorBalanceAfter
    ) internal returns (uint256 inventoryBefore, uint256 inventoryAfter) {
        if (paused) revert PurchasesPaused();
        if (buyer == address(0) || recipient == address(0)) revert InvalidRecipient();
        if (sourceId == shellId) revert SourceEqualsShell(sourceId);

        PoolPurchase memory purchase;
        purchase.premiumAmount = premium();
        if (purchase.premiumAmount > maxPremium) {
            revert PremiumExceedsMaximum(purchase.premiumAmount, maxPremium);
        }

        _requireStack();
        _requireShell(shellId);
        purchase.path = _requirePoolSource(sourceId);
        _requireArtwork(sourceId, expectedArtworkHash);
        purchase.payer = payer;
        purchase.buyer = buyer;
        purchase.recipient = recipient;
        purchase.shellId = shellId;
        purchase.sourceId = sourceId;
        purchase.artworkHash = expectedArtworkHash;
        purchase.displacedArtworkHash = artworkHash(shellId);
        purchase.inventoryBefore = inventory();

        return _executePoolPurchase(purchase, minBuyerMirrorBalanceAfter);
    }

    function _executePoolPurchase(PoolPurchase memory purchase, uint256 minBuyerMirrorBalanceAfter)
        internal
        returns (uint256 inventoryBefore, uint256 inventoryAfter)
    {
        _enterSettlement();
        _distributePremium(purchase.payer, address(0));

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
        _pullFame(purchase.payer, address(this), unitAmount);

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
        IERC721(token).safeTransferFrom(address(this), to, tokenId);
        emit RescueERC721(token, to, tokenId);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        if (msg.sender != address(mirror)) revert UnsupportedNFT(msg.sender);
        return IERC721Receiver.onERC721Received.selector;
    }

    function _requireFee(uint256 candidate) internal view {
        uint256 maximum = fame.unit() / 10;
        if (candidate > maximum) revert FeeTooLarge(candidate, maximum);
    }

    function _requireFeeRecipient(address candidate) internal view {
        if (candidate == address(0) || candidate == address(this)) {
            revert InvalidFeeRecipient(candidate);
        }
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

    function _distributePremium(address payer, address excludedProvider) internal {
        address communityRecipient = feeRecipient;
        _requireFeeRecipient(communityRecipient);

        uint256 providerUnits = totalProviderUnits;
        uint256 distributedProviderFee;
        uint256 configuredProviderFee = providerFee;
        uint256 providerCount = _activeProviders.length;
        if (providerUnits != 0 && configuredProviderFee != 0) {
            for (uint256 i; i < providerCount; ++i) {
                address provider = _activeProviders[i];
                uint256 share = _providerShare(provider, configuredProviderFee, providerUnits);
                if (provider != excludedProvider) {
                    distributedProviderFee += share;
                    if (share != 0 && provider != payer) _pullFame(payer, provider, share);
                }
            }
        }

        // Always charge communityFee (no buyer-identity waiver). Pull even when payer is
        // the fee recipient so purchaseCharge stays synchronized with measured debits.
        uint256 communityAmount = configuredProviderFee - distributedProviderFee + uint256(communityFee);
        if (communityAmount != 0) {
            _pullFame(payer, communityRecipient, communityAmount);
        }
    }

    function _removeProviderUnit(address provider) internal returns (uint256 remainingUnits) {
        ProviderPosition storage position = _providerPositions[provider];
        uint256 unitCount = position.unitCount;
        if (unitCount == 0) revert NoProviderPosition(provider);

        remainingUnits = unitCount - 1;
        --totalProviderUnits;
        if (remainingUnits != 0) {
            position.unitCount = uint32(remainingUnits);
            return remainingUnits;
        }

        uint256 index = uint256(position.indexPlusOne) - 1;
        uint256 lastIndex = _activeProviders.length - 1;
        if (index != lastIndex) {
            address movedProvider = _activeProviders[lastIndex];
            _activeProviders[index] = movedProvider;
            _providerPositions[movedProvider].indexPlusOne = uint32(index + 1);
        }
        _activeProviders.pop();
        delete _providerPositions[provider];
    }

    function _providerPositionForDeposit(address provider) internal returns (ProviderPosition storage position) {
        position = _providerPositions[provider];
        if (position.unitCount != 0) return position;

        uint256 providerCount = _activeProviders.length;
        if (providerCount >= activeProviderCap) revert ActiveProviderCapReached(activeProviderCap);
        _activeProviders.push(provider);
        position.indexPlusOne = uint32(providerCount + 1);
    }

    function _transferInventoryToken(address provider, uint256 tokenId) internal {
        mirror.safeTransferFrom(provider, address(this), tokenId);
    }

    function _requireInventoryTokenId(uint256 tokenId) internal pure {
        if (tokenId < SOCIETY_TOKEN_ID_START || tokenId >= SOCIETY_TOKEN_ID_START + SOCIETY_TOKEN_ID_COUNT) {
            revert UnavailableShell(tokenId);
        }
    }

    function _providerShare(address provider, uint256 configuredProviderFee, uint256 providerUnits)
        internal
        view
        returns (uint256)
    {
        return configuredProviderFee * _providerPositions[provider].unitCount / providerUnits;
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
