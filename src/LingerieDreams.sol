// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC721} from "solady/tokens/ERC721.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {MerkleProofLib} from "solady/utils/MerkleProofLib.sol";
import {LibMap} from "solady/utils/LibMap.sol";
import {LibString} from "solady/utils/LibString.sol";

contract LingerieDreams is ERC721, Ownable {
    using LibString for uint256;
    using LibString for string;
    using LibMap for LibMap.Uint8Map;

    uint64 private START_TIME;

    uint256 private MINT_PRICE = 30 ether;
    uint8 private MINT_LIMIT = 3;

    // ERC721 identifiers
    string constant NAME = "Lingerie Dreams";
    string constant SYMBOL = "LD";

    // Supply
    uint8 private SUPPLY;
    uint8 private SUPPLY_MAX = 69;

    // Tracking public mint count
    mapping(address => uint8) private PUBLIC_MINT_MAP;

    // Base URI for token metadata
    string private BASE_URI;

    constructor(
        uint64 _startTime,
        uint256 _mintPrice,
        uint8 _mintLimit,
        string memory _baseURI
    ) {
        START_TIME = _startTime;
        MINT_PRICE = _mintPrice;
        MINT_LIMIT = _mintLimit;
        BASE_URI = _baseURI;
        _initializeOwner(msg.sender);
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

    function mintPrice() public view returns (uint256) {
        return MINT_PRICE;
    }

    function mintLimit() public view returns (uint8) {
        return MINT_LIMIT;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        return BASE_URI.concat(tokenId.toString());
    }

    function setBaseURI(string memory newBaseURI) external onlyOwner {
        BASE_URI = newBaseURI;
    }

    error MintLimitCantBeZero();

    function setMintLimit(uint8 newMintLimit) external onlyOwner {
        if (newMintLimit == 0) revert MintLimitCantBeZero();
        MINT_LIMIT = newMintLimit;
    }

    error MintMustNotBeStarted();

    function setStartTime(uint64 newStartTime) external onlyOwner {
        if (START_TIME < uint64(block.timestamp)) revert MintMustNotBeStarted();
        START_TIME = newStartTime;
    }

    function getStartTime() external view returns (uint64) {
        return START_TIME;
    }

    error MintAmountExceedsLimit();
    error MintAmountExceedsSupply();
    error MintMustBeGreaterThanZero();

    modifier mintAvailable(uint8 mintAmount) {
        if (mintAmount <= 0) revert MintMustBeGreaterThanZero();
        if (SUPPLY + mintAmount > SUPPLY_MAX) revert MintAmountExceedsSupply();
        if (mintAmount + PUBLIC_MINT_MAP[msg.sender] > MINT_LIMIT)
            revert MintAmountExceedsLimit();
        _;
    }

    error NotEnoughPayment();

    modifier enoughPayment(uint8 mintAmount) {
        if (msg.value < MINT_PRICE * mintAmount) {
            revert NotEnoughPayment();
        }
        _;
    }

    error PublicMintNotStarted();

    function publicMint(
        uint8 mintAmount
    ) external payable mintAvailable(mintAmount) enoughPayment(mintAmount) {
        if (uint64(block.timestamp) < START_TIME) revert PublicMintNotStarted();
        PUBLIC_MINT_MAP[msg.sender] += mintAmount;
        for (uint8 i = 0; i < mintAmount; i++) {
            _mint(msg.sender, ++SUPPLY);
        }
    }

    error FailedToSendEther();

    function withdraw() external onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        if (!success) revert FailedToSendEther();
    }
}
