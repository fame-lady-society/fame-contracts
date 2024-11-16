// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin5/contracts/token/ERC20/IERC20.sol";

contract SwapContract {
    struct Donation {
        address token;
        uint256 amount;
    }

    address constant TOKEN = 0xf307e242BfE1EC1fF01a4Cef2fdaa81b10A52418;
    mapping(address => Donation) private destinationMap;

    function donate(uint256 amount, address destination) external {
        // check if the destination already has a swap
        if (destinationMap[destination].token != address(0)) {
            // if it does, add the amount to the existing swap
            destinationMap[destination].amount += amount;
        } else {
            // if it doesn't, create a new swap
            destinationMap[destination] = Donation(TOKEN, amount);
        }
        IERC20(TOKEN).transferFrom(msg.sender, address(this), amount);
    }

    function redeem(address onBehalf) external {
        Donation memory donation = destinationMap[onBehalf];
        require(
            donation.token != address(0),
            "No donation found for this address"
        );
        IERC20(donation.token).transfer(onBehalf, donation.amount);
        delete destinationMap[onBehalf];
    }
}
