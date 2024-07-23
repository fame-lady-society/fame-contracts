// contracts/TokenVesting.sol
// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {TokenVesting} from "@AbdelStark/token-vesting-contracts/TokenVesting.sol";

contract FameVesting is TokenVesting {
    constructor(address token) TokenVesting(token) {}
}
