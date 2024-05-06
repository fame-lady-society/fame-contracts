// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "solady/tokens/ERC20.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {EnumerableSetLib} from "solady/utils/EnumerableSetLib.sol";

contract FameSaleToken is ERC20, OwnableRoles {
    EnumerableSetLib.AddressSet internal _holders;
    using EnumerableSetLib for EnumerableSetLib.AddressSet;

    constructor(address owner) {
        _initializeOwner(owner);
    }

    function name() public pure override returns (string memory) {
        return "Fame Presale Token";
    }

    function symbol() public pure override returns (string memory) {
        return "FPT";
    }

    uint256 internal constant MINTER = 1 << 0;

    function roleMinter() public pure returns (uint256) {
        return MINTER;
    }

    uint256 internal constant BURNER = 1 << 1;

    function roleBurner() public pure returns (uint256) {
        return BURNER;
    }

    uint256 internal constant CONTROLLER = 1 << 2;

    function roleController() public pure returns (uint256) {
        return CONTROLLER;
    }

    // @dev soulbound transfer
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override onlyRoles(CONTROLLER) {}

    function _afterTokenTransfer(
        address from,
        address to,
        uint256
    ) internal override {
        if (
            (from != address(0) && balanceOf(from) == 0) ||
            _holders.contains(from)
        ) {
            _holders.remove(from);
        }
        if (to != address(0)) {
            _holders.add(to);
        }
    }

    function holders() public view returns (address[] memory) {
        return _holders.values();
    }

    function hasHolder(address account) public view returns (bool) {
        return _holders.contains(account);
    }

    function mint(address to, uint256 amount) external onlyRoles(MINTER) {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRoles(BURNER) {
        _burn(from, amount);
    }
}
