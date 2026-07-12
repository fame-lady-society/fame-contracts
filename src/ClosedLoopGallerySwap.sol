// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {CreatorArtistMagic} from "./CreatorArtistMagic.sol";
import {Fame} from "./Fame.sol";
import {FameMirror} from "./FameMirror.sol";

interface IERC721RescueTarget {
    function safeTransferFrom(address from, address to, uint256 id) external;
}

contract ClosedLoopGallerySwap is OwnableRoles, ReentrancyGuard {
    using SafeTransferLib for address;

    uint256 internal constant OPERATOR_ROLE = _ROLE_0;
    uint256 internal constant CREATOR_MAGIC_CREATOR_ROLE = _ROLE_1;
    uint256 internal constant CREATOR_MAGIC_BANISHER_ROLE = _ROLE_2;
    uint256 internal constant CREATOR_MAGIC_ART_POOL_MANAGER_ROLE = _ROLE_3;

    bytes4 private constant ERC721_RECEIVED = 0x150b7a02;

    Fame public immutable fame;
    FameMirror public immutable mirror;
    CreatorArtistMagic public immutable creatorMagic;

    address public feeRecipient;
    uint256 public accruedProtocolFees;

    bool private _externalMutationActive;

    struct Listing {
        uint96 premium;
        bool active;
    }

    mapping(uint256 => Listing) public listings;

    event FeeRecipientUpdated(address indexed feeRecipient);
    event Listed(uint256 indexed tokenId, uint256 premium);
    event Unlisted(uint256 indexed tokenId);
    event PremiumUpdated(uint256 indexed tokenId, uint256 premium);
    event Filled(
        address indexed buyer,
        address indexed recipient,
        uint256 indexed tokenId,
        uint256 unitAmount,
        uint256 premium,
        uint256 inventoryBefore,
        uint256 inventoryAfter
    );
    event MetadataRotated(uint256 indexed tokenId, RotationKind indexed kind, uint256 indexed poolTokenId);
    event AccruedFeesWithdrawn(address indexed to, uint256 amount, uint256 inventoryBefore, uint256 inventoryAfter);
    event RescueERC20(address indexed token, address indexed to, uint256 amount);
    event RescueERC721(address indexed token, address indexed to, uint256 indexed tokenId);

    enum RotationKind {
        ArtPool,
        EndOfMintPool,
        MintPool,
        BurnPool
    }

    error ZeroAddress();
    error ZeroPremium();
    error PremiumTooLarge(uint256 premium);
    error NotVaultOwner(uint256 tokenId);
    error ListingInactive(uint256 tokenId);
    error InventoryInvariantBroken(uint256 beforeBalance, uint256 afterBalance);
    error SettlementInProgress();
    error UnsupportedNFT(address token);
    error ListedTokenRescueBlocked(uint256 tokenId);
    error FameRescueBlocked();
    error InsufficientAccruedFees(uint256 requested, uint256 available);
    error TransferFailed();

    modifier noActiveSettlement() {
        if (_externalMutationActive) revert SettlementInProgress();
        _;
    }

    constructor(
        address payable fame_,
        address creatorMagic_,
        address initialFeeRecipient,
        address initialOwner,
        address initialOperator
    ) payable {
        if (
            fame_ == address(0) || creatorMagic_ == address(0) || initialFeeRecipient == address(0)
                || initialOwner == address(0) || initialOperator == address(0)
        ) {
            revert ZeroAddress();
        }

        fame = Fame(fame_);
        mirror = Fame(fame_).fameMirror();
        creatorMagic = CreatorArtistMagic(creatorMagic_);
        feeRecipient = initialFeeRecipient;

        Fame(fame_).setSkipNFT(false);

        _initializeOwner(initialOwner);
        _grantRoles(initialOperator, OPERATOR_ROLE);

        emit FeeRecipientUpdated(initialFeeRecipient);
    }

    function roleOperator() external pure returns (uint256) {
        return OPERATOR_ROLE;
    }

    function creatorMagicCreatorRole() external pure returns (uint256) {
        return CREATOR_MAGIC_CREATOR_ROLE;
    }

    function creatorMagicBanisherRole() external pure returns (uint256) {
        return CREATOR_MAGIC_BANISHER_ROLE;
    }

    function creatorMagicArtPoolManagerRole() external pure returns (uint256) {
        return CREATOR_MAGIC_ART_POOL_MANAGER_ROLE;
    }

    function requiredCreatorMagicRoles() external pure returns (uint256) {
        return CREATOR_MAGIC_BANISHER_ROLE | CREATOR_MAGIC_ART_POOL_MANAGER_ROLE;
    }

    function transferOwnership(address newOwner) public payable override onlyOwner noActiveSettlement {
        super.transferOwnership(newOwner);
    }

    function renounceOwnership() public payable override onlyOwner noActiveSettlement {
        super.renounceOwnership();
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

    function grantRoles(address user, uint256 roles) public payable override onlyOwner noActiveSettlement {
        super.grantRoles(user, roles);
    }

    function revokeRoles(address user, uint256 roles) public payable override onlyOwner noActiveSettlement {
        super.revokeRoles(user, roles);
    }

    function renounceRoles(uint256 roles) public payable override noActiveSettlement {
        super.renounceRoles(roles);
    }

    function setFeeRecipient(address newFeeRecipient) external onlyOwner noActiveSettlement {
        if (newFeeRecipient == address(0)) revert ZeroAddress();
        feeRecipient = newFeeRecipient;
        emit FeeRecipientUpdated(newFeeRecipient);
    }

    function list(uint256 tokenId, uint256 premium) external onlyOwnerOrRoles(OPERATOR_ROLE) noActiveSettlement {
        _requirePositivePremium(premium);
        _requireVaultOwner(tokenId);
        listings[tokenId] = Listing({premium: uint96(premium), active: true});
        emit Listed(tokenId, premium);
    }

    function unlist(uint256 tokenId) external onlyOwnerOrRoles(OPERATOR_ROLE) noActiveSettlement {
        if (!listings[tokenId].active) revert ListingInactive(tokenId);
        delete listings[tokenId];
        emit Unlisted(tokenId);
    }

    function setPremium(uint256 tokenId, uint256 premium) external onlyOwnerOrRoles(OPERATOR_ROLE) noActiveSettlement {
        _requireActiveListing(tokenId);
        _requirePositivePremium(premium);
        listings[tokenId].premium = uint96(premium);
        emit PremiumUpdated(tokenId, premium);
    }

    function fill(uint256 tokenId, address recipient)
        external
        nonReentrant
        noActiveSettlement
        returns (uint256 inventoryBefore, uint256 inventoryAfter)
    {
        if (recipient == address(0)) revert ZeroAddress();
        Listing memory listing = _requireActiveListing(tokenId);
        _requireVaultOwner(tokenId);

        uint256 unitAmount = fame.unit();
        uint256 totalAmount = unitAmount + uint256(listing.premium);
        inventoryBefore = mirror.balanceOf(address(this));

        delete listings[tokenId];
        _enterExternalMutation();
        if (!fame.transferFrom(msg.sender, address(this), totalAmount)) revert TransferFailed();
        mirror.safeTransferFrom(address(this), recipient, tokenId);
        accruedProtocolFees += uint256(listing.premium);
        inventoryAfter = mirror.balanceOf(address(this));
        if (inventoryAfter < inventoryBefore) revert InventoryInvariantBroken(inventoryBefore, inventoryAfter);
        _exitExternalMutation();

        emit Unlisted(tokenId);
        emit Filled(
            msg.sender, recipient, tokenId, unitAmount, uint256(listing.premium), inventoryBefore, inventoryAfter
        );
    }

    function rotateToArtPool(uint256 tokenId, string calldata newMetadataUrl)
        external
        onlyOwnerOrRoles(OPERATOR_ROLE)
        noActiveSettlement
    {
        _requireVaultOwner(tokenId);
        _enterExternalMutation();
        creatorMagic.banishToArtPool(tokenId, newMetadataUrl);
        _exitExternalMutation();
        emit MetadataRotated(tokenId, RotationKind.ArtPool, 0);
    }

    function rotateToEndOfMintPool(uint256 tokenId, string calldata newMetadataUrl)
        external
        onlyOwnerOrRoles(OPERATOR_ROLE)
        noActiveSettlement
    {
        _requireVaultOwner(tokenId);
        _enterExternalMutation();
        creatorMagic.banishToEndOfMintPool(tokenId, newMetadataUrl);
        _exitExternalMutation();
        emit MetadataRotated(tokenId, RotationKind.EndOfMintPool, 0);
    }

    function rotateToMintPool(uint256 tokenId, uint256 poolTokenId)
        external
        onlyOwnerOrRoles(OPERATOR_ROLE)
        noActiveSettlement
    {
        _requireVaultOwner(tokenId);
        _enterExternalMutation();
        creatorMagic.banishToMintPool(tokenId, poolTokenId);
        _exitExternalMutation();
        emit MetadataRotated(tokenId, RotationKind.MintPool, poolTokenId);
    }

    function rotateToBurnPool(uint256 tokenId, uint256 poolTokenId)
        external
        onlyOwnerOrRoles(OPERATOR_ROLE)
        noActiveSettlement
    {
        _requireVaultOwner(tokenId);
        _enterExternalMutation();
        creatorMagic.banishToBurnPool(tokenId, poolTokenId);
        _exitExternalMutation();
        emit MetadataRotated(tokenId, RotationKind.BurnPool, poolTokenId);
    }

    function withdrawAccruedFees(address to, uint256 amount)
        external
        onlyOwner
        nonReentrant
        noActiveSettlement
        returns (uint256 inventoryBefore, uint256 inventoryAfter)
    {
        if (to == address(0)) revert ZeroAddress();
        uint256 available = accruedProtocolFees;
        if (amount > available) revert InsufficientAccruedFees(amount, available);

        inventoryBefore = mirror.balanceOf(address(this));

        _enterExternalMutation();
        accruedProtocolFees = available - amount;
        if (!fame.transfer(to, amount)) revert TransferFailed();
        inventoryAfter = mirror.balanceOf(address(this));
        if (inventoryAfter < inventoryBefore) revert InventoryInvariantBroken(inventoryBefore, inventoryAfter);
        _exitExternalMutation();

        emit AccruedFeesWithdrawn(to, amount, inventoryBefore, inventoryAfter);
    }

    function rescueERC20(address token, address to, uint256 amount) external onlyOwner nonReentrant noActiveSettlement {
        if (token == address(0) || to == address(0)) revert ZeroAddress();
        if (token == address(fame)) revert FameRescueBlocked();

        _enterExternalMutation();
        token.safeTransfer(to, amount);
        _exitExternalMutation();

        emit RescueERC20(token, to, amount);
    }

    function rescueERC721(address token, address to, uint256 tokenId)
        external
        onlyOwner
        nonReentrant
        noActiveSettlement
    {
        if (token == address(0) || to == address(0)) revert ZeroAddress();
        if (token == address(mirror) && listings[tokenId].active) revert ListedTokenRescueBlocked(tokenId);

        _enterExternalMutation();
        IERC721RescueTarget(token).safeTransferFrom(address(this), to, tokenId);
        _exitExternalMutation();

        emit RescueERC721(token, to, tokenId);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        if (msg.sender != address(mirror)) revert UnsupportedNFT(msg.sender);
        return ERC721_RECEIVED;
    }

    function _requireActiveListing(uint256 tokenId) private view returns (Listing memory listing) {
        listing = listings[tokenId];
        if (!listing.active) revert ListingInactive(tokenId);
    }

    function _requirePositivePremium(uint256 premium) private pure {
        if (premium == 0) revert ZeroPremium();
        if (premium > type(uint96).max) revert PremiumTooLarge(premium);
    }

    function _requireVaultOwner(uint256 tokenId) private view {
        if (mirror.ownerOf(tokenId) != address(this)) revert NotVaultOwner(tokenId);
    }

    function _enterExternalMutation() private {
        if (_externalMutationActive) revert SettlementInProgress();
        _externalMutationActive = true;
    }

    function _exitExternalMutation() private {
        _externalMutationActive = false;
    }
}
