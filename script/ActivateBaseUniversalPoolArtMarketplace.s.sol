// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {FameMarketplaceCheckout} from "../src/FameMarketplaceCheckout.sol";
import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {ValidateBaseUniversalPoolArtMarketplace} from "./ValidateBaseUniversalPoolArtMarketplace.s.sol";
import {ValidateFameRouterBase} from "./ValidateFameRouterBase.s.sol";

contract ActivateBaseUniversalPoolArtMarketplace is Script {
    uint256 internal constant BASE_CHAIN_ID = 8453;
    address internal constant BASE_CHILD_RENDERER = 0x8091D00A25ebE87A2A1Ef19e1d33689FCAdC3fA5;

    error ChainIdMismatch(uint256 expected, uint256 actual);
    error UnexpectedOwner(address expected, address actual);
    error UnexpectedCheckout(address expected, address actual);

    function run() external {
        _requireBase();

        Fame fame = Fame(payable(vm.envAddress("BASE_FAME_ADDRESS")));
        FameMirror mirror = FameMirror(payable(vm.envAddress("BASE_FAME_NFT_ADDRESS")));
        CreatorArtistMagic creatorMagic = CreatorArtistMagic(vm.envAddress("BASE_CREATOR_ARTIST_MAGIC_ADDRESS"));
        UniversalPoolArtMarketplace market =
            UniversalPoolArtMarketplace(vm.envAddress("BASE_UNIVERSAL_MARKETPLACE_ADDRESS"));
        FameMarketplaceCheckout checkout =
            FameMarketplaceCheckout(payable(vm.envAddress("BASE_FAME_MARKETPLACE_CHECKOUT_ADDRESS")));
        address owner = vm.envAddress("BASE_UNIVERSAL_MARKETPLACE_OWNER");
        ValidateBaseUniversalPoolArtMarketplace validator = new ValidateBaseUniversalPoolArtMarketplace();
        new ValidateFameRouterBase().run();
        validator.validateBaseCheckoutDependencies(checkout);
        ValidateBaseUniversalPoolArtMarketplace.MarketplaceExpectations memory expected =
            ValidateBaseUniversalPoolArtMarketplace.MarketplaceExpectations({
                owner: owner,
                feeRecipient: vm.envAddress("BASE_UNIVERSAL_MARKETPLACE_FEE_RECIPIENT"),
                premium: vm.envUint("BASE_UNIVERSAL_MARKETPLACE_PREMIUM"),
                inventory: vm.envUint("BASE_UNIVERSAL_MARKETPLACE_INVENTORY"),
                paused: true
            });

        ValidateBaseUniversalPoolArtMarketplace.CheckoutExpectations memory checkoutExpected =
            ValidateBaseUniversalPoolArtMarketplace.CheckoutExpectations({
                router: vm.envAddress("BASE_FAME_ROUTER_ADDRESS"),
                usdc: vm.envAddress("BASE_USDC_ADDRESS"),
                weth: vm.envAddress("BASE_WETH_ADDRESS"),
                routerFeeRecipient: vm.envAddress("BASE_FAME_ROUTER_FEE_RECIPIENT"),
                routerFeePpm: vm.envUint("BASE_FAME_ROUTER_FEE_PPM")
            });

        validator.validateMarketplaceStack(
            fame, mirror, creatorMagic, market, checkout, BASE_CHILD_RENDERER, expected, checkoutExpected
        );
        activateMarketplace(market, checkout, owner);
        expected.paused = false;
        validator.validateMarketplaceStack(
            fame, mirror, creatorMagic, market, checkout, BASE_CHILD_RENDERER, expected, checkoutExpected
        );
    }

    function activateMarketplace(UniversalPoolArtMarketplace market, FameMarketplaceCheckout checkout, address owner)
        public
    {
        _requireBase();
        if (market.owner() != owner) revert UnexpectedOwner(owner, market.owner());
        if (market.authorizedCheckout() != address(checkout)) {
            revert UnexpectedCheckout(address(checkout), market.authorizedCheckout());
        }

        vm.startBroadcast(owner);
        market.unpause();
        vm.stopBroadcast();
    }

    function _requireBase() internal view {
        if (block.chainid != BASE_CHAIN_ID) revert ChainIdMismatch(BASE_CHAIN_ID, block.chainid);
    }
}
