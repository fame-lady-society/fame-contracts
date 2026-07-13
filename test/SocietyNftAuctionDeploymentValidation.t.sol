// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {DeploySocietyNftAuction} from "../script/DeploySocietyNftAuction.s.sol";
import {ValidateSocietyNftAuctionBase} from "../script/ValidateSocietyNftAuctionBase.s.sol";
import {SocietyNftAuction} from "../src/SocietyNftAuction.sol";
import {ForceEth, MockSocietyNftMirror} from "./mocks/SocietyNftAuctionActors.sol";

contract WrongAuctionCode {}

contract DeploySocietyNftAuctionHarness is DeploySocietyNftAuction {
    function checkDeployerOwner(address deployerAddress, address configuredOwner) external pure {
        requireDeployerOwner(deployerAddress, configuredOwner);
    }
}

contract SocietyNftAuctionDeploymentValidationTest is Test {
    using stdStorage for StdStorage;

    address internal constant MIRROR = 0xBB5ED04dD7B207592429eb8d599d103CCad646c4;
    address internal owner = makeAddr("owner");

    DeploySocietyNftAuction internal deployer;
    ValidateSocietyNftAuctionBase internal validator;

    function setUp() public {
        vm.chainId(8453);
        deployer = new DeploySocietyNftAuction();
        validator = new ValidateSocietyNftAuctionBase();
    }

    function testDeploymentRejectsWrongChainAndZeroOwner() public {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(DeploySocietyNftAuction.ChainIdMismatch.selector, 8453, 1));
        deployer.deployConfigured(owner);

        vm.chainId(8453);
        vm.expectRevert(DeploySocietyNftAuction.ZeroOwner.selector);
        deployer.deployConfigured(address(0));
    }

    function testRunRejectsDeployerThatIsNotConfiguredOwner() public {
        DeploySocietyNftAuctionHarness harness = new DeploySocietyNftAuctionHarness();
        address deployerAddress = makeAddr("deployer");
        address configuredOwner = address(0xB0B);

        vm.expectRevert(
            abi.encodeWithSelector(
                DeploySocietyNftAuction.DeployerMustBeOwner.selector, deployerAddress, configuredOwner
            )
        );
        harness.checkDeployerOwner(deployerAddress, configuredOwner);
    }

    function testRunRejectsWrongChainBeforeReadingPrivateKey() public {
        vm.chainId(1);
        vm.setEnv("BASE_SOCIETY_NFT_AUCTION_OWNER", vm.toString(owner));
        vm.setEnv("BASE_DEPLOYER_PRIVATE_KEY", "not-a-private-key");

        vm.expectRevert(abi.encodeWithSelector(DeploySocietyNftAuction.ChainIdMismatch.selector, 8453, 1));
        deployer.run();
    }

    function testDeploymentProducesPristineAuction() public {
        SocietyNftAuction auction = deployer.deployConfigured(owner);

        assertEq(auction.owner(), owner);
        assertEq(auction.SOCIETY_NFT(), MIRROR);
        assertEq(uint8(auction.lifecycle()), uint8(SocietyNftAuction.Lifecycle.Unstarted));
        assertEq(auction.startTime(), 0);
        assertEq(auction.endTime(), 0);
        assertEq(auction.highestBid(), 0);
        assertEq(auction.failedRefundDonations(), 0);
        assertEq(auction.withdrawableProceeds(), 0);
    }

    function testValidatorAcceptsExactRuntimeAndRejectsWrongOwnerOrCode() public {
        SocietyNftAuction auction = deployer.deployConfigured(owner);
        validator.validateAuction(auction, owner);

        vm.expectRevert(
            abi.encodeWithSelector(ValidateSocietyNftAuctionBase.OwnerMismatch.selector, address(0xBAD), owner)
        );
        validator.validateAuction(auction, address(0xBAD));

        WrongAuctionCode wrong = new WrongAuctionCode();
        vm.expectRevert(ValidateSocietyNftAuctionBase.RuntimeCodeMismatch.selector);
        validator.validateAuction(SocietyNftAuction(payable(address(wrong))), owner);
    }

    function testValidatorRejectsWrongChain() public {
        SocietyNftAuction auction = deployer.deployConfigured(owner);
        vm.chainId(1);

        vm.expectRevert(
            abi.encodeWithSelector(ValidateSocietyNftAuctionBase.ChainIdMismatch.selector, uint256(8453), uint256(1))
        );
        validator.validateAuction(auction, owner);
    }

    function testValidatorRejectsActiveLifecycle() public {
        SocietyNftAuction auction = deployer.deployConfigured(owner);
        stdstore.target(address(auction)).sig("lifecycle()").checked_write(uint256(SocietyNftAuction.Lifecycle.Active));

        vm.expectRevert(ValidateSocietyNftAuctionBase.LifecycleNotPristine.selector);
        validator.validateAuction(auction, owner);
    }

    function testValidatorRejectsTimingState() public {
        SocietyNftAuction auction = deployer.deployConfigured(owner);
        stdstore.target(address(auction)).sig("startTime()").checked_write(uint256(1));

        vm.expectRevert(ValidateSocietyNftAuctionBase.TimingStateNotPristine.selector);
        validator.validateAuction(auction, owner);
    }

    function testValidatorRejectsTrackedEconomicState() public {
        SocietyNftAuction auction = deployer.deployConfigured(owner);
        stdstore.target(address(auction)).sig("highestBid()").checked_write(uint256(1 ether));

        vm.expectRevert(ValidateSocietyNftAuctionBase.EconomicStateNotPristine.selector);
        validator.validateAuction(auction, owner);
    }

    function testValidatorAllowsForcedEthWhileOtherwisePristine() public {
        SocietyNftAuction auction = deployer.deployConfigured(owner);
        vm.deal(address(this), 1 ether);
        ForceEth force = new ForceEth{value: 1 ether}();
        force.force(payable(address(auction)));

        validator.validateAuction(auction, owner);
        assertEq(address(auction).balance, 1 ether);
    }

    function testValidatorBindsIntendedTokenOwnerAndApproval() public {
        MockSocietyNftMirror implementation = new MockSocietyNftMirror();
        vm.etch(MIRROR, address(implementation).code);
        MockSocietyNftMirror mirror = MockSocietyNftMirror(MIRROR);
        SocietyNftAuction auction = deployer.deployConfigured(owner);
        mirror.mint(owner, 42);

        vm.expectRevert(ValidateSocietyNftAuctionBase.LotNotApproved.selector);
        validator.validateIntendedLot(auction, 42);

        vm.prank(owner);
        mirror.approve(address(auction), 42);
        validator.validateIntendedLot(auction, 42);
    }

    function testValidatorRejectsIntendedTokenOwnerMismatch() public {
        MockSocietyNftMirror implementation = new MockSocietyNftMirror();
        vm.etch(MIRROR, address(implementation).code);
        MockSocietyNftMirror mirror = MockSocietyNftMirror(MIRROR);
        SocietyNftAuction auction = deployer.deployConfigured(owner);
        address wrongOwner = makeAddr("wrongOwner");
        mirror.mint(wrongOwner, 42);

        vm.expectRevert(
            abi.encodeWithSelector(ValidateSocietyNftAuctionBase.LotOwnerMismatch.selector, owner, wrongOwner)
        );
        validator.validateIntendedLot(auction, 42);
    }
}
