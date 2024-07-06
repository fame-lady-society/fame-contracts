// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface IGasliteDrop {
    function airdropERC721(
        address _nft,
        address[] calldata _addresses,
        uint256[] calldata _tokenIds
    ) external payable;

    /**
     * @notice Airdrop ERC20 tokens to a list of addresses
     * @param _token The address of the ERC20 contract
     * @param _addresses The addresses to airdrop to
     * @param _amounts The amounts to airdrop
     * @param _totalAmount The total amount to airdrop
     */
    function airdropERC20(
        address _token,
        address[] calldata _addresses,
        uint256[] calldata _amounts,
        uint256 _totalAmount
    ) external payable;
}
