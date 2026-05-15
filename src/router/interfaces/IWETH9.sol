// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function transfer(address to, uint256 amount) external returns (bool);
}
