// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin5/contracts/governance/TimelockController.sol";

contract FAMEusTimelockController is TimelockController {
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}
}
