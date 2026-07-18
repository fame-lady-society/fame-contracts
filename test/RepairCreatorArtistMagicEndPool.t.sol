// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LibString} from "solady/utils/LibString.sol";
import {
    ICreatorArtistMagicRepair,
    RepairCreatorArtistMagicEndPool
} from "../script/RepairCreatorArtistMagicEndPool.s.sol";

contract RepairCreatorArtistMagicEndPoolHarness is RepairCreatorArtistMagicEndPool {
    function runWithMode(bool execute, bool broadcast) external {
        _run(execute, broadcast);
    }

    function assertContractState() external view {
        _assertContractState();
    }

    function assertPreState() external view {
        _assertPreState(repairManifest());
    }

    function assertBroadcastTarget(address confirmedTarget) external pure {
        _assertBroadcastTarget(confirmedTarget);
    }

    function assertBroadcastSigner(address operator) external view {
        _assertBroadcastSigner(ICreatorArtistMagicRepair(TARGET), operator);
    }
}

contract RepairCreatorArtistMagicTargetMock {
    address public fame;
    address public childRenderer;
    uint16 public nextTokenId;
    address public owner;
    uint256 public updateCalls;

    mapping(address user => uint256 roles) internal roleMasks;
    mapping(uint256 tokenId => uint16 metadataId) internal metadataIds;
    mapping(uint256 tokenId => bool inMintPool) internal mintPool;
    mapping(uint256 tokenId => string uri) internal tokenUris;

    function configure(address fame_, address childRenderer_, uint16 nextTokenId_, address owner_) external {
        fame = fame_;
        childRenderer = childRenderer_;
        nextTokenId = nextTokenId_;
        owner = owner_;
    }

    function setNextTokenId(uint16 nextTokenId_) external {
        nextTokenId = nextTokenId_;
    }

    function configureToken(uint256 tokenId, uint16 metadataId, bool inMintPool, string calldata uri) external {
        metadataIds[tokenId] = metadataId;
        mintPool[tokenId] = inMintPool;
        tokenUris[tokenId] = uri;
    }

    function setRoles(address user, uint256 roles) external {
        roleMasks[user] = roles;
    }

    function getTokenMetadataId(uint256 tokenId) external view returns (uint16) {
        return metadataIds[tokenId];
    }

    function isTokenInMintPool(uint256 tokenId) external view returns (bool) {
        return mintPool[tokenId];
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        return tokenUris[tokenId];
    }

    function rolesOf(address user) external view returns (uint256) {
        return roleMasks[user];
    }

    function updateMetadata(uint256 tokenId, string calldata newMetadataUrl) external {
        ++updateCalls;
        metadataIds[tokenId] = 1;
        tokenUris[tokenId] = newMetadataUrl;
    }

    function grantRoles(address user, uint256 roles) external payable {
        roleMasks[user] |= roles;
    }

    function revokeRoles(address user, uint256 roles) external payable {
        roleMasks[user] &= ~roles;
    }
}

contract FameRepairTargetMock {
    address public renderer;

    function setRenderer(address renderer_) external {
        renderer = renderer_;
    }
}

