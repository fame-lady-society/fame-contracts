// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {GovSociety} from "./GovSociety.sol";

contract FameusGovernorQuorum {
    GovSociety private immutable _societyToken;

    constructor(GovSociety societyToken) {
        _societyToken = societyToken;
    }

    function quorum(uint256 /* blockNumber */) public view returns (uint256) {
        uint256 supply = _societyToken.totalSupply();
        // Less than 88 Society tokens? Then there is no quorum
        if (supply < 88) {
            return 0;
        }
        // Else return the nearest multiple of 8 then divide by 8
        return (((supply * 88) / 88) / 8);
    }
}
