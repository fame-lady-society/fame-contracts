// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";

contract DeployBaseSepoliaUniversalPoolArtMarketplace is Script {
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;
    address internal constant BASE_SEPOLIA_FAME = 0x2cF0408Ee86b337216dD0073ab257F84497067cA;
    address internal constant BASE_SEPOLIA_MIRROR = 0x2907936013BDF568F98A98893AC1C746256A9cC5;
    uint256 internal constant EXPECTED_UNIT = 1_000_000 ether;
    uint256 internal constant CREATOR_MAGIC_CREATOR_ROLE = 1 << 1;
    uint256 internal constant CREATOR_MAGIC_BANISHER_ROLE = 1 << 2;
    uint256 internal constant CREATOR_MAGIC_ART_POOL_MANAGER_ROLE = 1 << 3;
    uint256 internal constant FAME_SKIP_MANAGER_ROLE = 1 << 3;
    uint256 internal constant REQUIRED_INITIAL_INVENTORY = 2;

    enum DeploymentPrefix {
        None,
        Deployed,
        BanisherGranted,
        PartiallySeeded,
        ReadyPaused
    }

    struct DeploymentInputs {
        uint256 privateKey;
        address deployer;
        Fame fame;
        CreatorArtistMagic creatorMagic;
        address owner;
        address feeRecipient;
        uint256 premium;
        uint256 minimumInventory;
        uint256 expectedNonce;
    }

    error ChainIdMismatch(uint256 expected, uint256 actual);
    error UnexpectedDeployer(address expected, address actual);
    error DeployerNonceMismatch(uint256 expected, uint256 actual);
    error PredictedAddressMismatch(address expected, address actual);
    error CanonicalStackMismatch();
    error InvalidOwner(address owner);
    error InvalidPremium(uint256 premium);
    error InvalidMinimumInventory(uint256 expected, uint256 actual);
    error FeeRecipientNotSkippingNFT(address recipient);
    error InsufficientSeedBalance(uint256 required, uint256 available);
    error ExistingDeploymentMismatch(string field);
    error ExistingDeploymentActivated(address market);
    error ExistingDeploymentAuthorityTooBroad(uint256 role);

    function run() external returns (UniversalPoolArtMarketplace market) {
        if (block.chainid != BASE_SEPOLIA_CHAIN_ID) {
            revert ChainIdMismatch(BASE_SEPOLIA_CHAIN_ID, block.chainid);
        }

        DeploymentInputs memory inputs = _loadInputs();
        address predicted = vm.computeCreateAddress(inputs.deployer, inputs.expectedNonce);
        address configured = vm.envOr("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_ADDRESS", address(0));
        if (configured != address(0) && configured != predicted) {
            revert PredictedAddressMismatch(predicted, configured);
        }

        uint256 actualNonce = vm.getNonce(inputs.deployer);
        if (predicted.code.length == 0 && actualNonce != inputs.expectedNonce) {
            revert DeployerNonceMismatch(inputs.expectedNonce, actualNonce);
        }

        uint256 existingInventory;
        if (predicted.code.length != 0) {
            market = UniversalPoolArtMarketplace(predicted);
            (, existingInventory) = deploymentPrefix(
                market,
                inputs.fame,
                inputs.creatorMagic,
                inputs.owner,
                inputs.feeRecipient,
                inputs.premium,
                inputs.minimumInventory
            );
        }
        uint256 missingInventory =
            existingInventory >= inputs.minimumInventory ? 0 : inputs.minimumInventory - existingInventory;
        uint256 requiredBalance = missingInventory * inputs.fame.unit();
        uint256 availableBalance = inputs.fame.balanceOf(inputs.deployer);
        if (availableBalance < requiredBalance) {
            revert InsufficientSeedBalance(requiredBalance, availableBalance);
        }

        vm.startBroadcast(inputs.privateKey);
        if (address(market) == address(0)) {
            market = new UniversalPoolArtMarketplace(
                payable(address(inputs.fame)),
                address(inputs.creatorMagic),
                inputs.premium,
                inputs.feeRecipient,
                inputs.owner
            );
        }
        if (!inputs.creatorMagic.hasAnyRole(address(market), CREATOR_MAGIC_BANISHER_ROLE)) {
            inputs.creatorMagic.grantRoles(address(market), CREATOR_MAGIC_BANISHER_ROLE);
        }
        for (uint256 i; i < missingInventory; ++i) {
            inputs.fame.transfer(address(market), inputs.fame.unit());
        }
        vm.stopBroadcast();
    }

    function _loadInputs() internal view returns (DeploymentInputs memory inputs) {
        inputs.privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        inputs.deployer = vm.addr(inputs.privateKey);
        address expectedDeployer = vm.envAddress("BASE_SEPOLIA_FAME_EXPECTED_ADMIN");
        if (inputs.deployer != expectedDeployer) {
            revert UnexpectedDeployer(expectedDeployer, inputs.deployer);
        }

        inputs.fame = Fame(payable(vm.envAddress("BASE_SEPOLIA_FAME_ADDRESS")));
        inputs.creatorMagic = CreatorArtistMagic(vm.envAddress("BASE_SEPOLIA_CREATOR_ARTIST_MAGIC_ADDRESS"));
        inputs.owner = vm.envAddress("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_OWNER");
        inputs.feeRecipient = vm.envAddress("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_FEE_RECIPIENT");
        inputs.premium = vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_PREMIUM");
        inputs.minimumInventory = vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_MINIMUM_INVENTORY");
        inputs.expectedNonce = vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_EXPECTED_DEPLOYER_NONCE");
        _validateMinimumInventory(inputs.minimumInventory);

        _validateInputs(
            inputs.fame, inputs.creatorMagic, inputs.deployer, inputs.owner, inputs.feeRecipient, inputs.premium
        );
    }

    function deploymentPrefix(
        UniversalPoolArtMarketplace market,
        Fame fame,
        CreatorArtistMagic creatorMagic,
        address expectedOwner,
        address expectedFeeRecipient,
        uint256 expectedPremium,
        uint256 minimumInventory
    ) public view returns (DeploymentPrefix prefix, uint256 inventory) {
        _validateMinimumInventory(minimumInventory);
        _validateExistingCore(market, fame, creatorMagic, expectedOwner, expectedFeeRecipient, expectedPremium);

        bool hasBanisher = creatorMagic.hasAnyRole(address(market), CREATOR_MAGIC_BANISHER_ROLE);
        inventory = market.inventory();
        if (!hasBanisher) return (DeploymentPrefix.Deployed, inventory);
        if (inventory == 0) return (DeploymentPrefix.BanisherGranted, 0);
        if (inventory < minimumInventory) {
            return (DeploymentPrefix.PartiallySeeded, inventory);
        }
        return (DeploymentPrefix.ReadyPaused, inventory);
    }

    function _validateInputs(
        Fame fame,
        CreatorArtistMagic creatorMagic,
        address deployer,
        address owner,
        address feeRecipient,
        uint256 premium
    ) internal view {
        if (
            address(fame) != BASE_SEPOLIA_FAME || address(fame.fameMirror()) != BASE_SEPOLIA_MIRROR
                || address(fame.renderer()) != address(creatorMagic) || address(creatorMagic.fame()) != address(fame)
                || keccak256(bytes(fame.name())) != keccak256("Example")
                || keccak256(bytes(fame.symbol())) != keccak256("TEST") || fame.unit() != EXPECTED_UNIT
        ) {
            revert CanonicalStackMismatch();
        }
        if (owner == address(0) || owner != deployer) revert InvalidOwner(owner);
        if (premium == 0 || premium > type(uint96).max) revert InvalidPremium(premium);
        if (!fame.getSkipNFT(feeRecipient)) {
            revert FeeRecipientNotSkippingNFT(feeRecipient);
        }
    }

    function _validateMinimumInventory(uint256 minimumInventory) internal pure {
        if (minimumInventory != REQUIRED_INITIAL_INVENTORY) {
            revert InvalidMinimumInventory(REQUIRED_INITIAL_INVENTORY, minimumInventory);
        }
    }

    function _validateExistingCore(
        UniversalPoolArtMarketplace market,
        Fame fame,
        CreatorArtistMagic creatorMagic,
        address expectedOwner,
        address expectedFeeRecipient,
        uint256 expectedPremium
    ) internal view {
        if (
            address(market.fame()) != address(fame) || address(market.mirror()) != address(fame.fameMirror())
                || address(market.creatorMagic()) != address(creatorMagic)
        ) {
            revert ExistingDeploymentMismatch("dependencies");
        }
        if (market.owner() != expectedOwner) {
            revert ExistingDeploymentMismatch("owner");
        }
        if (market.feeRecipient() != expectedFeeRecipient) {
            revert ExistingDeploymentMismatch("feeRecipient");
        }
        if (market.premium() != expectedPremium) {
            revert ExistingDeploymentMismatch("premium");
        }
        if (!market.paused()) revert ExistingDeploymentActivated(address(market));
        if (fame.getSkipNFT(address(market))) {
            revert ExistingDeploymentMismatch("marketplace.skipNFT");
        }
        if (!fame.getSkipNFT(expectedFeeRecipient)) {
            revert FeeRecipientNotSkippingNFT(expectedFeeRecipient);
        }
        if (creatorMagic.hasAnyRole(address(market), CREATOR_MAGIC_CREATOR_ROLE)) {
            revert ExistingDeploymentAuthorityTooBroad(CREATOR_MAGIC_CREATOR_ROLE);
        }
        if (creatorMagic.hasAnyRole(address(market), CREATOR_MAGIC_ART_POOL_MANAGER_ROLE)) {
            revert ExistingDeploymentAuthorityTooBroad(CREATOR_MAGIC_ART_POOL_MANAGER_ROLE);
        }
        if (fame.hasAnyRole(address(market), FAME_SKIP_MANAGER_ROLE)) {
            revert ExistingDeploymentAuthorityTooBroad(FAME_SKIP_MANAGER_ROLE);
        }
    }
}
