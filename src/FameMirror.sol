// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Votes.sol";
import "./DN404Mirror.sol";

interface IERC6372 {
    function clock() external view returns (uint48);
    function CLOCK_MODE() external view returns (string memory);
}

interface IERC5805 is IERC6372 {
    event DelegateChanged(
        address indexed delegator,
        address indexed fromDelegate,
        address indexed toDelegate
    );
    event DelegateVotesChanged(
        address indexed delegate,
        uint256 previousBalance,
        uint256 newBalance
    );

    function getVotes(address account) external view returns (uint256);
    function getPastVotes(
        address account,
        uint256 timepoint
    ) external view returns (uint256);
    function delegates(address account) external view returns (address);
    function nonces(address owner) external view returns (uint256);

    function delegate(address delegatee) external;
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

/**
 * @title FameMirror
 * @notice DN404 Mirror (NFT) contract that mirrors the fungible token contract.
 * This contract is used to mint NFTs for users who have accumulated a certain amount of fungible tokens.
 * Also Implements the EIP-5805 standard (ERC721Votes) and EIP-6372 standard (clock)
 */
contract FameMirror is DN404Mirror, IERC6372 {
    constructor(address owner) DN404Mirror(owner) {}

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
}
