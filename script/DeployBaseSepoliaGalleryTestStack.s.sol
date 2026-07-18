// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {BaseSepoliaTestRenderer} from "../src/BaseSepoliaTestRenderer.sol";
import {ClosedLoopGallerySwap} from "../src/ClosedLoopGallerySwap.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";

contract DeployBaseSepoliaGalleryTestStack is Script {
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;
    address internal constant BASE_SEPOLIA_FAME = 0x2cF0408Ee86b337216dD0073ab257F84497067cA;
    address internal constant BASE_SEPOLIA_MIRROR = 0x2907936013BDF568F98A98893AC1C746256A9cC5;
    address internal constant BASE_SEPOLIA_ADMIN = 0xD52E2A6bBcEba9673440e4D7843Db6713E9B6FD9;
    uint256 internal constant FAME_METADATA_ROLE = 1 << 1;
    uint256 internal constant FAME_ADMIN_ROLE = 1 << 255;
    uint16 internal constant NEXT_TOKEN_ID = 500;
    uint256 internal constant INITIAL_GALLERY_INVENTORY = 2;

    error ChainIdMismatch(uint256 expected, uint256 actual);
    error FameIdentityMismatch();
    error FameMirrorMismatch(address expected, address actual);
    error CanonicalAddressMismatch(string field, address expected, address actual);
    error PreviousRendererMismatch(address expected, address actual);
    error UnexpectedDeployer(address expected, address actual);
    error DeployerMissingFameAdmin(address deployer);
    error GalleryOwnerMissingFameAdmin(address owner);
    error DeployerNonceMismatch(uint256 expected, uint256 actual);
    error InsufficientDeploymentFameBalance(uint256 required, uint256 available);
    error ZeroAddress(string field);

    function run()
        external
        returns (BaseSepoliaTestRenderer renderer, CreatorArtistMagic creatorMagic, ClosedLoopGallerySwap gallery)
    {
        if (block.chainid != BASE_SEPOLIA_CHAIN_ID) {
            revert ChainIdMismatch(BASE_SEPOLIA_CHAIN_ID, block.chainid);
        }

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        Fame fame = Fame(payable(vm.envAddress("BASE_SEPOLIA_FAME_ADDRESS")));
        address expectedMirror = vm.envAddress("BASE_SEPOLIA_FAME_NFT_ADDRESS");
        address expectedPreviousRenderer = vm.envAddress("BASE_SEPOLIA_EXPECTED_PREVIOUS_RENDERER");
        address owner = vm.envOr("BASE_SEPOLIA_GALLERY_OWNER", deployer);
        address operator = vm.envOr("BASE_SEPOLIA_GALLERY_OPERATOR", owner);
        address feeRecipient = vm.envOr("BASE_SEPOLIA_GALLERY_FEE_RECIPIENT", owner);
        uint256 expectedDeployerNonce = vm.envUint("BASE_SEPOLIA_EXPECTED_DEPLOYER_NONCE");

        _validateInputs(fame, expectedMirror, deployer, owner, operator, feeRecipient);
        validateDeployerReadiness(fame, deployer, expectedDeployerNonce);
        if (address(fame.renderer()) != expectedPreviousRenderer) {
            revert PreviousRendererMismatch(expectedPreviousRenderer, address(fame.renderer()));
        }

        vm.startBroadcast(deployerPrivateKey);
        if (!fame.hasAnyRole(deployer, FAME_METADATA_ROLE)) fame.grantRoles(deployer, FAME_METADATA_ROLE);
        (renderer, creatorMagic, gallery) = deployConfiguredStack(fame, feeRecipient, owner, operator);
        vm.stopBroadcast();
    }

    function deployConfiguredStack(Fame fame, address feeRecipient, address owner, address operator)
        public
        returns (BaseSepoliaTestRenderer renderer, CreatorArtistMagic creatorMagic, ClosedLoopGallerySwap gallery)
    {
        renderer = new BaseSepoliaTestRenderer();
        creatorMagic = new CreatorArtistMagic(address(renderer), payable(address(fame)), NEXT_TOKEN_ID);
        gallery =
            new ClosedLoopGallerySwap(payable(address(fame)), address(creatorMagic), feeRecipient, owner, operator);
        creatorMagic.grantRoles(address(gallery), gallery.requiredCreatorMagicRoles());
        if (creatorMagic.owner() != owner) creatorMagic.transferOwnership(owner);
        fame.transfer(address(gallery), INITIAL_GALLERY_INVENTORY * fame.unit());
        fame.setRenderer(address(creatorMagic));
    }

    function validateDeployerReadiness(Fame fame, address deployer, uint256 expectedNonce) public view {
        uint256 actualNonce = vm.getNonce(deployer);
        if (actualNonce != expectedNonce) revert DeployerNonceMismatch(expectedNonce, actualNonce);

        uint256 requiredBalance = INITIAL_GALLERY_INVENTORY * fame.unit();
        uint256 availableBalance = fame.balanceOf(deployer);
        if (availableBalance < requiredBalance) {
            revert InsufficientDeploymentFameBalance(requiredBalance, availableBalance);
        }
    }

    function _validateInputs(
        Fame fame,
        address expectedMirror,
        address deployer,
        address owner,
        address operator,
        address feeRecipient
    ) internal view {
        if (address(fame) != BASE_SEPOLIA_FAME) {
            revert CanonicalAddressMismatch("fame", BASE_SEPOLIA_FAME, address(fame));
        }
        if (expectedMirror != BASE_SEPOLIA_MIRROR) {
            revert CanonicalAddressMismatch("mirror", BASE_SEPOLIA_MIRROR, expectedMirror);
        }
        if (deployer != BASE_SEPOLIA_ADMIN) revert UnexpectedDeployer(BASE_SEPOLIA_ADMIN, deployer);
        if (address(fame).code.length == 0) revert ZeroAddress("fame");
        if (expectedMirror == address(0)) revert ZeroAddress("mirror");
        if (owner == address(0)) revert ZeroAddress("owner");
        if (operator == address(0)) revert ZeroAddress("operator");
        if (feeRecipient == address(0)) revert ZeroAddress("feeRecipient");
        if (
            keccak256(bytes(fame.name())) != keccak256("Example")
                || keccak256(bytes(fame.symbol())) != keccak256("TEST")
        ) {
            revert FameIdentityMismatch();
        }
        if (address(fame.fameMirror()) != expectedMirror) {
            revert FameMirrorMismatch(expectedMirror, address(fame.fameMirror()));
        }
        if (!fame.hasAnyRole(deployer, FAME_ADMIN_ROLE)) revert DeployerMissingFameAdmin(deployer);
        if (!fame.hasAnyRole(owner, FAME_ADMIN_ROLE)) revert GalleryOwnerMissingFameAdmin(owner);
    }
}
