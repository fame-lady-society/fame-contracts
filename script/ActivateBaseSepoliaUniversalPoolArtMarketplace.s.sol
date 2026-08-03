// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {ValidateBaseSepoliaUniversalPoolArtMarketplace} from "./ValidateBaseSepoliaUniversalPoolArtMarketplace.s.sol";

contract ActivateBaseSepoliaUniversalPoolArtMarketplace is Script {
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;

    error ChainIdMismatch(uint256 expected, uint256 actual);
    error UnexpectedOwnerSigner(address expected, address actual);

    function run() external {
        if (block.chainid != BASE_SEPOLIA_CHAIN_ID) {
            revert ChainIdMismatch(BASE_SEPOLIA_CHAIN_ID, block.chainid);
        }

        Fame fame = Fame(payable(vm.envAddress("BASE_SEPOLIA_FAME_ADDRESS")));
        FameMirror mirror = FameMirror(payable(vm.envAddress("BASE_SEPOLIA_FAME_NFT_ADDRESS")));
        CreatorArtistMagic creatorMagic = CreatorArtistMagic(vm.envAddress("BASE_SEPOLIA_CREATOR_ARTIST_MAGIC_ADDRESS"));
        UniversalPoolArtMarketplace market =
            UniversalPoolArtMarketplace(vm.envAddress("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_ADDRESS"));
        address owner = vm.envAddress("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_OWNER");
        address feeRecipient = vm.envAddress("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_FEE_RECIPIENT");
        uint256 communityFee = vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_COMMUNITY_FEE");
        uint256 providerFee = vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_PROVIDER_FEE");
        uint256 activeProviderCap = vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_ACTIVE_PROVIDER_CAP");
        uint256 minimumInventory = vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_MINIMUM_INVENTORY");

        ValidateBaseSepoliaUniversalPoolArtMarketplace validator = new ValidateBaseSepoliaUniversalPoolArtMarketplace();
        validator.validateCanonicalAddresses(fame, mirror);

        uint256 privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address signer = vm.addr(privateKey);
        if (signer != owner) revert UnexpectedOwnerSigner(owner, signer);

        ValidateBaseSepoliaUniversalPoolArtMarketplace.MarketplaceExpectations memory expected =
            ValidateBaseSepoliaUniversalPoolArtMarketplace.MarketplaceExpectations({
                owner: owner,
                feeRecipient: feeRecipient,
                communityFee: communityFee,
                providerFee: providerFee,
                activeProviderCap: activeProviderCap,
                minimumInventory: minimumInventory,
                paused: market.paused()
            });
        if (!market.paused()) {
            validator.validateMarketplace(fame, mirror, creatorMagic, market, expected);
            return;
        }

        validator.validateMarketplace(fame, mirror, creatorMagic, market, expected);

        vm.startBroadcast(privateKey);
        market.unpause();
        vm.stopBroadcast();
    }
}
