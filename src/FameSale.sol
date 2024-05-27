// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FameSaleToken} from "./FameSaleToken.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {MerkleProofLib} from "solady/utils/MerkleProofLib.sol";

contract FameSale is OwnableRoles {
    address public immutable fameSaleToken;
    bool public isPaused;
    bytes32 public merkleRoot;

    constructor() {
        _initializeOwner(msg.sender);
        isPaused = true;
        fameSaleToken = address(new FameSaleToken(msg.sender));
    }

    uint256 internal constant TREASURER = _ROLE_0;

    function roleTreasurer() public pure returns (uint256) {
        return TREASURER;
    }

    uint256 internal constant EXECUTIVE = _ROLE_1;

    function roleExecutive() public pure returns (uint256) {
        return EXECUTIVE;
    }

    uint256 internal constant ALLOWLIST = _ROLE_2;

    function roleAllowlist() public pure returns (uint256) {
        return ALLOWLIST;
    }

    function fameTotalSupply() public view returns (uint256) {
        return FameSaleToken(fameSaleToken).totalSupply();
    }

    function fameBalanceOf(address account) public view returns (uint256) {
        return FameSaleToken(fameSaleToken).balanceOf(account);
    }

    uint256 public maxRaise = 8 ether;

    function setMaxRaise(uint256 _maxRaise) public onlyRoles(TREASURER) {
        maxRaise = _maxRaise;
    }

    uint public maxBuy = 1 ether;

    function setMaxBuy(uint _maxBuy) public onlyRoles(TREASURER) {
        maxBuy = _maxBuy;
    }

    function raiseRemaining() public view returns (uint256) {
        return maxRaise - fameTotalSupply();
    }

    function setMerkleRoot(bytes32 _merkleRoot) public onlyRoles(ALLOWLIST) {
        merkleRoot = _merkleRoot;
    }

    function canProve(
        bytes32[] calldata proof,
        address check
    ) public view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(check));
        return MerkleProofLib.verifyCalldata(proof, merkleRoot, leaf);
    }

    error NotAllowed();
    modifier isAllowed(bytes32[] calldata proof, address check) {
        if (!canProve(proof, check)) {
            revert NotAllowed();
        }
        _;
    }

    error Paused();
    modifier whenNotPaused() {
        if (isPaused) {
            revert Paused();
        }
        _;
    }

    error MaxRaisedExceeded();
    error MaxBuyExceeded();
    function buy(
        bytes32[] calldata merkleProof
    ) public payable isAllowed(merkleProof, msg.sender) whenNotPaused {
        if (raiseRemaining() < msg.value) {
            revert MaxRaisedExceeded();
        }
        if (msg.value + fameBalanceOf(msg.sender) > maxBuy) {
            revert MaxBuyExceeded();
        }

        FameSaleToken(fameSaleToken).mint(msg.sender, msg.value);
    }

    error NoFundsAvailable();
    error NoRefundAvailable();

    function refund(address to, uint256 amount) public onlyRoles(TREASURER) {
        if (address(this).balance < amount) {
            revert NoFundsAvailable();
        }
        if (amount > fameBalanceOf(to)) {
            revert NoRefundAvailable();
        }

        FameSaleToken(fameSaleToken).burn(to, amount);

        (bool success, ) = payable(to).call{value: amount}("");
        require(success);
    }

    function pause() public onlyRoles(EXECUTIVE) {
        isPaused = true;
    }

    function unpause() public onlyRoles(EXECUTIVE) {
        isPaused = false;
    }

    function withdraw() public onlyRoles(EXECUTIVE) {
        isPaused = true;
        payable(msg.sender).transfer(address(this).balance);
    }

    receive() external payable {
        revert("No direct deposits allowed");
    }
}
