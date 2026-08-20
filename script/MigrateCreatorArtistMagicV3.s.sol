// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {FameMarketplaceCheckout} from "../src/FameMarketplaceCheckout.sol";
import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";

interface ICreatorArtistMagicV2 {
    function owner() external view returns (address);
    function fame() external view returns (address);
    function nextTokenId() external view returns (uint16);
    function artPoolNext() external view returns (uint256);
    function getTotalNFTSupply() external view returns (uint256);
    function rolesOf(address user) external view returns (uint256);
    function revokeRoles(address user, uint256 roles) external payable;
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

interface IFameV3Cutover {
    function renderer() external view returns (address);
    function fameMirror() external view returns (address);
    function rolesOf(address user) external view returns (uint256);
    function getSkipNFT(address user) external view returns (bool);
    function setRenderer(address renderer_) external;
}

/**
 * @notice Guarded one-shot Base cutover to CreatorArtistMagic V3 and a replacement marketplace stack.
 * @dev The default mode is read-only inspection. No provider position is moved by this script.
 *      The old marketplace pause is deliberately the first state-changing call.
 */
contract MigrateCreatorArtistMagicV3 is Script {
    struct CutoverResult {
        CreatorArtistMagic creatorMagic;
        UniversalPoolArtMarketplace marketplace;
        FameMarketplaceCheckout checkout;
    }

    struct LegacyPositionSnapshot {
        uint256 inventory;
        uint256 totalProviderUnits;
        uint256 providerUnits;
        uint256 providerIndexPlusOne;
    }

    uint256 public constant BASE_CHAIN_ID = 8453;
    uint16 public constant EXPECTED_NEXT_TOKEN_ID = 651;
    uint16 public constant EXPECTED_ART_POOL_NEXT = 266;
    uint32 public constant EXPECTED_DN404_TOTAL_NFT_SUPPLY = 564;
    uint32 public constant EXPECTED_DN404_PACKED_NEXT_TOKEN_ID = 592;
    uint64 public constant EXPECTED_OPERATOR_NONCE = 230;
    uint256 public constant DN404_STORAGE_SLOT = 0xa20d6e21d0e5255308;
    uint256 public constant MAX_TOKEN_ID = 888;

    uint256 public constant RENDERER_ROLE = 1;
    uint256 public constant CREATOR_ROLE = 2;
    uint256 public constant BANISHER_ROLE = 4;
    uint256 public constant METADATA_ROLE = 2;

    uint256 public constant COMMUNITY_FEE = 25_000 ether;
    uint256 public constant PROVIDER_FEE = 25_000 ether;
    uint256 public constant ACTIVE_PROVIDER_CAP = 88;

    bool public constant DEFAULT_EXECUTE = false;
    bool public constant DEFAULT_BROADCAST = false;
    bool public constant BROADCAST_APPROVED = true;

    address public constant FAME = 0xf307e242BfE1EC1fF01a4Cef2fdaa81b10A52418;
    address public constant FAME_MIRROR = 0xBB5ED04dD7B207592429eb8d599d103CCad646c4;
    address public constant V2 = 0xC8268c2aa571F3C88044C2959F73DdB8eB9e139F;
    address public constant OLD_MARKETPLACE = 0x54e7E4F2d439Be599706f51068f7EB2ce2D2a27e;
    address public constant OLD_CHECKOUT = 0x1905B4a633074243f3D9FDB59596fB7419adce2c;
    address public constant ROUTER = 0xAdefa5860389E8936ebf2977e1Fb4a365aA39636;
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant FEE_RECIPIENT = 0xC952C53D8B63919e372caa2E6FEe605ee24E4D3D;
    address public constant EXPECTED_OPERATOR = 0xD52E2A6bBcEba9673440e4D7843Db6713E9B6FD9;
    address public constant EXPECTED_CREATOR_MAGIC_V3 = 0x6754e4871775A781702f2Ab6e494754a562586ee;
    address public constant EXPECTED_MARKETPLACE_V3 = 0x93222897902a5Fc2f20079d242c660117277930A;
    address public constant EXPECTED_CHECKOUT_V3 = 0x50B9649Aa28D7d0B966B2A51092C5BcF37905a63;

    address public constant CREATOR_1 = 0xF11Ce547ff948a03570B20Eac4a4d7b648693324;
    address public constant CREATOR_2 = 0x750ea1c5ad297278665f2f8332a8876d6f95E19c;
    address public constant CREATOR_3 = 0xaE30c908C41407877fE764B5f864eb0F5e536A72;
    address public constant LEGACY_PROVIDER = CREATOR_1;

    error ChainIdMismatch(uint256 expected, uint256 actual);
    error BroadcastFlagRequiresExecution();
    error BroadcastNotApproved();
    error TargetCodeMissing(address target);
    error AddressMismatch(string field, address expected, address actual);
    error ValueMismatch(string field, uint256 expected, uint256 actual);
    error RoleMismatch(address contractAddress, address holder, uint256 expected, uint256 actual);
    error BoolMismatch(string field, bool expected, bool actual);
    error TokenUriMismatch(uint256 tokenId);
    error BroadcastConfirmationMismatch(string field, address expected, address actual);
    error StaticMintPoolFrontierPresent(address target);

    function run() external returns (CutoverResult memory result) {
        bool execute = vm.envOr("CREATOR_ARTIST_MAGIC_V3_EXECUTE", DEFAULT_EXECUTE);
        bool broadcast = vm.envOr("CREATOR_ARTIST_MAGIC_V3_BROADCAST", DEFAULT_BROADCAST);
        result = _run(execute, broadcast);
    }

    /**
     * @notice Reconcile the completed live cutover after a normal or resumed Foundry broadcast.
     * @dev Load config/fame-public.env after recording the three deployed addresses, then call
     *      this function without broadcast. It performs no writes.
     */
    function verifyDeployed() external view {
        CutoverResult memory result = CutoverResult({
            creatorMagic: CreatorArtistMagic(vm.envAddress("BASE_CREATOR_ARTIST_MAGIC_V3_ADDRESS")),
            marketplace: UniversalPoolArtMarketplace(vm.envAddress("BASE_UNIVERSAL_MARKETPLACE_V3_ADDRESS")),
            checkout: FameMarketplaceCheckout(payable(vm.envAddress("BASE_FAME_MARKETPLACE_CHECKOUT_V3_ADDRESS")))
        });
        LegacyPositionSnapshot memory legacyPosition =
            LegacyPositionSnapshot({inventory: 1, totalProviderUnits: 1, providerUnits: 1, providerIndexPlusOne: 1});
        _assertPostState(result, legacyPosition);
    }

    function _run(bool execute, bool broadcast) internal returns (CutoverResult memory result) {
        if (broadcast && !execute) revert BroadcastFlagRequiresExecution();
        if (broadcast && !BROADCAST_APPROVED) revert BroadcastNotApproved();

        LegacyPositionSnapshot memory legacyPosition = _assertPreState();
        _printPlan();
        if (!execute) {
            console2.log("Inspection complete; no state changed.");
            return result;
        }

        if (broadcast) {
            _assertBroadcastConfirmations();
            uint256 privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            address operator = vm.addr(privateKey);
            _assertOperator(operator);
            vm.startBroadcast(privateKey);
            result = _executeCutover(operator);
            vm.stopBroadcast();
            _assertAddress("predicted V3", EXPECTED_CREATOR_MAGIC_V3, address(result.creatorMagic));
            _assertAddress("predicted marketplace", EXPECTED_MARKETPLACE_V3, address(result.marketplace));
            _assertAddress("predicted checkout", EXPECTED_CHECKOUT_V3, address(result.checkout));
        } else {
            _assertOperator(EXPECTED_OPERATOR);
            vm.startPrank(EXPECTED_OPERATOR);
            result = _executeCutover(EXPECTED_OPERATOR);
            vm.stopPrank();
        }

        _assertPostState(result, legacyPosition);
        console2.log("CreatorArtistMagic V3", address(result.creatorMagic));
        console2.log("Replacement marketplace", address(result.marketplace));
        console2.log("Replacement checkout", address(result.checkout));
    }

    function creatorWallets() public pure returns (address[3] memory wallets) {
        wallets = [CREATOR_1, CREATOR_2, CREATOR_3];
    }

    function _assertPreState() internal view returns (LegacyPositionSnapshot memory snapshot) {
        if (block.chainid != BASE_CHAIN_ID) revert ChainIdMismatch(BASE_CHAIN_ID, block.chainid);
        _requireCode(FAME);
        _requireCode(FAME_MIRROR);
        _requireCode(V2);
        _requireCode(OLD_MARKETPLACE);
        _requireCode(OLD_CHECKOUT);
        _requireCode(ROUTER);

        IFameV3Cutover fame = IFameV3Cutover(FAME);
        ICreatorArtistMagicV2 v2 = ICreatorArtistMagicV2(V2);
        UniversalPoolArtMarketplace oldMarket = UniversalPoolArtMarketplace(OLD_MARKETPLACE);

        _assertAddress("FAME renderer", V2, fame.renderer());
        _assertValue("operator nonce", EXPECTED_OPERATOR_NONCE, vm.getNonce(EXPECTED_OPERATOR));
        _assertAddress("FAME mirror", FAME_MIRROR, fame.fameMirror());
        _assertRole(FAME, V2, RENDERER_ROLE, fame.rolesOf(V2));
        _assertBool("router skipNFT", true, fame.getSkipNFT(ROUTER));
        _assertAddress("V2 FAME", FAME, v2.fame());
        _assertAddress("V2 owner", EXPECTED_OPERATOR, v2.owner());
        _assertValue("V2 nextTokenId", EXPECTED_NEXT_TOKEN_ID, v2.nextTokenId());
        _assertValue("V2 artPoolNext", EXPECTED_ART_POOL_NEXT, v2.artPoolNext());
        _assertValue("DN404 total NFT supply", EXPECTED_DN404_TOTAL_NFT_SUPPLY, v2.getTotalNFTSupply());
        _assertDn404PackedNextTokenId();

        address[3] memory creators = creatorWallets();
        for (uint256 i; i < creators.length; ++i) {
            _assertRole(V2, creators[i], CREATOR_ROLE, v2.rolesOf(creators[i]));
        }
        _assertRole(V2, OLD_MARKETPLACE, BANISHER_ROLE, v2.rolesOf(OLD_MARKETPLACE));

        _assertAddress("old market owner", EXPECTED_OPERATOR, oldMarket.owner());
        _assertAddress("old market FAME", FAME, address(oldMarket.fame()));
        _assertAddress("old market creator", V2, address(oldMarket.creatorMagic()));
        _assertBool("old market paused", false, oldMarket.paused());

        snapshot.inventory = oldMarket.inventory();
        snapshot.totalProviderUnits = oldMarket.totalProviderUnits();
        (snapshot.providerUnits, snapshot.providerIndexPlusOne) = oldMarket.providerPosition(LEGACY_PROVIDER);
        _assertValue("old market inventory", 1, snapshot.inventory);
        _assertValue("old market total provider units", 1, snapshot.totalProviderUnits);
        _assertValue("legacy provider units", 1, snapshot.providerUnits);
        _assertValue("legacy provider index", 1, snapshot.providerIndexPlusOne);
    }

    function _assertOperator(address operator) internal view {
        _assertAddress("operator", EXPECTED_OPERATOR, operator);
        _assertAddress("V2 owner", operator, ICreatorArtistMagicV2(V2).owner());
        _assertAddress("old market owner", operator, UniversalPoolArtMarketplace(OLD_MARKETPLACE).owner());
        uint256 fameRoles = IFameV3Cutover(FAME).rolesOf(operator);
        if (fameRoles & METADATA_ROLE == 0) _assertRole(FAME, operator, METADATA_ROLE, fameRoles);
    }

    function _assertBroadcastConfirmations() internal view {
        _assertConfirmation("FAME", FAME, vm.envOr("CREATOR_ARTIST_MAGIC_V3_CONFIRM_FAME", address(0)));
        _assertConfirmation("V2", V2, vm.envOr("CREATOR_ARTIST_MAGIC_V3_CONFIRM_V2", address(0)));
        _assertConfirmation(
            "old marketplace", OLD_MARKETPLACE, vm.envOr("CREATOR_ARTIST_MAGIC_V3_CONFIRM_OLD_MARKETPLACE", address(0))
        );
    }

    function _executeCutover(address operator) internal returns (CutoverResult memory result) {
        UniversalPoolArtMarketplace oldMarket = UniversalPoolArtMarketplace(OLD_MARKETPLACE);
        ICreatorArtistMagicV2 v2 = ICreatorArtistMagicV2(V2);

        // This must remain the first deployment-side write.
        oldMarket.pause();

        // Recheck the manifest-pinned live inputs immediately after the first write.
        _assertValue("V2 nextTokenId", EXPECTED_NEXT_TOKEN_ID, v2.nextTokenId());
        _assertValue("V2 artPoolNext", EXPECTED_ART_POOL_NEXT, v2.artPoolNext());
        _assertValue("DN404 total NFT supply", EXPECTED_DN404_TOTAL_NFT_SUPPLY, v2.getTotalNFTSupply());
        _assertDn404PackedNextTokenId();

        result.creatorMagic = new CreatorArtistMagic(V2, payable(FAME), EXPECTED_NEXT_TOKEN_ID, EXPECTED_ART_POOL_NEXT);
        address[3] memory creators = creatorWallets();
        for (uint256 i; i < creators.length; ++i) {
            result.creatorMagic.grantRoles(creators[i], CREATOR_ROLE);
        }

        IFameV3Cutover(FAME).setRenderer(address(result.creatorMagic));

        result.marketplace = new UniversalPoolArtMarketplace(
            payable(FAME),
            address(result.creatorMagic),
            COMMUNITY_FEE,
            PROVIDER_FEE,
            FEE_RECIPIENT,
            operator,
            ACTIVE_PROVIDER_CAP
        );
        result.creatorMagic.grantRoles(address(result.marketplace), BANISHER_ROLE);

        result.checkout = new FameMarketplaceCheckout(ROUTER, address(result.marketplace), payable(FAME), USDC, WETH);
        result.marketplace.setAuthorizedCheckout(address(result.checkout));
        result.marketplace.unpause();

        for (uint256 i; i < creators.length; ++i) {
            v2.revokeRoles(creators[i], CREATOR_ROLE);
        }
        v2.revokeRoles(OLD_MARKETPLACE, BANISHER_ROLE);
    }

    function _assertPostState(CutoverResult memory result, LegacyPositionSnapshot memory legacyPosition) internal view {
        _requireCode(address(result.creatorMagic));
        _requireCode(address(result.marketplace));
        _requireCode(address(result.checkout));

        _assertAddress("V3 owner", EXPECTED_OPERATOR, result.creatorMagic.owner());
        _assertAddress("V3 FAME", FAME, address(result.creatorMagic.fame()));
        _assertAddress("V3 child", V2, address(result.creatorMagic.childRenderer()));
        _assertValue("V3 nextTokenId", EXPECTED_NEXT_TOKEN_ID, result.creatorMagic.nextTokenId());
        _assertValue(
            "V3 live mint boundary", result.creatorMagic.getTotalNFTSupply() + 1, result.creatorMagic.getMintPoolStart()
        );
        _assertNoStaticMintPoolFrontier(address(result.creatorMagic));
        _assertValue("V3 artPoolNext", EXPECTED_ART_POOL_NEXT, result.creatorMagic.artPoolNext());
        _assertRole(address(result.creatorMagic), V2, RENDERER_ROLE, result.creatorMagic.rolesOf(V2));

        address[3] memory creators = creatorWallets();
        for (uint256 i; i < creators.length; ++i) {
            _assertRole(
                address(result.creatorMagic), creators[i], CREATOR_ROLE, result.creatorMagic.rolesOf(creators[i])
            );
            _assertRole(V2, creators[i], 0, ICreatorArtistMagicV2(V2).rolesOf(creators[i]));
        }
        _assertRole(
            address(result.creatorMagic),
            address(result.marketplace),
            BANISHER_ROLE,
            result.creatorMagic.rolesOf(address(result.marketplace))
        );
        _assertRole(V2, OLD_MARKETPLACE, 0, ICreatorArtistMagicV2(V2).rolesOf(OLD_MARKETPLACE));

        _assertAddress("FAME renderer", address(result.creatorMagic), IFameV3Cutover(FAME).renderer());
        _assertRole(
            FAME,
            address(result.creatorMagic),
            RENDERER_ROLE,
            IFameV3Cutover(FAME).rolesOf(address(result.creatorMagic))
        );
        _assertRole(FAME, V2, 0, IFameV3Cutover(FAME).rolesOf(V2));

        _assertAddress("new market owner", EXPECTED_OPERATOR, result.marketplace.owner());
        _assertAddress("new market creator", address(result.creatorMagic), address(result.marketplace.creatorMagic()));
        _assertAddress("new market checkout", address(result.checkout), result.marketplace.authorizedCheckout());
        _assertBool("new market paused", false, result.marketplace.paused());
        _assertValue("new market inventory", 0, result.marketplace.inventory());
        _assertValue("new market provider units", 0, result.marketplace.totalProviderUnits());

        _assertAddress("checkout market", address(result.marketplace), address(result.checkout.market()));
        _assertAddress("checkout FAME", FAME, address(result.checkout.fame()));

        UniversalPoolArtMarketplace oldMarket = UniversalPoolArtMarketplace(OLD_MARKETPLACE);
        _assertBool("old market paused", true, oldMarket.paused());
        _assertValue("old market inventory unchanged", legacyPosition.inventory, oldMarket.inventory());
        _assertValue("old market units unchanged", legacyPosition.totalProviderUnits, oldMarket.totalProviderUnits());
        (uint256 providerUnits, uint256 providerIndex) = oldMarket.providerPosition(LEGACY_PROVIDER);
        _assertValue("legacy provider units unchanged", legacyPosition.providerUnits, providerUnits);
        _assertValue("legacy provider index unchanged", legacyPosition.providerIndexPlusOne, providerIndex);

        for (uint256 tokenId = 1; tokenId <= MAX_TOKEN_ID; ++tokenId) {
            if (
                keccak256(bytes(result.creatorMagic.tokenURI(tokenId)))
                    != keccak256(bytes(ICreatorArtistMagicV2(V2).tokenURI(tokenId)))
            ) revert TokenUriMismatch(tokenId);
        }
    }

    function _requireCode(address target) internal view {
        if (target.code.length == 0) revert TargetCodeMissing(target);
    }

    /// @dev Migration-only guard for the private DN404 cursor observed in the cutover manifest.
    ///      This value is never installed as CreatorArtistMagic classifier state.
    function _assertDn404PackedNextTokenId() internal view {
        uint256 packed = uint256(vm.load(FAME, bytes32(DN404_STORAGE_SLOT)));
        uint256 packedNextTokenId = uint32(packed >> 32);
        _assertValue("DN404 packed next token", EXPECTED_DN404_PACKED_NEXT_TOKEN_ID, packedNextTokenId);
    }

    function _assertNoStaticMintPoolFrontier(address target) internal view {
        (bool success,) = target.staticcall(abi.encodeWithSignature("mintPoolStartTokenId()"));
        if (success) revert StaticMintPoolFrontierPresent(target);
    }

    function _assertAddress(string memory field, address expected, address actual) internal pure {
        if (actual != expected) revert AddressMismatch(field, expected, actual);
    }

    function _assertValue(string memory field, uint256 expected, uint256 actual) internal pure {
        if (actual != expected) revert ValueMismatch(field, expected, actual);
    }

    function _assertRole(address target, address holder, uint256 expected, uint256 actual) internal pure {
        if (actual != expected) revert RoleMismatch(target, holder, expected, actual);
    }

    function _assertBool(string memory field, bool expected, bool actual) internal pure {
        if (actual != expected) revert BoolMismatch(field, expected, actual);
    }

    function _assertConfirmation(string memory field, address expected, address actual) internal pure {
        if (actual != expected) revert BroadcastConfirmationMismatch(field, expected, actual);
    }

    function _printPlan() internal pure {
        console2.log("1 pause old marketplace", OLD_MARKETPLACE);
        console2.log("2 deploy V3 with child", V2);
        console2.log("3 set V3 renderer and deploy replacement market plus checkout");
        console2.log("4 activate replacement market with zero inventory");
        console2.log("5 revoke V2 creator and old-market write roles");
        console2.log("legacy provider remains", LEGACY_PROVIDER);
    }
}
