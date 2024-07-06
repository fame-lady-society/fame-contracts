// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin5/contracts/token/ERC20/IERC20.sol";
import {IGasliteDrop} from "../../src/IGasliteDrop.sol";

interface IAirdropSource {
    function balanceOf(address) external view returns (uint256);
    function allOwners() external pure returns (address[] memory);
}

contract AirdropHelper {
    function totalFromContract(
        IAirdropSource source
    ) public view returns (uint256) {
        uint256 totalAmount = 0;
        address[] memory owners = source.allOwners();
        for (uint256 i = 0; i < owners.length; i++) {
            totalAmount += source.balanceOf(owners[i]);
        }
        return totalAmount;
    }

    // Javascript exports from src/features/claim/hooks/constants.ts
    // export const TOTAL_TOKENS = 888_000_000n * 10n ** 18n;
    // export const FLS_TOKENS = (TOTAL_TOKENS * 235n) / 1000n;
    // export const SISTER_TOKENS = (TOTAL_TOKENS * 15n) / 1000n;
    // export const METAVIXEN_BOOST = 5n;
    // export const TOTAL_SISTER_TOKENS = 14483n;
    // export const ALLOCATION_PER_SISTER_TOKEN = SISTER_TOKENS / TOTAL_SISTER_TOKENS;
    // but use totalSupply from the fame tokenContract
    uint256 public METAVIXEN_BOOST = 5;
    function baseTokenAmount(
        uint256 totalSupply
    ) public pure returns (uint256) {
        return (totalSupply * 235) / 1000;
    }
    function sisterTokenAmount(
        uint256 totalSupply
    ) public pure returns (uint256) {
        return (totalSupply * 15) / 1000;
    }
    function allocationPerSisterToken(
        uint256 totalSupply
    ) public pure returns (uint256) {
        return sisterTokenAmount(totalSupply) / 14483;
    }
}
