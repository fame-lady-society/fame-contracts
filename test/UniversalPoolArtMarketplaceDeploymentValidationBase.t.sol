// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {ActivateBaseUniversalPoolArtMarketplace} from "../script/ActivateBaseUniversalPoolArtMarketplace.s.sol";
import {DeployBaseUniversalPoolArtMarketplace} from "../script/DeployBaseUniversalPoolArtMarketplace.s.sol";
import {ValidateBaseUniversalPoolArtMarketplace} from "../script/ValidateBaseUniversalPoolArtMarketplace.s.sol";
import {UniversalPoolArtMarketplaceTestBase} from "./helpers/UniversalPoolArtMarketplaceTestBase.sol";

contract UniversalPoolArtMarketplaceDeploymentValidationBaseTest is UniversalPoolArtMarketplaceTestBase {
    uint256 internal constant BASE_CHAIN_ID = 8453;
    uint256 internal constant PREMIUM = 30_000 ether;
    uint256 internal constant REQUIRED_INVENTORY = 1;
    address internal constant DEPLOYER = 0xD52E2A6bBcEba9673440e4D7843Db6713E9B6FD9;
    address internal constant SAFE = 0xC952C53D8B63919e372caa2E6FEe605ee24E4D3D;

    DeployBaseUniversalPoolArtMarketplace internal deployer;
    ValidateBaseUniversalPoolArtMarketplace internal validator;
    ActivateBaseUniversalPoolArtMarketplace internal activator;

    function setUp() public override {
        super.setUp();
        vm.chainId(BASE_CHAIN_ID);

        deployer = new DeployBaseUniversalPoolArtMarketplace();
        validator = new ValidateBaseUniversalPoolArtMarketplace();
        activator = new ActivateBaseUniversalPoolArtMarketplace();

        vm.prank(SAFE);
        fame.setSkipNFT(true);
        creatorMagic.transferOwnership(DEPLOYER);
        fame.transfer(SAFE, fame.unit());
    }

    function _fameName() internal pure override returns (string memory) {
        return "Society";
    }

    function testOneShellLifecycleDeploysPausedSeedsAndActivatesFromDeployer() public {
        uint256 unit = fame.unit();
        uint256 safeBalanceBefore = fame.balanceOf(SAFE);

        UniversalPoolArtMarketplace deployed =
            deployer.deployMarketplace(fame, creatorMagic, PREMIUM, SAFE, DEPLOYER, DEPLOYER);

        assertTrue(deployed.paused());
        assertEq(deployed.owner(), DEPLOYER);
        assertEq(deployed.feeRecipient(), SAFE);

        vm.prank(SAFE);
        fame.transfer(DEPLOYER, unit);
        assertEq(safeBalanceBefore - fame.balanceOf(SAFE), unit);
        assertEq(fame.balanceOf(DEPLOYER), unit);

        vm.startPrank(DEPLOYER);
        creatorMagic.grantRoles(address(deployed), CREATOR_MAGIC_BANISHER_ROLE);
        fame.transfer(address(deployed), unit);
        vm.stopPrank();

        validator.validateMarketplace(
            fame,
            mirror,
            creatorMagic,
            deployed,
            address(childRenderer),
            ValidateBaseUniversalPoolArtMarketplace.MarketplaceExpectations({
                owner: DEPLOYER, feeRecipient: SAFE, premium: PREMIUM, inventory: REQUIRED_INVENTORY, paused: true
            })
        );

        activator.activateMarketplace(deployed, DEPLOYER);

        validator.validateMarketplace(
            fame,
            mirror,
            creatorMagic,
            deployed,
            address(childRenderer),
            ValidateBaseUniversalPoolArtMarketplace.MarketplaceExpectations({
                owner: DEPLOYER, feeRecipient: SAFE, premium: PREMIUM, inventory: REQUIRED_INVENTORY, paused: false
            })
        );
    }
}
