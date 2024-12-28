// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {GovSociety} from "../src/GovSociety.sol";
import {FAMEusGovernor} from "../src/FameusGovernor.sol";
import {FAMEusTimelockController} from "../src/FameusTimelockController.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {StubBalanceOf} from "./mocks/StubBalanceOf.sol";
import {ITokenURIGenerator} from "../src/ITokenURIGenerator.sol";
import {EchoMetadata} from "./mocks/EchoMetadata.sol";
import {ERC721} from "@openzeppelin5/contracts/token/ERC721/ERC721.sol";
import {IGovernor} from "@openzeppelin5/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin5/contracts/governance/TimelockController.sol";

contract GovSocietyTest is Test {
    GovSociety public govSociety;
    FAMEusTimelockController public fameusTimelockController;
    FAMEusGovernor public fameusGovernor;
    FameMirror public fameMirror;
    Fame public fame;
    StubBalanceOf public stubBalanceOf;
    address public admin = makeAddr("admin");

    function setUp() public {
        stubBalanceOf = new StubBalanceOf();
        fame = new Fame("Fame", "FAME", address(stubBalanceOf));
        fameMirror = FameMirror(payable(fame.mirrorERC721()));
        govSociety = new GovSociety(
            address(fameMirror),
            admin,
            address(new EchoMetadata())
        );


        fameusTimelockController = new FAMEusTimelockController(
            govSociety,
            1 days,
            admin,
            1 weeks,
            5 days,
            1
        );

        fameusGovernor = fameusTimelockController.governor();
    }

    function test_Quorum() public {
        // Test when supply < 88
        assertEq(fameusGovernor.quorum(0), 0);

        // Mint 88 tokens to test quorum calculation
        fame.transfer(address(111), 88 * 10 ** 24);
        vm.startPrank(address(111));
        uint256[] memory tokenIds = new uint256[](88);
        for (uint256 i = 0; i < 88; i++) {
            tokenIds[i] = i + 1;
            fameMirror.approve(address(govSociety), i + 1);
        }
        govSociety.depositFor(address(111), tokenIds);
        vm.stopPrank();

        // With 88 tokens, quorum should be 11 (88/8)
        assertEq(fameusGovernor.quorum(0), 11);

        // Test with 100 tokens
        fame.transfer(address(111), 12 * 10 ** 24); // Add 12 more for 100 total
        vm.startPrank(address(111));
        uint256[] memory moreTokenIds = new uint256[](12);
        for (uint256 i = 0; i < 12; i++) {
            moreTokenIds[i] = i + 89;
            fameMirror.approve(address(govSociety), i + 89);
        }
        govSociety.depositFor(address(111), moreTokenIds);
        vm.stopPrank();

        // With 100 tokens, quorum should be 12 (nearest multiple of 8 is 96, then divided by 8)
        assertEq(fameusGovernor.quorum(0), 12);
    }
    function test_ExecuteTransactionAdmin() public {
        // Setup voting tokens
        fame.transfer(admin, 100 * 10 ** 24);
        vm.startPrank(admin);

        // give token 1 to timelock

        fameMirror.setApprovalForAll(address(govSociety), true);
        uint256[] memory tokenIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            tokenIds[i] = i + 1;
        }
        govSociety.depositFor(admin, tokenIds);

        // give token 1 to dao
        fame.transfer(address(fameusTimelockController), 1);

        // Delegate votes to self
        govSociety.delegate(admin);

        // Let one block pass so the delegate snapshot is recorded:
        vm.warp(block.timestamp + 1);

        // Create a simple proposal
        address[] memory targets = new address[](1);
        targets[0] = address(govSociety);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        // Call to set approval on a fake address
        calldatas[0] = abi.encodeWithSelector(
            ERC721.setApprovalForAll.selector,
            address(1),
            true
        );
        string memory description = "Set approval for all";

        uint256 proposalId = fameusGovernor.propose(
            targets,
            values,
            calldatas,
            description
        );

        // Wait for voting delay
        vm.warp(block.timestamp + fameusGovernor.votingDelay() + 1);

        // Cast vote
        fameusGovernor.castVote(proposalId, 1); // Vote in favor

        // Wait for voting period to end
        vm.warp(block.timestamp + fameusGovernor.votingPeriod() + 1);

        // Queue the proposal
        bytes32 descriptionHash = keccak256(bytes(description));
        fameusGovernor.queue(targets, values, calldatas, descriptionHash);

        // Wait for timelock
        vm.warp(block.timestamp + 1 days + 1);

        // Execute
        fameusGovernor.execute(targets, values, calldatas, descriptionHash);

        // Verify token was approved
        assertTrue(
            govSociety.isApprovedForAll(
                address(fameusTimelockController),
                address(1)
            )
        );
        vm.stopPrank();
    }

    function test_CancelProposal() public {
        // Setup voting tokens
        address member1 = makeAddr("member1");
        fame.transfer(member1, 100 * 10 ** 24);
        vm.startPrank(member1);

        // give token 1 to timelock

        fameMirror.setApprovalForAll(address(govSociety), true);
        uint256[] memory tokenIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            tokenIds[i] = i + 1;
        }
        govSociety.depositFor(member1, tokenIds);

        // give token 1 to dao
        fame.transfer(address(fameusTimelockController), 1);

        // Delegate votes to self
        govSociety.delegate(member1);

        // Let one block pass so the delegate snapshot is recorded:
        vm.warp(block.timestamp + 1);

        // Create a simple proposal
        address[] memory targets = new address[](1);
        targets[0] = address(govSociety);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        // Call to set approval on a fake address
        calldatas[0] = abi.encodeWithSelector(
            ERC721.setApprovalForAll.selector,
            address(1),
            true
        );
        string memory description = "Set approval for all";

        uint256 proposalId = fameusGovernor.propose(
            targets,
            values,
            calldatas,
            description
        );

        // Wait for voting delay
        vm.warp(block.timestamp + fameusGovernor.votingDelay() + 1);

        // Cast vote
        fameusGovernor.castVote(proposalId, 1); // Vote in favor

        // Wait for voting period to end
        vm.warp(block.timestamp + fameusGovernor.votingPeriod() + 1);

        // queue the proposal and expect the CallSalt event
        bytes32 descriptionHash = keccak256(bytes(description));
        bytes32 timelockProposalId = 0x6b6d667d9eceb0290fae8f2ac7e2320ab5aa544f617a3950366f64f48fbff104;
        fameusGovernor.queue(targets, values, calldatas, descriptionHash);

        vm.stopPrank();

        vm.startPrank(admin);
        fameusTimelockController.cancel(timelockProposalId);
        vm.stopPrank();

        // Verify the proposal was canceled
        assertTrue(
            fameusGovernor.state(proposalId) == IGovernor.ProposalState.Canceled
        );

        // Verify an attempt to execute the proposal will revert
        vm.warp(block.timestamp + 1 days + 1);
        vm.expectRevert();
        fameusGovernor.execute(targets, values, calldatas, descriptionHash);
    }
}
