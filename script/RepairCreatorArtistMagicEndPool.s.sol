// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

interface ICreatorArtistMagicRepair {
    function childRenderer() external view returns (address);
    function fame() external view returns (address);
    function nextTokenId() external view returns (uint16);
    function getTokenMetadataId(uint256 tokenId) external view returns (uint16);
    function isTokenInMintPool(uint256 tokenId) external view returns (bool);
    function tokenURI(uint256 tokenId) external view returns (string memory);
    function updateMetadata(uint256 tokenId, string calldata newMetadataUrl) external;
    function owner() external view returns (address);
    function rolesOf(address user) external view returns (uint256);
    function grantRoles(address user, uint256 roles) external payable;
    function revokeRoles(address user, uint256 roles) external payable;
}

interface IFameRepairTarget {
    function renderer() external view returns (address);
}

/**
 * @notice Repairs the five end-of-mint-pool slots consumed by the legacy
 *         CreatorArtistMagic implementation without receiving the source metadata.
 *
 * Default mode is read-only:
 *
 *   set -a
 *   source config/fame-public.env
 *   set +a
 *   doppler run --config prd -- sh -c \
 *     'BASE_RPC="$RPC_URL" forge script script/RepairCreatorArtistMagicEndPool.s.sol --rpc-url base'
 *
 * Fork simulation requires an explicit execution flag but no private key:
 *
 *   set -a
 *   source config/fame-public.env
 *   set +a
 *   doppler run --config prd -- sh -c \
 *     'BASE_RPC="$RPC_URL" CREATOR_ARTIST_MAGIC_REPAIR_EXECUTE=true \
 *       forge script script/RepairCreatorArtistMagicEndPool.s.sol --rpc-url base'
 *
 * Live broadcast is double-gated. It additionally requires the exact target
 * confirmation, the broadcast flag, DEPLOYER_PRIVATE_KEY, and Foundry's
 * command-line --broadcast flag:
 *
 *   set -a
 *   source config/fame-public.env
 *   set +a
 *   doppler run --config prd -- sh -c \
 *     'BASE_RPC="$RPC_URL" \
 *       CREATOR_ARTIST_MAGIC_REPAIR_EXECUTE=true \
 *       CREATOR_ARTIST_MAGIC_REPAIR_BROADCAST=true \
 *       CREATOR_ARTIST_MAGIC_REPAIR_CONFIRM_TARGET="$BASE_CREATOR_ARTIST_MAGIC_LEGACY_ADDRESS" \
 *       forge script script/RepairCreatorArtistMagicEndPool.s.sol --rpc-url base --broadcast --slow'
 *
 * A live run is a sequence of transactions, not an atomic operation. Keep
 * Foundry's broadcast artifacts if it stops partway. After reconciling the
 * confirmed transactions and current on-chain state, the same command may be
 * continued with --resume --slow. If resuming is not safe and the owner was
 * temporarily granted CREATOR, the owner must explicitly revoke that role
 * after confirming which metadata updates landed.
 *
 * The current prd deployer is the legacy contract owner but has no CREATOR
 * role. The script temporarily grants only CREATOR, executes the five repairs,
 * and restores the signer's exact original role mask.
 */
