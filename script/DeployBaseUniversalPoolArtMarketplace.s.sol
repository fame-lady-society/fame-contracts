// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {FameMarketplaceCheckout} from "../src/FameMarketplaceCheckout.sol";
import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";
import {ValidateFameRouterBase} from "./ValidateFameRouterBase.s.sol";

contract DeployBaseUniversalPoolArtMarketplace is Script {
    uint256 internal constant BASE_CHAIN_ID = 8453;
    address internal constant BASE_FAME = 0xf307e242BfE1EC1fF01a4Cef2fdaa81b10A52418;
    address internal constant BASE_MIRROR = 0xBB5ED04dD7B207592429eb8d599d103CCad646c4;
    address internal constant BASE_CREATOR_MAGIC = 0xC8268c2aa571F3C88044C2959F73DdB8eB9e139F;
    address internal constant BASE_CHILD_RENDERER = 0x8091D00A25ebE87A2A1Ef19e1d33689FCAdC3fA5;
    address internal constant BASE_FAME_ROUTER = 0xAdefa5860389E8936ebf2977e1Fb4a365aA39636;
    address internal constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant BASE_WETH = 0x4200000000000000000000000000000000000006;
    address internal constant EXPECTED_DEPLOYER = 0xD52E2A6bBcEba9673440e4D7843Db6713E9B6FD9;
    address internal constant EXPECTED_SAFE = 0xC952C53D8B63919e372caa2E6FEe605ee24E4D3D;
    uint256 internal constant EXPECTED_UNIT = 1_000_000 ether;
    uint256 internal constant EXPECTED_PREMIUM = 30_000 ether;

    error ChainIdMismatch(uint256 expected, uint256 actual);
    error CanonicalStackMismatch();
    error ConfigurationMismatch(string field, address expected, address actual);
    error ValueMismatch(string field, uint256 expected, uint256 actual);
    error FeeRecipientNotSkippingNFT(address recipient);
    error RouterNotSkippingNFT(address router);

    function run() external returns (UniversalPoolArtMarketplace market, FameMarketplaceCheckout checkout) {
        _requireBase();

        Fame fame = Fame(payable(vm.envAddress("BASE_FAME_ADDRESS")));
        CreatorArtistMagic creatorMagic = CreatorArtistMagic(vm.envAddress("BASE_CREATOR_ARTIST_MAGIC_ADDRESS"));
        address router = vm.envAddress("BASE_FAME_ROUTER_ADDRESS");
        address usdc = vm.envAddress("BASE_USDC_ADDRESS");
        address weth = vm.envAddress("BASE_WETH_ADDRESS");
        address deployer = vm.envAddress("BASE_UNIVERSAL_MARKETPLACE_DEPLOYER");
        address owner = vm.envAddress("BASE_UNIVERSAL_MARKETPLACE_OWNER");
        address feeRecipient = vm.envAddress("BASE_UNIVERSAL_MARKETPLACE_FEE_RECIPIENT");
        address futureOwner = vm.envAddress("BASE_UNIVERSAL_MARKETPLACE_FUTURE_OWNER");
        uint256 premium = vm.envUint("BASE_UNIVERSAL_MARKETPLACE_PREMIUM");

        _checkAddress("fame", BASE_FAME, address(fame));
        _checkAddress("mirror", BASE_MIRROR, address(fame.fameMirror()));
        _checkAddress("creatorMagic", BASE_CREATOR_MAGIC, address(creatorMagic));
        _checkAddress("childRenderer", BASE_CHILD_RENDERER, address(creatorMagic.childRenderer()));
        _checkAddress("router", BASE_FAME_ROUTER, router);
        _checkAddress("usdc", BASE_USDC, usdc);
        _checkAddress("weth", BASE_WETH, weth);
        _checkAddress("deployer", EXPECTED_DEPLOYER, deployer);
        _checkAddress("owner", EXPECTED_DEPLOYER, owner);
        _checkAddress("feeRecipient", EXPECTED_SAFE, feeRecipient);
        _checkAddress("futureOwner", EXPECTED_SAFE, futureOwner);
        if (premium != EXPECTED_PREMIUM) {
            revert ValueMismatch("premium", EXPECTED_PREMIUM, premium);
        }

        new ValidateFameRouterBase().run();
        _validateStack(fame, creatorMagic, router, feeRecipient, deployer);
        (market, checkout) =
            _deployMarketplaceStack(fame, creatorMagic, router, usdc, weth, premium, feeRecipient, owner, deployer);
    }

    function deployMarketplaceStack(
        Fame fame,
        CreatorArtistMagic creatorMagic,
        address router,
        address usdc,
        address weth,
        uint256 premium,
        address feeRecipient,
        address owner,
        address sender
    ) public returns (UniversalPoolArtMarketplace market, FameMarketplaceCheckout checkout) {
        _requireBase();
        _validateStack(fame, creatorMagic, router, feeRecipient, sender);
        if (owner != sender) revert ConfigurationMismatch("owner", sender, owner);
        (market, checkout) =
            _deployMarketplaceStack(fame, creatorMagic, router, usdc, weth, premium, feeRecipient, owner, sender);
    }

    function _deployMarketplaceStack(
        Fame fame,
        CreatorArtistMagic creatorMagic,
        address router,
        address usdc,
        address weth,
        uint256 premium,
        address feeRecipient,
        address owner,
        address sender
    ) internal returns (UniversalPoolArtMarketplace market, FameMarketplaceCheckout checkout) {
        vm.startBroadcast(sender);
        market = new UniversalPoolArtMarketplace(
            payable(address(fame)), address(creatorMagic), premium, feeRecipient, owner
        );
        checkout = new FameMarketplaceCheckout(router, address(market), payable(address(fame)), usdc, weth);
        market.setAuthorizedCheckout(address(checkout));
        vm.stopBroadcast();
    }

    function _validateStack(
        Fame fame,
        CreatorArtistMagic creatorMagic,
        address router,
        address feeRecipient,
        address deployer
    ) internal view {
        if (
            address(fame.fameMirror()) == address(0) || address(fame.renderer()) != address(creatorMagic)
                || address(creatorMagic.fame()) != address(fame) || creatorMagic.owner() != deployer
                || keccak256(bytes(fame.name())) != keccak256("Society")
                || keccak256(bytes(fame.symbol())) != keccak256("FAME") || fame.unit() != EXPECTED_UNIT
        ) {
            revert CanonicalStackMismatch();
        }
        if (!fame.getSkipNFT(feeRecipient)) revert FeeRecipientNotSkippingNFT(feeRecipient);
        if (!fame.getSkipNFT(router)) revert RouterNotSkippingNFT(router);
    }

    function _requireBase() internal view {
        if (block.chainid != BASE_CHAIN_ID) revert ChainIdMismatch(BASE_CHAIN_ID, block.chainid);
    }

    function _checkAddress(string memory field, address expected, address actual) internal pure {
        if (actual != expected) revert ConfigurationMismatch(field, expected, actual);
    }
}