contract RepairCreatorArtistMagicEndPoolTest is Test {
    using LibString for string;

    address internal constant OWNER = address(0x0B0B);
    address internal constant CREATOR = address(0xC0DE);
    uint256 internal constant CREATOR_ROLE = 1 << 1;

    RepairCreatorArtistMagicEndPoolHarness internal repairScript;
    RepairCreatorArtistMagicTargetMock internal target;
    FameRepairTargetMock internal fame;

    function setUp() public {
        repairScript = new RepairCreatorArtistMagicEndPoolHarness();

        vm.etch(repairScript.TARGET(), address(new RepairCreatorArtistMagicTargetMock()).code);
        vm.etch(repairScript.FAME(), address(new FameRepairTargetMock()).code);
        target = RepairCreatorArtistMagicTargetMock(repairScript.TARGET());
        fame = FameRepairTargetMock(repairScript.FAME());

        vm.chainId(repairScript.BASE_CHAIN_ID());
        fame.setRenderer(address(target));
        target.configure(
            address(fame), repairScript.LEGACY_CHILD_RENDERER(), repairScript.EXPECTED_NEXT_TOKEN_ID(), OWNER
        );

        RepairCreatorArtistMagicEndPool.Repair[5] memory repairs = repairScript.repairManifest();
        for (uint256 i; i < repairs.length; ++i) {
            target.configureToken(repairs[i].tokenId, 0, true, repairs[i].expectedCurrentUri);
        }
    }

    function testDefaultModeIsInspectOnlyAndDoesNotUpdateMetadata() public {
        assertFalse(repairScript.DEFAULT_EXECUTE());
        assertFalse(repairScript.DEFAULT_BROADCAST());
        repairScript.runWithMode(repairScript.DEFAULT_EXECUTE(), repairScript.DEFAULT_BROADCAST());

        assertEq(target.updateCalls(), 0);
        RepairCreatorArtistMagicEndPool.Repair[5] memory repairs = repairScript.repairManifest();
        for (uint256 i; i < repairs.length; ++i) {
            assertEq(target.getTokenMetadataId(repairs[i].tokenId), 0);
            assertEq(target.tokenURI(repairs[i].tokenId), repairs[i].expectedCurrentUri);
        }
    }

    function testForkSimulationUpdatesAllMetadataAndRestoresExactRoleMask() public {
        uint256 unrelatedRole = 1 << 7;
        target.setRoles(OWNER, unrelatedRole);

        repairScript.runWithMode(true, false);

        assertEq(target.updateCalls(), repairScript.REPAIR_COUNT());
        assertEq(target.rolesOf(OWNER), unrelatedRole);

        RepairCreatorArtistMagicEndPool.Repair[5] memory repairs = repairScript.repairManifest();
        for (uint256 i; i < repairs.length; ++i) {
            assertEq(target.getTokenMetadataId(repairs[i].tokenId), 1);
            assertEq(target.tokenURI(repairs[i].tokenId), repairs[i].intendedUri);
        }
    }

    function testRejectsBroadcastWithoutExecution() public {
        vm.expectRevert(RepairCreatorArtistMagicEndPool.BroadcastFlagRequiresExecution.selector);
        repairScript.runWithMode(false, true);
    }

    function testRejectsWrongBroadcastTargetConfirmation() public {
        address wrongTarget = address(0xBAD);
        vm.expectRevert(
            abi.encodeWithSelector(
                RepairCreatorArtistMagicEndPool.BroadcastTargetConfirmationMismatch.selector,
                repairScript.TARGET(),
                wrongTarget
            )
        );
        repairScript.assertBroadcastTarget(wrongTarget);
    }

    function testAcceptsExactBroadcastTargetConfirmation() public view {
        repairScript.assertBroadcastTarget(repairScript.TARGET());
    }

    function testRejectsUnauthorizedBroadcastSigner() public {
        address unauthorized = address(0xDEAD);
        vm.expectRevert(
            abi.encodeWithSelector(RepairCreatorArtistMagicEndPool.BroadcastSignerUnauthorized.selector, unauthorized)
        );
        repairScript.assertBroadcastSigner(unauthorized);
    }

    function testAcceptsOwnerAndCreatorBroadcastSigners() public {
        repairScript.assertBroadcastSigner(OWNER);

        target.setRoles(CREATOR, CREATOR_ROLE);
        repairScript.assertBroadcastSigner(CREATOR);
    }

    function testRejectsUnexpectedNextTokenId() public {
        target.setNextTokenId(repairScript.EXPECTED_NEXT_TOKEN_ID() + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                RepairCreatorArtistMagicEndPool.NextTokenIdMismatch.selector,
                repairScript.EXPECTED_NEXT_TOKEN_ID(),
                repairScript.EXPECTED_NEXT_TOKEN_ID() + 1
            )
        );
        repairScript.assertContractState();
    }

    function testRejectsAlreadyAssignedMetadataId() public {
        RepairCreatorArtistMagicEndPool.Repair[5] memory repairs = repairScript.repairManifest();
        RepairCreatorArtistMagicEndPool.Repair memory repair = repairs[0];
        target.configureToken(repair.tokenId, 1, true, repair.expectedCurrentUri);

        vm.expectRevert(
            abi.encodeWithSelector(RepairCreatorArtistMagicEndPool.MetadataIdMismatch.selector, repair.tokenId, 0, 1)
        );
        repairScript.assertPreState();
    }

    function testRejectsTokenOutsideMintPool() public {
        RepairCreatorArtistMagicEndPool.Repair[5] memory repairs = repairScript.repairManifest();
        RepairCreatorArtistMagicEndPool.Repair memory repair = repairs[0];
        target.configureToken(repair.tokenId, 0, false, repair.expectedCurrentUri);

        vm.expectRevert(
            abi.encodeWithSelector(RepairCreatorArtistMagicEndPool.TokenNotInExpectedMintPool.selector, repair.tokenId)
        );
        repairScript.assertPreState();
    }

    function testRejectsUnexpectedCurrentUri() public {
        RepairCreatorArtistMagicEndPool.Repair[5] memory repairs = repairScript.repairManifest();
        RepairCreatorArtistMagicEndPool.Repair memory repair = repairs[0];
        string memory unexpectedUri = "https://example.invalid/already-changed.json";
        target.configureToken(repair.tokenId, 0, true, unexpectedUri);

        vm.expectRevert(
            abi.encodeWithSelector(
                RepairCreatorArtistMagicEndPool.UriMismatch.selector,
                repair.tokenId,
                keccak256(bytes(repair.expectedCurrentUri)),
                keccak256(bytes(unexpectedUri))
            )
        );
        repairScript.assertPreState();
    }

    function testManifestMatchesExecutableRepairData() public view {
        string memory json = vm.readFile("script/manifests/creator-artist-magic-end-pool-repair-base.json");
        RepairCreatorArtistMagicEndPool.Repair[5] memory repairs = repairScript.repairManifest();

        assertEq(repairScript.REPAIR_COUNT(), repairs.length);
        assertEq(repairScript.BASE_CHAIN_ID(), vm.parseJsonUint(json, ".chainId"));
        assertEq(repairScript.FAME(), vm.parseJsonAddress(json, ".fame"));
        assertEq(repairScript.TARGET(), vm.parseJsonAddress(json, ".creatorArtistMagic"));
        assertEq(repairScript.LEGACY_CHILD_RENDERER(), vm.parseJsonAddress(json, ".legacyChildRenderer"));
        assertEq(repairScript.EXPECTED_NEXT_TOKEN_ID(), vm.parseJsonUint(json, ".expectedNextTokenId"));

        for (uint256 i; i < repairs.length; ++i) {
            RepairCreatorArtistMagicEndPool.Repair memory repair = repairs[i];
            string memory key = string.concat(".repairs[", vm.toString(i), "]");
            assertEq(repair.tokenId, vm.parseJsonUint(json, string.concat(key, ".tokenId")));
            assertEq(repair.sourceTokenId, vm.parseJsonUint(json, string.concat(key, ".sourceTokenId")));
            assertEq(repair.sourceTransaction, vm.parseJsonBytes32(json, string.concat(key, ".sourceTransaction")));
            assertEq(repair.expectedCurrentUri, vm.parseJsonString(json, string.concat(key, ".currentUrl")));
            assertEq(repair.intendedUri, vm.parseJsonString(json, string.concat(key, ".intendedUrl")));
            assertEq(repair.expectedCalldataHash, vm.parseJsonBytes32(json, string.concat(key, ".updateCalldataHash")));
            assertEq(
                repair.expectedCalldataHash,
                keccak256(
                    abi.encodeCall(ICreatorArtistMagicRepair.updateMetadata, (repair.tokenId, repair.intendedUri))
                )
            );
        }
    }

    function testPublicConfigMatchesExecutableAddresses() public view {
        string memory config = vm.readFile("config/fame-public.env").lower();
        assertTrue(config.contains(string.concat("base_fame_address=", vm.toString(repairScript.FAME()).lower())));
        assertTrue(
            config.contains(
                string.concat("base_creator_artist_magic_legacy_address=", vm.toString(repairScript.TARGET()).lower())
            )
        );
        assertTrue(
            config.contains(
                string.concat(
                    "base_creator_artist_magic_legacy_child_renderer_address=",
                    vm.toString(repairScript.LEGACY_CHILD_RENDERER()).lower()
                )
            )
        );
    }
}
