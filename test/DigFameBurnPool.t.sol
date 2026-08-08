// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DigFameBurnPool} from "../script/DigFameBurnPool.s.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {StubBalanceOf} from "./mocks/StubBalanceOf.sol";

contract TestableDigFameBurnPool is DigFameBurnPool {
    function executeTurn(
        address fameAddress,
        uint256 primaryPrivateKey,
        uint256 secondaryPrivateKey,
        uint256 targetTokenId,
        bool recoverInterrupted
    ) external returns (bool) {
        return _executeTurn(fameAddress, primaryPrivateKey, secondaryPrivateKey, targetTokenId, recoverInterrupted);
    }
}

contract DigFameBurnPoolTest is Test {
    uint256 internal constant PRIMARY_KEY = 0xA11CE;
    uint256 internal constant SECONDARY_KEY = 0xB0B;

    Fame internal fame;
    FameMirror internal mirror;
    TestableDigFameBurnPool internal digger;
    address internal primary;
    address internal secondary;
    uint256 internal unit;

    function setUp() public {
        fame = new Fame("Fame", "FAME", address(new StubBalanceOf()));
        mirror = fame.fameMirror();
        digger = new TestableDigFameBurnPool();
        primary = vm.addr(PRIMARY_KEY);
        secondary = vm.addr(SECONDARY_KEY);
        unit = fame.unit();
    }

    function test_DigsTargetOutOfBurnPoolInOneTurn() public {
        uint256 targetTokenId = _seedTargetInBurnPool();
        uint256 primaryBalanceBefore = fame.balanceOf(primary);

        bool found = digger.executeTurn(address(fame), PRIMARY_KEY, SECONDARY_KEY, targetTokenId, false);

        assertTrue(found);
        assertEq(mirror.ownerAt(targetTokenId), primary);
        assertEq(fame.balanceOf(primary), primaryBalanceBefore);
        assertEq(fame.balanceOf(secondary), 0);
        assertEq(mirror.balanceOf(secondary), 0);
    }

    function test_RunReadsEnvironmentAndExecutesTurn() public {
        uint256 targetTokenId = _seedTargetInBurnPool();
        _configureRun(targetTokenId);
        vm.deal(primary, 1 ether);
        vm.deal(secondary, 1 ether);

        assertTrue(digger.run());
        assertEq(mirror.ownerAt(targetTokenId), primary);

        uint256 expectedChainId = block.chainid;
        vm.chainId(expectedChainId + 1);

        vm.expectRevert(
            abi.encodeWithSelector(DigFameBurnPool.WrongChain.selector, expectedChainId, expectedChainId + 1)
        );
        digger.run();
    }

    function test_RepeatedTurnsDigTargetBehindAnotherBurnedToken() public {
        uint256 targetTokenId = _seedTargetBehindAnotherBurnedToken();

        assertFalse(digger.executeTurn(address(fame), PRIMARY_KEY, SECONDARY_KEY, targetTokenId, false));
        assertTrue(digger.executeTurn(address(fame), PRIMARY_KEY, SECONDARY_KEY, targetTokenId, false));

        assertEq(mirror.ownerAt(targetTokenId), primary);
    }

    function test_RecoversInterruptedOutboundTurn() public {
        uint256 targetTokenId = _seedTargetInBurnPool();
        uint256 primaryBalanceBefore = fame.balanceOf(primary);

        vm.prank(primary);
        fame.transfer(secondary, unit - 1);
        assertEq(fame.balanceOf(secondary), unit - 1);

        vm.expectRevert(
            abi.encodeWithSelector(DigFameBurnPool.InterruptedTurnRequiresRecovery.selector, secondary, unit - 1)
        );
        digger.executeTurn(address(fame), PRIMARY_KEY, SECONDARY_KEY, targetTokenId, false);

        bool found = digger.executeTurn(address(fame), PRIMARY_KEY, SECONDARY_KEY, targetTokenId, true);

        assertTrue(found);
        assertEq(mirror.ownerAt(targetTokenId), primary);
        assertEq(fame.balanceOf(primary), primaryBalanceBefore);
        assertEq(fame.balanceOf(secondary), 0);
    }

    function test_RecoversBeforeReturningSuccessForAlreadyOwnedTarget() public {
        fame.transfer(primary, 3 * unit);
        uint256 primaryBalanceBefore = fame.balanceOf(primary);

        vm.prank(primary);
        fame.transfer(secondary, unit - 1);
        assertEq(mirror.ownerAt(1), primary);

        vm.expectRevert(
            abi.encodeWithSelector(DigFameBurnPool.InterruptedTurnRequiresRecovery.selector, secondary, unit - 1)
        );
        digger.executeTurn(address(fame), PRIMARY_KEY, SECONDARY_KEY, 1, false);

        assertTrue(digger.executeTurn(address(fame), PRIMARY_KEY, SECONDARY_KEY, 1, true));
        assertEq(fame.balanceOf(primary), primaryBalanceBefore);
        assertEq(fame.balanceOf(secondary), 0);
    }

    function test_ReturnsImmediatelyWhenPrimaryAlreadyOwnsTarget() public {
        fame.transfer(primary, unit);

        assertTrue(digger.executeTurn(address(fame), PRIMARY_KEY, SECONDARY_KEY, 1, false));
    }

    function test_RevertsWhenTargetIsOwnedByAnotherAddress() public {
        address other = makeAddr("other");
        fame.transfer(other, unit);

        vm.expectRevert(abi.encodeWithSelector(DigFameBurnPool.TargetOwnedElsewhere.selector, 1, other));
        digger.executeTurn(address(fame), PRIMARY_KEY, SECONDARY_KEY, 1, false);
    }

    function test_RevertsWhenSecondaryContainsDust() public {
        uint256 targetTokenId = _seedTargetInBurnPool();
        fame.transfer(secondary, 1);

        vm.expectRevert(abi.encodeWithSelector(DigFameBurnPool.SecondaryBalanceMustBeZero.selector, 1));
        digger.executeTurn(address(fame), PRIMARY_KEY, SECONDARY_KEY, targetTokenId, false);
    }

    function test_RevertsWhenOutboundTransferWouldNotBurnAnNft() public {
        fame.transfer(primary, (2 * unit) - 1);

        vm.expectRevert(abi.encodeWithSelector(DigFameBurnPool.OutboundTransferWouldNotBurn.selector, primary, 1, 1));
        digger.executeTurn(address(fame), PRIMARY_KEY, SECONDARY_KEY, 2, false);
    }

    function _seedTargetInBurnPool() internal returns (uint256 targetTokenId) {
        address sink = _createSkipSink();
        fame.transfer(primary, 3 * unit);
        vm.prank(primary);
        fame.transfer(sink, unit);

        targetTokenId = 3;
        assertEq(mirror.ownerAt(targetTokenId), address(0));
    }

    function _seedTargetBehindAnotherBurnedToken() internal returns (uint256 targetTokenId) {
        address sink = _createSkipSink();
        fame.transfer(primary, 4 * unit);
        vm.startPrank(primary);
        fame.transfer(sink, unit);
        fame.transfer(sink, unit);
        vm.stopPrank();

        assertEq(mirror.ownerAt(4), address(0));
        assertEq(mirror.ownerAt(3), address(0));
        return 3;
    }

    function _createSkipSink() internal returns (address sink) {
        sink = makeAddr("skip-sink");
        vm.prank(sink);
        fame.setSkipNFT(true);
    }

    function _configureRun(uint256 targetTokenId) internal {
        vm.setEnv("BASE_CHAIN_ID", vm.toString(block.chainid));
        vm.setEnv("BASE_FAME_ADDRESS", vm.toString(address(fame)));
        vm.setEnv("FAME_DIG_PRIMARY_PRIVATE_KEY", vm.toString(PRIMARY_KEY));
        vm.setEnv("FAME_DIG_SECONDARY_PRIVATE_KEY", vm.toString(SECONDARY_KEY));
        vm.setEnv("FAME_DIG_TOKEN_ID", vm.toString(targetTokenId));
    }
}
