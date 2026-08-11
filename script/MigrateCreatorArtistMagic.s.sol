// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";

interface ICreatorArtistMagicMigrationLegacy {
    function owner() external view returns (address);
    function fame() external view returns (address);
    function childRenderer() external view returns (address);
    function nextTokenId() external view returns (uint16);
    function artPoolNext() external view returns (uint256);
    function rolesOf(address user) external view returns (uint256);
    function getTokenMetadataId(uint256 tokenId) external view returns (uint16);
    function revokeRoles(address user, uint256 roles) external payable;
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

interface IFameCreatorArtistMagicMigration {
    function renderer() external view returns (address);
    function rolesOf(address user) external view returns (uint256);
    function setRenderer(address renderer_) external;
}

/**
 * @notice Guarded Base migration from the legacy CreatorArtistMagic renderer to
 * a new CreatorArtistMagic whose child renderer is the repaired legacy contract.
 *
 * Default read-only inspection:
 *
 *   set -a
 *   source config/fame-public.env
 *   set +a
 *   doppler run --config prd -- sh -c \
 *     'BASE_RPC="$RPC_URL" forge script script/MigrateCreatorArtistMagic.s.sol --rpc-url base'
 *
 * Non-broadcasting fork simulation:
 *
 *   set -a
 *   source config/fame-public.env
 *   set +a
 *   doppler run --config prd -- sh -c \
 *     'BASE_RPC="$RPC_URL" CREATOR_ARTIST_MAGIC_MIGRATION_EXECUTE=true \
 *       forge script script/MigrateCreatorArtistMagic.s.sol --rpc-url base'
 *
 * Production broadcasting is intentionally gated behind execute, broadcast,
 * two exact target confirmations, and Foundry's --broadcast flag. Use --slow
 * so the cutover and role cleanup are submitted sequentially. Do not broadcast
 * until the migration manifest and fls-www handoff have been approved.
 */
contract MigrateCreatorArtistMagic is Script {
    struct LegacyRoleRevocation {
        address holder;
        uint256 roleMask;
    }

    uint256 public constant BASE_CHAIN_ID = 8453;
    uint16 public constant EXPECTED_NEXT_TOKEN_ID = 650;
    uint16 public constant EXPECTED_ART_POOL_NEXT = 266;
    uint256 public constant MAX_TOKEN_ID = 888;
    uint256 public constant RENDERER_ROLE = 1 << 0;
    uint256 public constant CREATOR_ROLE = 1 << 1;
    uint256 public constant METADATA_ROLE = 1 << 1;
    bool public constant DEFAULT_EXECUTE = false;
    bool public constant DEFAULT_BROADCAST = false;
    bool public constant BROADCAST_APPROVED = true;

    address public constant FAME = 0xf307e242BfE1EC1fF01a4Cef2fdaa81b10A52418;
    address public constant LEGACY = 0x8091D00A25ebE87A2A1Ef19e1d33689FCAdC3fA5;
    address public constant LEGACY_CHILD_RENDERER = 0xA50C9a918C110CA159fb187F4a55896A4d063878;

    address internal constant CREATOR_1 = 0xF11Ce547ff948a03570B20Eac4a4d7b648693324;
    address internal constant CREATOR_2 = 0x750ea1c5ad297278665f2f8332a8876d6f95E19c;
    address internal constant CREATOR_3 = 0xaE30c908C41407877fE764B5f864eb0F5e536A72;
    address internal constant LEGACY_RENDERER_WALLET = 0x1De45d6811d6796178C0adE37516E510C1E07f77;

    error ChainIdMismatch(uint256 expected, uint256 actual);
    error BroadcastFlagRequiresExecution();
    error BroadcastNotApproved();
    error TargetCodeMissing(address target);
    error FameMismatch(address expected, address actual);
    error ChildRendererMismatch(address expected, address actual);
    error RendererMismatch(address expected, address actual);
    error NextTokenIdMismatch(uint16 expected, uint16 actual);
    error ArtPoolNextMismatch(uint256 expected, uint256 actual);
    error LegacyRoleMismatch(address user, uint256 expected, uint256 actual);
    error OwnerMismatch(address expected, address actual);
    error OperatorMissingMetadataRole(address operator, uint256 roles);
    error BroadcastLegacyConfirmationMismatch(address expected, address actual);
    error BroadcastFameConfirmationMismatch(address expected, address actual);
    error NewRendererOwnerMismatch(address expected, address actual);
    error NewRendererRoleMismatch(address user, uint256 expected, uint256 actual);
    error TokenUriMismatch(uint256 tokenId);
    error RepairPrerequisiteMismatch(uint256 tokenId);

    function run() external returns (CreatorArtistMagic deployed) {
        bool execute = vm.envOr("CREATOR_ARTIST_MAGIC_MIGRATION_EXECUTE", DEFAULT_EXECUTE);
        bool broadcast = vm.envOr("CREATOR_ARTIST_MAGIC_MIGRATION_BROADCAST", DEFAULT_BROADCAST);
        deployed = _run(execute, broadcast);
    }

    function _run(bool execute, bool broadcast) internal returns (CreatorArtistMagic deployed) {
        if (broadcast && !execute) revert BroadcastFlagRequiresExecution();
        if (broadcast && !BROADCAST_APPROVED) revert BroadcastNotApproved();

        _assertPreState();
        _printPlan();
        if (!execute) {
            console2.log("Inspection complete; no contract deployed and no state changed.");
            return CreatorArtistMagic(address(0));
        }

        address operator;
        if (broadcast) {
            _assertBroadcastConfirmations();
            uint256 privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            operator = vm.addr(privateKey);
            _assertOperator(operator);

            vm.startBroadcast(privateKey);
            deployed = _executeMigration();
            vm.stopBroadcast();
        } else {
            operator = ICreatorArtistMagicMigrationLegacy(LEGACY).owner();
            _assertOperator(operator);

            vm.startPrank(operator);
            deployed = _executeMigration();
            vm.stopPrank();
        }

        _assertPostState(deployed, operator);
        console2.log("New CreatorArtistMagic", address(deployed));
        console2.log(
            broadcast
                ? "Broadcast simulation complete; Foundry sends only with --broadcast."
                : "Fork simulation complete; no live transactions were broadcast."
        );
    }

    function creatorWallets() public pure returns (address[3] memory wallets) {
        wallets = [CREATOR_1, CREATOR_2, CREATOR_3];
    }

    function legacyRoleRevocations() public pure returns (LegacyRoleRevocation[5] memory revocations) {
        revocations = [
            LegacyRoleRevocation(LEGACY_CHILD_RENDERER, RENDERER_ROLE),
            LegacyRoleRevocation(CREATOR_1, RENDERER_ROLE | CREATOR_ROLE),
            LegacyRoleRevocation(CREATOR_2, RENDERER_ROLE | CREATOR_ROLE),
            LegacyRoleRevocation(CREATOR_3, RENDERER_ROLE | CREATOR_ROLE),
            LegacyRoleRevocation(LEGACY_RENDERER_WALLET, RENDERER_ROLE)
        ];
    }

    function expectedRepairedUri(uint256 tokenId) public pure returns (string memory) {
        if (tokenId == 645) {
            return "https://gateway.irys.xyz/BkM3YuRbFfecQNFFLJ3B7AHFKMOosD7OAMPb_W-m-4w/96491614803638560672972006391329580542169724233889678455509076750297420919226.json";
        }
        if (tokenId == 646) return "https://gateway.irys.xyz/BfE2c2cNNdpkX2D8Q81Z9ra1fQZQY4RawA2uDtx3AeGe";
        if (tokenId == 647) {
            return "https://gateway.irys.xyz/FD1-OUXP9tuePs8mlTYk25hA8TgnuaZ67RfL3P7Qi08/102830112365573296485305446164386189795940232314654879416395712650316837242972.json";
        }
        if (tokenId == 648) {
            return "https://gateway.irys.xyz/AtQw-VDi13oYZd-fmOiDOp9y6ScNsAsT0HJsqWPuwpU/89130979697350676416287159826765619017698331009266499466147289381976509963047.json";
        }
        if (tokenId == 649) {
            return "https://gateway.irys.xyz/BkM3YuRbFfecQNFFLJ3B7AHFKMOosD7OAMPb_W-m-4w/8192569806743278573033010153761630783437259634776181426633770268721943497377.json";
        }
        return "";
    }

    function _assertPreState() internal view {
        if (block.chainid != BASE_CHAIN_ID) {
            revert ChainIdMismatch(BASE_CHAIN_ID, block.chainid);
        }
        if (FAME.code.length == 0) revert TargetCodeMissing(FAME);
        if (LEGACY.code.length == 0) revert TargetCodeMissing(LEGACY);

        ICreatorArtistMagicMigrationLegacy legacy = ICreatorArtistMagicMigrationLegacy(LEGACY);
        IFameCreatorArtistMagicMigration fame = IFameCreatorArtistMagicMigration(FAME);

        if (legacy.fame() != FAME) revert FameMismatch(FAME, legacy.fame());
        if (legacy.childRenderer() != LEGACY_CHILD_RENDERER) {
            revert ChildRendererMismatch(LEGACY_CHILD_RENDERER, legacy.childRenderer());
        }
        if (fame.renderer() != LEGACY) {
            revert RendererMismatch(LEGACY, fame.renderer());
        }
        if (legacy.nextTokenId() != EXPECTED_NEXT_TOKEN_ID) {
            revert NextTokenIdMismatch(EXPECTED_NEXT_TOKEN_ID, legacy.nextTokenId());
        }
        if (legacy.artPoolNext() != EXPECTED_ART_POOL_NEXT) {
            revert ArtPoolNextMismatch(EXPECTED_ART_POOL_NEXT, legacy.artPoolNext());
        }
        for (uint256 tokenId = 645; tokenId <= 649; ++tokenId) {
            if (
                legacy.getTokenMetadataId(tokenId) == 0
                    || keccak256(bytes(legacy.tokenURI(tokenId))) != keccak256(bytes(expectedRepairedUri(tokenId)))
            ) {
                revert RepairPrerequisiteMismatch(tokenId);
            }
        }

        LegacyRoleRevocation[5] memory revocations = legacyRoleRevocations();
        for (uint256 i; i < revocations.length; ++i) {
            uint256 actual = legacy.rolesOf(revocations[i].holder);
            if (actual != revocations[i].roleMask) {
                revert LegacyRoleMismatch(revocations[i].holder, revocations[i].roleMask, actual);
            }
        }

        if (fame.rolesOf(LEGACY) & RENDERER_ROLE == 0) {
            revert NewRendererRoleMismatch(LEGACY, RENDERER_ROLE, fame.rolesOf(LEGACY));
        }
    }

    function _assertOperator(address operator) internal view {
        ICreatorArtistMagicMigrationLegacy legacy = ICreatorArtistMagicMigrationLegacy(LEGACY);
        IFameCreatorArtistMagicMigration fame = IFameCreatorArtistMagicMigration(FAME);
        if (legacy.owner() != operator) {
            revert OwnerMismatch(legacy.owner(), operator);
        }

        uint256 fameRoles = fame.rolesOf(operator);
        if (fameRoles & METADATA_ROLE == 0) {
            revert OperatorMissingMetadataRole(operator, fameRoles);
        }
    }

    function _assertBroadcastConfirmations() internal view {
        address confirmedLegacy = vm.envOr("CREATOR_ARTIST_MAGIC_MIGRATION_CONFIRM_LEGACY", address(0));
        address confirmedFame = vm.envOr("CREATOR_ARTIST_MAGIC_MIGRATION_CONFIRM_FAME", address(0));
        if (confirmedLegacy != LEGACY) {
            revert BroadcastLegacyConfirmationMismatch(LEGACY, confirmedLegacy);
        }
        if (confirmedFame != FAME) {
            revert BroadcastFameConfirmationMismatch(FAME, confirmedFame);
        }
    }

    function _executeMigration() internal returns (CreatorArtistMagic deployed) {
        deployed = new CreatorArtistMagic(LEGACY, payable(FAME), EXPECTED_NEXT_TOKEN_ID, EXPECTED_ART_POOL_NEXT);

        address[3] memory creators = creatorWallets();
        for (uint256 i; i < creators.length; ++i) {
            deployed.grantRoles(creators[i], CREATOR_ROLE);
        }

        LegacyRoleRevocation[5] memory revocations = legacyRoleRevocations();
        for (uint256 i; i < revocations.length; ++i) {
            ICreatorArtistMagicMigrationLegacy(LEGACY).revokeRoles(revocations[i].holder, revocations[i].roleMask);
        }

        IFameCreatorArtistMagicMigration(FAME).setRenderer(address(deployed));
    }

    function _assertPostState(CreatorArtistMagic deployed, address operator) internal view {
        if (address(deployed).code.length == 0) {
            revert TargetCodeMissing(address(deployed));
        }
        if (deployed.owner() != operator) {
            revert NewRendererOwnerMismatch(operator, deployed.owner());
        }
        if (address(deployed.fame()) != FAME) {
            revert FameMismatch(FAME, address(deployed.fame()));
        }
        if (address(deployed.childRenderer()) != LEGACY) {
            revert ChildRendererMismatch(LEGACY, address(deployed.childRenderer()));
        }
        if (deployed.nextTokenId() != EXPECTED_NEXT_TOKEN_ID) {
            revert NextTokenIdMismatch(EXPECTED_NEXT_TOKEN_ID, deployed.nextTokenId());
        }
        if (deployed.artPoolNext() != EXPECTED_ART_POOL_NEXT) {
            revert ArtPoolNextMismatch(EXPECTED_ART_POOL_NEXT, deployed.artPoolNext());
        }
        if (deployed.rolesOf(LEGACY) != RENDERER_ROLE) {
            revert NewRendererRoleMismatch(LEGACY, RENDERER_ROLE, deployed.rolesOf(LEGACY));
        }

        address[3] memory creators = creatorWallets();
        for (uint256 i; i < creators.length; ++i) {
            uint256 actual = deployed.rolesOf(creators[i]);
            if (actual != CREATOR_ROLE) {
                revert NewRendererRoleMismatch(creators[i], CREATOR_ROLE, actual);
            }
        }

        IFameCreatorArtistMagicMigration fame = IFameCreatorArtistMagicMigration(FAME);
        if (fame.renderer() != address(deployed)) {
            revert RendererMismatch(address(deployed), fame.renderer());
        }
        if (fame.rolesOf(address(deployed)) & RENDERER_ROLE == 0) {
            revert NewRendererRoleMismatch(address(deployed), RENDERER_ROLE, fame.rolesOf(address(deployed)));
        }
        if (fame.rolesOf(LEGACY) & RENDERER_ROLE != 0) {
            revert NewRendererRoleMismatch(LEGACY, 0, fame.rolesOf(LEGACY));
        }

        LegacyRoleRevocation[5] memory revocations = legacyRoleRevocations();
        for (uint256 i; i < revocations.length; ++i) {
            uint256 actual = ICreatorArtistMagicMigrationLegacy(LEGACY).rolesOf(revocations[i].holder);
            if (actual != 0) {
                revert LegacyRoleMismatch(revocations[i].holder, 0, actual);
            }
        }

        ICreatorArtistMagicMigrationLegacy legacy = ICreatorArtistMagicMigrationLegacy(LEGACY);
        for (uint256 tokenId = 1; tokenId <= MAX_TOKEN_ID; ++tokenId) {
            if (keccak256(bytes(deployed.tokenURI(tokenId))) != keccak256(bytes(legacy.tokenURI(tokenId)))) {
                revert TokenUriMismatch(tokenId);
            }
        }
    }

    function _printPlan() internal pure {
        console2.log("FAME", FAME);
        console2.log("Legacy CreatorArtistMagic", LEGACY);
        console2.log("New child renderer", LEGACY);
        console2.log("Starting nextTokenId", EXPECTED_NEXT_TOKEN_ID);

        address[3] memory creators = creatorWallets();
        for (uint256 i; i < creators.length; ++i) {
            console2.log("Migrate CREATOR wallet", creators[i]);
        }

        LegacyRoleRevocation[5] memory revocations = legacyRoleRevocations();
        for (uint256 i; i < revocations.length; ++i) {
            console2.log("Revoke legacy holder", revocations[i].holder);
            console2.log("Legacy role mask", revocations[i].roleMask);
        }
    }
}
