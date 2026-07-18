// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";
import {ValidateBaseSepoliaUniversalPoolArtMarketplace} from "./ValidateBaseSepoliaUniversalPoolArtMarketplace.s.sol";

contract ActivateBaseSepoliaUniversalPoolArtMarketplace is Script {
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;

    error ChainIdMismatch(uint256 expected, uint256 actual);
    error UnexpectedOwnerSigner(address expected, address actual);

    function run() external {
        if (block.chainid != BASE_SEPOLIA_CHAIN_ID) {
            revert ChainIdMismatch(BASE_SEPOLIA_CHAIN_ID, block.chainid);
        }

        uint256 privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address signer = vm.addr(privateKey);
        Fame fame = Fame(payable(vm.envAddress("BASE_SEPOLIA_FAME_ADDRESS")));
        CreatorArtistMagic creatorMagic = CreatorArtistMagic(vm.envAddress("BASE_SEPOLIA_CREATOR_ARTIST_MAGIC_ADDRESS"));
        UniversalPoolArtMarketplace market =
            UniversalPoolArtMarketplace(vm.envAddress("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_ADDRESS"));
        address owner = vm.envAddress("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_OWNER");
        address feeRecipient = vm.envAddress("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_FEE_RECIPIENT");
        uint256 premium = vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_PREMIUM");
        uint256 minimumInventory = vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_MINIMUM_INVENTORY");

        if (signer != owner) revert UnexpectedOwnerSigner(owner, signer);

        ValidateBaseSepoliaUniversalPoolArtMarketplace validator = new ValidateBaseSepoliaUniversalPoolArtMarketplace();
        ValidateBaseSepoliaUniversalPoolArtMarketplace.MarketplaceExpectations memory expected =
            ValidateBaseSepoliaUniversalPoolArtMarketplace.MarketplaceExpectations({
                owner: owner,
                feeRecipient: feeRecipient,
                premium: premium,
                minimumInventory: minimumInventory,
                paused: market.paused()
            });
        if (!market.paused()) {
            validator.validateMarketplace(fame, fame.fameMirror(), creatorMagic, market, expected);
            return;
        }

        validator.validateMarketplace(fame, fame.fameMirror(), creatorMagic, market, expected);

        vm.startBroadcast(privateKey);
        market.unpause();
        vm.stopBroadcast();
    }
}
