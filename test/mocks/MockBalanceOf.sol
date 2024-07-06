// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

contract MockBalanceOf {
    mapping(address => uint256) private _balances;

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function setBalance(address account, uint256 amount) external {
        _balances[account] = amount;
    }
}