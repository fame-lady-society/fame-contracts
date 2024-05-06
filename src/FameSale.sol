// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FameSaleToken} from "./FameSaleToken.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";

contract FameSale is OwnableRoles {
    address public immutable fameSaleToken;
    bool public isPaused;

    constructor() {
        _initializeOwner(msg.sender);

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

    error MaxRaisedExceeded();
    error MaxBuyExceeded();
    function buy() public payable {
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
        if (amount > fameBalanceOf(msg.sender)) {
            revert NoRefundAvailable();
        }

        FameSaleToken(fameSaleToken).burn(msg.sender, amount);

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
}