contract RepairCreatorArtistMagicEndPool is Script {
    struct Repair {
        uint256 tokenId;
        uint256 sourceTokenId;
        bytes32 sourceTransaction;
        string expectedCurrentUri;
        string intendedUri;
        bytes32 expectedCalldataHash;
    }

    uint256 public constant REPAIR_COUNT = 5;
    uint256 public constant BASE_CHAIN_ID = 8453;
    uint16 public constant EXPECTED_NEXT_TOKEN_ID = 650;
    bool public constant DEFAULT_EXECUTE = false;
    bool public constant DEFAULT_BROADCAST = false;
    uint256 internal constant CREATOR_ROLE = 1 << 1;

    address public constant FAME = 0xf307e242BfE1EC1fF01a4Cef2fdaa81b10A52418;
    address public constant TARGET = 0x8091D00A25ebE87A2A1Ef19e1d33689FCAdC3fA5;
    address public constant LEGACY_CHILD_RENDERER = 0xA50C9a918C110CA159fb187F4a55896A4d063878;

    error ChainIdMismatch(uint256 expected, uint256 actual);
    error TargetCodeMissing();
    error FameMismatch(address expected, address actual);
    error RendererMismatch(address expected, address actual);
    error ChildRendererMismatch(address expected, address actual);
    error NextTokenIdMismatch(uint16 expected, uint16 actual);
    error MetadataIdMismatch(uint256 tokenId, uint16 expected, uint16 actual);
    error MetadataIdNotAssigned(uint256 tokenId);
    error TokenNotInExpectedMintPool(uint256 tokenId);
    error UriMismatch(uint256 tokenId, bytes32 expected, bytes32 actual);
    error CalldataHashMismatch(uint256 tokenId, bytes32 expected, bytes32 actual);
    error BroadcastFlagRequiresExecution();
    error BroadcastTargetConfirmationMismatch(address expected, address actual);
    error BroadcastSignerUnauthorized(address signer);
    error RoleMaskNotRestored(address signer, uint256 expected, uint256 actual);

    function run() external {
        bool execute = vm.envOr("CREATOR_ARTIST_MAGIC_REPAIR_EXECUTE", DEFAULT_EXECUTE);
        bool broadcast = vm.envOr("CREATOR_ARTIST_MAGIC_REPAIR_BROADCAST", DEFAULT_BROADCAST);
        _run(execute, broadcast);
    }

    function _run(bool execute, bool broadcast) internal {
        _assertExecutionMode(execute, broadcast);

        Repair[REPAIR_COUNT] memory repairs = repairManifest();
        _assertContractState();
        _assertPreState(repairs);
        _printManifest(repairs);

        if (!execute) {
            console2.log("Read-only inspection complete; no state changes simulated or broadcast.");
            return;
        }

        address operator;
        uint256 rolesBefore;
        if (broadcast) {
            (operator, rolesBefore) = _executeBroadcast(repairs);
        } else {
            (operator, rolesBefore) = _executeForkSimulation(repairs);
        }

        _assertPostState(repairs, operator, rolesBefore);
        console2.log(
            broadcast
                ? "Broadcast simulation complete; Foundry will send only when --broadcast is also present."
                : "Fork simulation complete; no live transactions were broadcast."
        );
    }

    function _assertExecutionMode(bool execute, bool broadcast) internal pure {
        if (broadcast && !execute) revert BroadcastFlagRequiresExecution();
    }

    function repairManifest() public pure returns (Repair[REPAIR_COUNT] memory repairs) {
        repairs[0] = Repair({
            tokenId: 645,
            sourceTokenId: 235,
            sourceTransaction: 0x94bd0a928e994824cb6df87c92e7f1a70ed69b2278acc43c3dff4624157e22b1,
            expectedCurrentUri: "https://www.fameladysociety.com/fame/metadata/645.json",
            intendedUri: "https://gateway.irys.xyz/BkM3YuRbFfecQNFFLJ3B7AHFKMOosD7OAMPb_W-m-4w/96491614803638560672972006391329580542169724233889678455509076750297420919226.json",
            expectedCalldataHash: 0x370aff772560204dac92e5427f102506a3d1b20335495967f6a1391ba0e97d5a
        });
        repairs[1] = Repair({
            tokenId: 646,
            sourceTokenId: 431,
            sourceTransaction: 0x0fb3c445ba89beccfa7ce413a28d1273ec0e1821c903a3bb0794ab9dd4f584b3,
            expectedCurrentUri: "https://www.fameladysociety.com/fame/metadata/646.json",
            intendedUri: "https://gateway.irys.xyz/BfE2c2cNNdpkX2D8Q81Z9ra1fQZQY4RawA2uDtx3AeGe",
            expectedCalldataHash: 0x2725fcd4f1d07fd245529042fe4f88dfe69903ee42e75c5001c195fe33d9f5f6
        });
        repairs[2] = Repair({
            tokenId: 647,
            sourceTokenId: 536,
            sourceTransaction: 0xa90f6ac5d2b4a213399d1a5df25cf7b86c6ee9f19f883a5678d86e61dae43b7f,
            expectedCurrentUri: "https://www.fameladysociety.com/fame/metadata/647.json",
            intendedUri: "https://gateway.irys.xyz/FD1-OUXP9tuePs8mlTYk25hA8TgnuaZ67RfL3P7Qi08/102830112365573296485305446164386189795940232314654879416395712650316837242972.json",
            expectedCalldataHash: 0x7ef963384eed4234a3d7037d0e6432bb12dc5792626a245c8588e85de5bcf9c0
        });
        repairs[3] = Repair({
            tokenId: 648,
            sourceTokenId: 587,
            sourceTransaction: 0xeb141ba953e88a15b37014a77d0901f5e3c325d22e880ed9a9bfc921e30f47c2,
            expectedCurrentUri: "https://www.fameladysociety.com/fame/metadata/648.json",
            intendedUri: "https://gateway.irys.xyz/AtQw-VDi13oYZd-fmOiDOp9y6ScNsAsT0HJsqWPuwpU/89130979697350676416287159826765619017698331009266499466147289381976509963047.json",
            expectedCalldataHash: 0xc6424d2b64e7dbd5e8be241b0e7327f619371e0b93f702c40a80fb2e8777cf41
        });
        repairs[4] = Repair({
            tokenId: 649,
            sourceTokenId: 144,
            sourceTransaction: 0x81ad0977e1916503f50d41d99c672857d412aa2ae17ced63d338ee85a9ab01c5,
            expectedCurrentUri: "https://www.fameladysociety.com/fame/metadata/649.json",
            intendedUri: "https://gateway.irys.xyz/BkM3YuRbFfecQNFFLJ3B7AHFKMOosD7OAMPb_W-m-4w/8192569806743278573033010153761630783437259634776181426633770268721943497377.json",
            expectedCalldataHash: 0xeb47a97fc7365276ae8dcb4b291d405a8e788604a5ae94e0bfe7c8e6b43f7773
        });
    }

    function _assertContractState() internal view {
        if (block.chainid != BASE_CHAIN_ID) revert ChainIdMismatch(BASE_CHAIN_ID, block.chainid);
        if (TARGET.code.length == 0) revert TargetCodeMissing();

        ICreatorArtistMagicRepair target = ICreatorArtistMagicRepair(TARGET);
        address actualFame = target.fame();
        address actualRenderer = IFameRepairTarget(FAME).renderer();
        address actualChildRenderer = target.childRenderer();
        uint16 actualNextTokenId = target.nextTokenId();
        if (actualFame != FAME) revert FameMismatch(FAME, actualFame);
        if (actualRenderer != TARGET) {
            revert RendererMismatch(TARGET, actualRenderer);
        }
        if (actualChildRenderer != LEGACY_CHILD_RENDERER) {
            revert ChildRendererMismatch(LEGACY_CHILD_RENDERER, actualChildRenderer);
        }
        if (actualNextTokenId != EXPECTED_NEXT_TOKEN_ID) {
            revert NextTokenIdMismatch(EXPECTED_NEXT_TOKEN_ID, actualNextTokenId);
        }
    }

    function _assertPreState(Repair[REPAIR_COUNT] memory repairs) internal view {
        ICreatorArtistMagicRepair target = ICreatorArtistMagicRepair(TARGET);
        for (uint256 i; i < repairs.length; ++i) {
            Repair memory repair = repairs[i];
            uint16 metadataId = target.getTokenMetadataId(repair.tokenId);
            if (metadataId != 0) revert MetadataIdMismatch(repair.tokenId, 0, metadataId);
            if (!target.isTokenInMintPool(repair.tokenId)) {
                revert TokenNotInExpectedMintPool(repair.tokenId);
            }
            _assertUri(repair.tokenId, repair.expectedCurrentUri);

            bytes32 calldataHash = keccak256(
                abi.encodeCall(ICreatorArtistMagicRepair.updateMetadata, (repair.tokenId, repair.intendedUri))
            );
            if (calldataHash != repair.expectedCalldataHash) {
                revert CalldataHashMismatch(repair.tokenId, repair.expectedCalldataHash, calldataHash);
            }
        }
    }

    function _executeForkSimulation(Repair[REPAIR_COUNT] memory repairs)
        internal
        returns (address operator, uint256 rolesBefore)
    {
        ICreatorArtistMagicRepair target = ICreatorArtistMagicRepair(TARGET);
        operator = target.owner();
        vm.startPrank(operator);
        rolesBefore = _executeRepairs(target, repairs, operator);
        vm.stopPrank();
    }

    function _executeBroadcast(Repair[REPAIR_COUNT] memory repairs)
        internal
        returns (address operator, uint256 rolesBefore)
    {
        address confirmedTarget = vm.envOr("CREATOR_ARTIST_MAGIC_REPAIR_CONFIRM_TARGET", address(0));
        _assertBroadcastTarget(confirmedTarget);

        uint256 privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        operator = vm.addr(privateKey);
        ICreatorArtistMagicRepair target = ICreatorArtistMagicRepair(TARGET);
        _assertBroadcastSigner(target, operator);

        vm.startBroadcast(privateKey);
        rolesBefore = _executeRepairs(target, repairs, operator);
        vm.stopBroadcast();
    }

    function _assertBroadcastTarget(address confirmedTarget) internal pure {
        if (confirmedTarget != TARGET) {
            revert BroadcastTargetConfirmationMismatch(TARGET, confirmedTarget);
        }
    }

    function _assertBroadcastSigner(ICreatorArtistMagicRepair target, address operator) internal view {
        if (operator != target.owner() && target.rolesOf(operator) & CREATOR_ROLE == 0) {
            revert BroadcastSignerUnauthorized(operator);
        }
    }

    function _executeRepairs(ICreatorArtistMagicRepair target, Repair[REPAIR_COUNT] memory repairs, address operator)
        internal
        returns (uint256 rolesBefore)
    {
        rolesBefore = target.rolesOf(operator);
        bool temporaryCreatorRole = rolesBefore & CREATOR_ROLE == 0;
        if (temporaryCreatorRole) {
            if (operator != target.owner()) revert BroadcastSignerUnauthorized(operator);
            target.grantRoles(operator, CREATOR_ROLE);
        }

        for (uint256 i; i < repairs.length; ++i) {
            target.updateMetadata(repairs[i].tokenId, repairs[i].intendedUri);
        }

        if (temporaryCreatorRole) target.revokeRoles(operator, CREATOR_ROLE);
    }

    function _assertPostState(Repair[REPAIR_COUNT] memory repairs, address operator, uint256 rolesBefore)
        internal
        view
    {
        ICreatorArtistMagicRepair target = ICreatorArtistMagicRepair(TARGET);
        _assertContractState();
        for (uint256 i; i < repairs.length; ++i) {
            Repair memory repair = repairs[i];
            uint16 metadataId = target.getTokenMetadataId(repair.tokenId);
            if (metadataId == 0) revert MetadataIdNotAssigned(repair.tokenId);
            _assertUri(repair.tokenId, repair.intendedUri);
        }

        uint256 rolesAfter = target.rolesOf(operator);
        if (rolesAfter != rolesBefore) revert RoleMaskNotRestored(operator, rolesBefore, rolesAfter);
    }

    function _assertUri(uint256 tokenId, string memory expectedUri) internal view {
        bytes32 expected = keccak256(bytes(expectedUri));
        bytes32 actual = keccak256(bytes(ICreatorArtistMagicRepair(TARGET).tokenURI(tokenId)));
        if (actual != expected) revert UriMismatch(tokenId, expected, actual);
    }

    function _printManifest(Repair[REPAIR_COUNT] memory repairs) internal pure {
        console2.log("CreatorArtistMagic end-pool repair target", TARGET);
        for (uint256 i; i < repairs.length; ++i) {
            Repair memory repair = repairs[i];
            console2.log("token", repair.tokenId);
            console2.log("source token", repair.sourceTokenId);
            console2.log("intended URI", repair.intendedUri);
            console2.log("source transaction");
            console2.logBytes32(repair.sourceTransaction);
            console2.log("update calldata hash");
            console2.logBytes32(repair.expectedCalldataHash);
        }
    }
}
