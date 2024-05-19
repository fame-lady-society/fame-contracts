// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin5/contracts/governance/utils/Votes.sol";
import "./DN404Mirror.sol";

/**
 * @title FameMirror
 * @notice DN404 Mirror (NFT) contract that mirrors the fungible token contract.
 * This contract is used to mint NFTs for users who have accumulated a certain amount of fungible tokens.
 * Also Implements the EIP-5805 standard (ERC721Votes) and EIP-6372 standard (clock)
 */
contract FameMirror is DN404Mirror, Votes {
    constructor(address owner) DN404Mirror(owner) EIP712("Fame404", "1") {}

    error OnlyERC20CanCall();

    modifier onlyERC20() {
        if (msg.sender != address(_getDN404NFTStorage().baseERC20)) {
            revert OnlyERC20CanCall();
        }
        _;
    }

    /* --- EIP-5805 implementation --- */
    /**
     * @notice Returns the current timestamp.
     * @return The current timestamp.
     */
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    /**
     * @notice Returns the clock mode.
     * @return The clock mode.
     */
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp&from=default";
    }

    /* --- Votes implementation --- */
    /**
     * @dev Returns the balance of `account`.
     *
     * WARNING: Overriding this function will likely result in incorrect vote tracking.
     */
    function _getVotingUnits(
        address account
    ) internal view virtual override returns (uint256) {
        return balanceOf(account);
    }

    function updateVotingUnits(
        address from,
        address to,
        uint256
    ) external onlyERC20 {
        _transferVotingUnits(from, to, 1);
    }
}
