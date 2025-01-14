// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC721} from "solady/tokens/ERC721.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {MerkleProofLib} from "solady/utils/MerkleProofLib.sol";
import {LibMap} from "solady/utils/LibMap.sol";
import {LibString} from "solady/utils/LibString.sol";

contract LingerieDreams is ERC721, Ownable {
    using LibString for uint256, string;
    using LibMap for LibMap.Uint8Map;
    using MerkleProofLib for bytes32[];

    // STAGE
    struct Stage {
        uint8 order;
        uint8 mintLimit;
        uint224 mintPrice;
    }
    uint8 private STAGE;
    uint8 constant STAGE_PRE_MINT = 0;
    uint8 constant STAGE_HOLDERS_MINT = 1;
    uint8 constant STAGE_ALLOWLIST_MINT = 2;
    uint8 constant STAGE_PUBLIC_MINT = 3;
    Stage constant STAGE_PRE_MINT = Stage({order: STAGE_PRE_MINT, mintLimit: 0, mintPrice: 100000 ether});
    Stage constant STAGE_HOLDERS_MINT = Stage({order: STAGE_HOLDERS_MINT, mintLimit: 3, mintPrice: 30 ether});
    Stage constant STAGE_ALLOWLIST_MINT = Stage({order: STAGE_ALLOWLIST_MINT, mintLimit: 3, mintPrice: 40 ether});
    Stage constant STAGE_PUBLIC_MINT = Stage({order: STAGE_PUBLIC_MINT, mintLimit: 10, mintPrice: 69 ether});
    
    // ERC721 identifiers
    string constant NAME = "Lingerie Dreams";
    string constant SYMBOL = "LD";

    // Supply
    uint8 private SUPPLY;
    uint8 constant SUPPLY_MAX = 69;

    // NFT contract allowlist minting
    address private ALLOWLIST_MINT_CONTRACT;
    LibMap.Uint8Map private HOLDERS_MINT_MAP;

    // Merkle root for allowlist minting
    bytes32 private MERKLE_ROOT;
    mapping(address => uint8) private ALLOWLIST_MINT_MAP;

    // Tracking public mint count
    mapping(address => uint8) private PUBLIC_MINT_MAP;

    // Base URI for token metadata
    string private BASE_URI;

    

    constructor(address allowlistMintContract, bytes32 merkleRoot) {
        _initializeOwner(msg.sender);
        ALLOWLIST_MINT_CONTRACT = allowlistMintContract;
        MERKLE_ROOT = merkleRoot;
    }

    function name() public pure override returns (string memory) {
        return NAME;
    }

    function symbol() public pure override returns (string memory) {
        return SYMBOL;
    }

    function totalSupply() public view returns (uint256) {
        return SUPPLY;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        return BASE_URI.concat(tokenId.toString());
    }

    function setBaseURI(string memory newBaseURI) external onlyOwner {
        BASE_URI = newBaseURI;
    }

    function setMerkleRoot(bytes32 newMerkleRoot) external onlyOwner {
        MERKLE_ROOT = newMerkleRoot;
    }

    error AllStagesCompleted();
    event StageAdvanced(uint8 newStage);

    function advanceStage() external onlyOwner {
        if (STAGE.order >= STAGE_PUBLIC_MINT) revert AllStagesCompleted();
        if (STAGE.order == STAGE_PRE_MINT) {
            STAGE = STAGE_HOLDERS_MINT;
        } else if (STAGE.order == STAGE_HOLDERS_MINT) {
            STAGE = STAGE_ALLOWLIST_MINT;
        } else if (STAGE.order == STAGE_ALLOWLIST_MINT) {
            STAGE = STAGE_PUBLIC_MINT;
        }
        emit StageAdvanced(STAGE.order);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override {
        if (from == address(0)) {
            SUPPLY++;
        } else if (to == address(0)) {
            SUPPLY--;
        }
    }

    error MintAmountExceedsLimit();
    error MintAmountExceedsSupply();
    modifier mintAvailable(uint8 mintAmount) {
        if (SUPPLY + mintAmount > SUPPLY_MAX) revert MintAmountExceedsSupply();
        _;
    }

    error NotEnoughPayment();
    modifier enoughPayment(uint8 mintAmount) {
        if (msg.value < STAGE.mintPrice * mintAmount) revert NotEnoughPayment();
        _;
    }

    error NotInHoldersMintStage();
    error NotTheOwnerOfTheToken();
    function holderMint(uint256 tokenId, uint8 mintAmount) external mintAvailable(mintAmount) enoughPayment(mintAmount) {
        uint8 currentHoldersMintAmount = HOLDERS_MINT_MAP.get(tokenId);
        if (STAGE.order != STAGE_HOLDERS_MINT) revert NotInHoldersMintStage();
        if (currentHoldersMintAmount + mintAmount > STAGE.mintLimit) revert MintAmountExceedsLimit();
        if (ALLOWLIST_MINT_TOKEN.ownerOf(tokenId) != msg.sender) revert NotTheOwnerOfTheToken();
        HOLDERS_MINT_MAP.set(tokenId, currentHoldersMintAmount + mintAmount);
        for (uint8 i = 0; i < mintAmount; i++) {
            _mint(msg.sender, ++SUPPLY);
        }
    }

    error NotInAllowlistMintStage();
    error InvalidProof();
    function allowlistMint(uint8 mintAmount, bytes32[] calldata proof) external mintAvailable(mintAmount) enoughPayment(mintAmount) {
        uint8 currentAllowlistMintAmount = ALLOWLIST_MINT_MAP.get(msg.sender);
        if (STAGE.order != STAGE_ALLOWLIST_MINT) revert NotInAllowlistMintStage();
        if (currentAllowlistMintAmount + mintAmount > STAGE.mintLimit) revert MintAmountExceedsLimit();
        if (proof.verifyProof(MERKLE_ROOT, keccak256(abi.encodePacked(msg.sender)))) revert InvalidProof();
        ALLOWLIST_MINT_MAP.set(msg.sender, currentAllowlistMintAmount + mintAmount);
        for (uint8 i = 0; i < mintAmount; i++) {
            _mint(msg.sender, ++SUPPLY);
        }
    }

    error NotInPublicMintStage();
    function publicMint(uint8 mintAmount) external mintAvailable(mintAmount) enoughPayment(mintAmount) {
        uint8 currentPublicMintAmount = PUBLIC_MINT_MAP.get(msg.sender);
        if (STAGE.order != STAGE_PUBLIC_MINT) revert NotInPublicMintStage();
        if (currentPublicMintAmount + mintAmount > STAGE.mintLimit) revert MintAmountExceedsLimit();
        PUBLIC_MINT_MAP.set(msg.sender, currentPublicMintAmount + mintAmount);
        for (uint8 i = 0; i < mintAmount; i++) {
            _mint(msg.sender, ++SUPPLY);
        }
    }
}
