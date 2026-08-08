// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {ValidateBaseUniversalPoolArtMarketplace} from "./ValidateBaseUniversalPoolArtMarketplace.s.sol";

contract TransferBaseUniversalPoolArtMarketplaceOwnership is Script {
    uint256 internal constant BASE_CHAIN_ID = 8453;
    address public constant SOCIETY_SAFE = 0xC952C53D8B63919e372caa2E6FEe605ee24E4D3D;

    error ChainIdMismatch(uint256 expected, uint256 actual);
    error CodeMissing(address target);
    error OwnerMismatch(address expected, address actual);
    error FutureOwnerMismatch(address expected, address actual);
    error FutureOwnerIsCurrentOwner(address owner);
    error MarketplaceNotPaused();
    error UnexpectedSigner(address expected, address actual);

    function run() external {
        if (block.chainid != BASE_CHAIN_ID) revert ChainIdMismatch(BASE_CHAIN_ID, block.chainid);

        UniversalPoolArtMarketplace market =
            UniversalPoolArtMarketplace(vm.envAddress("BASE_UNIVERSAL_MARKETPLACE_ADDRESS"));
        address expectedOwner = vm.envAddress("BASE_UNIVERSAL_MARKETPLACE_OWNER");
        address futureOwner = vm.envAddress("BASE_UNIVERSAL_MARKETPLACE_FUTURE_OWNER");
        _validateHandoff(market, expectedOwner, futureOwner);
        new ValidateBaseUniversalPoolArtMarketplace().run();

        uint256 privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address signer = vm.addr(privateKey);
        if (signer != expectedOwner) revert UnexpectedSigner(expectedOwner, signer);

        vm.startBroadcast(privateKey);
        market.transferOwnership(SOCIETY_SAFE);
        vm.stopBroadcast();

        if (market.owner() != SOCIETY_SAFE) revert FutureOwnerMismatch(SOCIETY_SAFE, market.owner());
    }

    function validateHandoff(UniversalPoolArtMarketplace market, address expectedOwner, address futureOwner)
        external
        view
    {
        _validateHandoff(market, expectedOwner, futureOwner);
    }

    function _validateHandoff(UniversalPoolArtMarketplace market, address expectedOwner, address futureOwner)
        internal
        view
    {
        if (address(market).code.length == 0) revert CodeMissing(address(market));
        if (market.owner() != expectedOwner) revert OwnerMismatch(expectedOwner, market.owner());
        if (futureOwner != SOCIETY_SAFE) revert FutureOwnerMismatch(SOCIETY_SAFE, futureOwner);
        if (futureOwner == market.owner()) revert FutureOwnerIsCurrentOwner(futureOwner);
        if (SOCIETY_SAFE.code.length == 0) revert CodeMissing(SOCIETY_SAFE);
        if (!market.paused()) revert MarketplaceNotPaused();
    }
}
