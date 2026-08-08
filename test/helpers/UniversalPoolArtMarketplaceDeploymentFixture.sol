// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {CreatorArtistMagic} from "../../src/CreatorArtistMagic.sol";
import {Fame} from "../../src/Fame.sol";
import {FameMarketplaceCheckout} from "../../src/FameMarketplaceCheckout.sol";
import {UniversalPoolArtMarketplace} from "../../src/UniversalPoolArtMarketplace.sol";

/// @dev Test-only deployment and lifecycle fixture. Production submission is owned by the
/// receipt-aware viem state machine in js/deploy/base-universal-pool-art-marketplace.mjs.
contract UniversalPoolArtMarketplaceDeploymentFixture is Script {
    uint256 internal constant BASE_CHAIN_ID = 8453;
    uint256 internal constant EXPECTED_UNIT = 1_000_000 ether;
    address public constant SOCIETY_SAFE = 0xC952C53D8B63919e372caa2E6FEe605ee24E4D3D;

    error ChainIdMismatch(uint256 expected, uint256 actual);
    error CanonicalStackMismatch();
    error ConfigurationMismatch(string field, address expected, address actual);
    error RouterNotSkippingNFT(address router);
    error UnexpectedOwner(address expected, address actual);
    error UnexpectedCheckout(address expected, address actual);
    error CodeMissing(address target);
    error OwnerMismatch(address expected, address actual);
    error FutureOwnerMismatch(address expected, address actual);
    error FutureOwnerIsCurrentOwner(address owner);
    error MarketplaceNotPaused();

    struct DeploymentConfig {
        address router;
        address usdc;
        address weth;
        uint256 communityFee;
        uint256 providerFee;
        address feeRecipient;
        address owner;
        uint256 activeProviderCap;
        address sender;
    }

    function deployMarketplaceStack(Fame fame, CreatorArtistMagic creatorMagic, DeploymentConfig memory config)
        public
        returns (UniversalPoolArtMarketplace market, FameMarketplaceCheckout checkout)
    {
        _requireBase();
        _validateStack(fame, creatorMagic, config.router, config.sender);
        if (config.owner != config.sender) revert ConfigurationMismatch("owner", config.sender, config.owner);

        vm.startPrank(config.sender);
        market = new UniversalPoolArtMarketplace(
            payable(address(fame)),
            address(creatorMagic),
            config.communityFee,
            config.providerFee,
            config.feeRecipient,
            config.owner,
            config.activeProviderCap
        );
        checkout = new FameMarketplaceCheckout(
            config.router, address(market), payable(address(fame)), config.usdc, config.weth
        );
        market.setAuthorizedCheckout(address(checkout));
        vm.stopPrank();
    }

    function activateMarketplace(UniversalPoolArtMarketplace market, FameMarketplaceCheckout checkout, address owner)
        public
    {
        _requireBase();
        if (market.owner() != owner) revert UnexpectedOwner(owner, market.owner());
        if (market.authorizedCheckout() != address(checkout)) {
            revert UnexpectedCheckout(address(checkout), market.authorizedCheckout());
        }

        vm.prank(owner);
        market.unpause();
    }

    function validateHandoff(UniversalPoolArtMarketplace market, address expectedOwner, address futureOwner)
        external
        view
    {
        if (address(market).code.length == 0) revert CodeMissing(address(market));
        if (market.owner() != expectedOwner) revert OwnerMismatch(expectedOwner, market.owner());
        if (futureOwner != SOCIETY_SAFE) revert FutureOwnerMismatch(SOCIETY_SAFE, futureOwner);
        if (futureOwner == market.owner()) revert FutureOwnerIsCurrentOwner(futureOwner);
        if (SOCIETY_SAFE.code.length == 0) revert CodeMissing(SOCIETY_SAFE);
        if (!market.paused()) revert MarketplaceNotPaused();
    }

    function _validateStack(Fame fame, CreatorArtistMagic creatorMagic, address router, address deployer)
        internal
        view
    {
        if (
            address(fame.fameMirror()) == address(0) || address(fame.renderer()) != address(creatorMagic)
                || address(creatorMagic.fame()) != address(fame) || creatorMagic.owner() != deployer
                || keccak256(bytes(fame.name())) != keccak256("Society")
                || keccak256(bytes(fame.symbol())) != keccak256("FAME") || fame.unit() != EXPECTED_UNIT
        ) {
            revert CanonicalStackMismatch();
        }
        if (!fame.getSkipNFT(router)) revert RouterNotSkippingNFT(router);
    }

    function _requireBase() internal view {
        if (block.chainid != BASE_CHAIN_ID) revert ChainIdMismatch(BASE_CHAIN_ID, block.chainid);
    }
}
