pragma solidity ^0.8.4;

interface IBurnedPoolManager {
    function addToBurnedPool(
        uint256 totalNFTSupplyAfterBurn,
        uint256 totalSupplyAfterBurn
    ) external pure returns (bool);
}
