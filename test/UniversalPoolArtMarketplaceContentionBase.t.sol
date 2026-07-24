// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {UniversalPoolArtMarketplaceForkBaseTestBase} from "./UniversalPoolArtMarketplaceForkBase.t.sol";

contract UniversalPoolArtMarketplaceContentionBaseTest is UniversalPoolArtMarketplaceForkBaseTestBase {
    function testOrderedPoolContendersProduceOneSettlementAndOneStaleAttempt() public {
        _selectLatestBaseFork();
        UniversalPoolArtMarketplace market = _deployOneShellMarket();
        uint256 shellId = _ownedTokenAt(address(market), 0);
        uint256 mintSource = _findMintPoolToken();
        uint256 burnSource = _findBurnPoolToken();
        bytes32 mintArtwork = market.artworkHash(mintSource);
        bytes32 burnArtwork = market.artworkHash(burnSource);
        uint256 premium = market.premium();
        uint256 total = fame.unit() + premium;
        _fundAndApprove(BUYER_ONE, market, total);
        _fundAndApprove(BUYER_TWO, market, total);

        vm.prank(DEPLOYER);
        market.unpause();
        uint256 feeBefore = fame.balanceOf(SAFE);
        vm.recordLogs();

        vm.prank(BUYER_ONE);
        market.purchasePool(shellId, mintSource, mintArtwork, premium, 0, MINT_RECIPIENT);

        bytes memory staleAttempt =
            abi.encodeCall(market.purchasePool, (shellId, burnSource, burnArtwork, premium, 0, BURN_RECIPIENT));
        vm.prank(BUYER_TWO);
        (bool staleSucceeded, bytes memory staleRevert) = address(market).call(staleAttempt);

        assertFalse(staleSucceeded, "ordered stale contender succeeded");
        assertEq(
            _revertSelector(staleRevert),
            UniversalPoolArtMarketplace.UnavailableShell.selector,
            "ordered contender failed for the wrong reason"
        );
        assertEq(_purchaseEventCount(vm.getRecordedLogs(), address(market)), 1, "contention event count mismatch");
        assertEq(fame.balanceOf(SAFE) - feeBefore, premium, "contention charged more than one premium");
        assertEq(mirror.ownerAt(shellId), MINT_RECIPIENT, "winning recipient mismatch");
        assertNotEq(mirror.ownerAt(shellId), BURN_RECIPIENT, "stale recipient received the shell");
        assertEq(market.inventory(), 1, "ordered contention changed one-shell inventory");
    }

    function testSameBlockPreparedHeldAttemptsProduceExactlyOneSettlement() public {
        _selectLatestBaseFork();
        UniversalPoolArtMarketplace market = _deployOneShellMarket();
        uint256 shellId = _ownedTokenAt(address(market), 0);
        bytes32 artwork = market.artworkHash(shellId);
        uint256 premium = market.premium();
        uint256 total = fame.unit() + premium;
        _fundAndApprove(BUYER_ONE, market, total);
        _fundAndApprove(BUYER_TWO, market, total);

        bytes memory firstAttempt = abi.encodeCall(market.purchaseHeld, (shellId, artwork, premium, 0, HELD_RECIPIENT));
        bytes memory secondAttempt =
            abi.encodeCall(market.purchaseHeld, (shellId, artwork, premium, 0, DISTINCT_RECIPIENT));

        vm.prank(DEPLOYER);
        market.unpause();
        uint256 preparedAtBlock = block.number;
        uint256 feeBefore = fame.balanceOf(SAFE);
        vm.recordLogs();

        vm.prank(BUYER_ONE);
        (bool firstSucceeded,) = address(market).call(firstAttempt);
        vm.prank(BUYER_TWO);
        (bool secondSucceeded, bytes memory secondRevert) = address(market).call(secondAttempt);

        assertTrue(firstSucceeded, "first prepared attempt failed");
        assertFalse(secondSucceeded, "second prepared attempt succeeded");
        assertEq(block.number, preparedAtBlock, "prepared attempts did not settle in one block");
        assertEq(
            _revertSelector(secondRevert),
            UniversalPoolArtMarketplace.UnavailableShell.selector,
            "same-block contender failed for the wrong reason"
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_purchaseEventCount(logs, address(market)), 1, "same-block event count mismatch");
        assertEq(fame.balanceOf(SAFE) - feeBefore, premium, "same-block race charged more than one premium");
        assertEq(mirror.ownerAt(shellId), HELD_RECIPIENT, "same-block winner mismatch");
        assertNotEq(mirror.ownerAt(shellId), DISTINCT_RECIPIENT, "same-block loser received the shell");
        assertEq(market.inventory(), 1, "same-block contention changed one-shell inventory");
    }
}
