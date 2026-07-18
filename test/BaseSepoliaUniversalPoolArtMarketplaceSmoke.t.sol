// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {SmokeBaseSepoliaUniversalPoolArtMarketplace} from "../script/SmokeBaseSepoliaUniversalPoolArtMarketplace.s.sol";
import {
    ValidateBaseSepoliaUniversalPoolArtMarketplaceSmokeResult
} from "../script/ValidateBaseSepoliaUniversalPoolArtMarketplaceSmokeResult.s.sol";
import {UniversalPoolArtMarketplaceTestBase} from "./helpers/UniversalPoolArtMarketplaceTestBase.sol";

contract BaseSepoliaUniversalPoolArtMarketplaceSmokeTest is UniversalPoolArtMarketplaceTestBase {
    bytes32 internal constant ARTWORK_PURCHASED_TOPIC =
        keccak256("ArtworkPurchased(address,address,uint256,uint8,uint256,bytes32,uint256,uint256,uint256,uint256)");

    SmokeBaseSepoliaUniversalPoolArtMarketplace internal smoke;
    ValidateBaseSepoliaUniversalPoolArtMarketplaceSmokeResult internal resultValidator;
    SmokeBaseSepoliaUniversalPoolArtMarketplace.SmokePlan internal plan;

    address internal directRecipient = address(0xCA01);
    address internal mintRecipient = address(0xCA02);
    address internal burnRecipient = address(0xCA03);

    function setUp() public override {
        super.setUp();
        smoke = new SmokeBaseSepoliaUniversalPoolArtMarketplace();
        resultValidator = new ValidateBaseSepoliaUniversalPoolArtMarketplaceSmokeResult();

        _seedShells(market, 5);
        _enablePoolPurchases(market);

        uint256 burnSource = _createBurnCandidate();
        uint256 mintSource = _findMintPoolToken();
        uint256 directShell = _ownedTokenAt(address(market), 0);
        uint256 mintShell = _ownedTokenAt(address(market), 1);
        uint256 burnShell = _ownedTokenAt(address(market), 2);

        vm.prank(address(smoke));
        fame.setSkipNFT(true);
        uint256 totalSpend = 3 * (fame.unit() + market.premium());
        fame.transfer(address(smoke), totalSpend);

        plan = SmokeBaseSepoliaUniversalPoolArtMarketplace.SmokePlan({
            buyer: address(smoke),
            directRecipient: directRecipient,
            mintRecipient: mintRecipient,
            burnRecipient: burnRecipient,
            directShell: directShell,
            mintShell: mintShell,
            mintSource: mintSource,
            burnShell: burnShell,
            burnSource: burnSource,
            directArtwork: market.artworkHash(directShell),
            mintArtwork: market.artworkHash(mintSource),
            mintDisplacedArtwork: market.artworkHash(mintShell),
            burnArtwork: market.artworkHash(burnSource),
            burnDisplacedArtwork: market.artworkHash(burnShell),
            premium: market.premium(),
            unit: fame.unit(),
            totalSpend: totalSpend,
            inventoryBefore: market.inventory(),
            feeBalanceBefore: fame.balanceOf(feeRecipient),
            buyerMirrorBalanceBefore: mirror.balanceOf(address(smoke)),
            minimumBuyerMirrorBalanceAfter: 0,
            expectedNonce: 0
        });
    }

    function testRunRejectsWrongChainBeforeConfirmationOrSecrets() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SmokeBaseSepoliaUniversalPoolArtMarketplace.ChainIdMismatch.selector, uint256(84532), block.chainid
            )
        );
        smoke.run();
    }

    function testExecuteRunsExactlyThreeCommittedPathsAndValidatesResult() public {
        bytes32 commitment = smoke.hashPlan(plan);
        assertEq(commitment, keccak256(abi.encode(plan)));

        vm.recordLogs();
        smoke.execute(plan, fame, creatorMagic, market);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 purchaseCount;
        bool sawHeld;
        bool sawBurn;
        bool sawMint;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter != address(market) || logs[i].topics.length == 0
                    || logs[i].topics[0] != ARTWORK_PURCHASED_TOPIC
            ) {
                continue;
            }
            (
                UniversalPoolArtMarketplace.FulfillmentPath path,
                uint256 sourceId,
                bytes32 artwork,
                uint256 unitAmount,
                uint256 premiumAmount,
                uint256 inventoryBefore,
                uint256 inventoryAfter
            ) = abi.decode(
                logs[i].data,
                (UniversalPoolArtMarketplace.FulfillmentPath, uint256, bytes32, uint256, uint256, uint256, uint256)
            );
            assertEq(unitAmount, plan.unit);
            assertEq(premiumAmount, plan.premium);
            assertGe(inventoryAfter, inventoryBefore);
            if (path == UniversalPoolArtMarketplace.FulfillmentPath.Held) {
                sawHeld = sourceId == 0 && artwork == plan.directArtwork;
            } else if (path == UniversalPoolArtMarketplace.FulfillmentPath.BurnPool) {
                sawBurn = sourceId == plan.burnSource && artwork == plan.burnArtwork;
            } else if (path == UniversalPoolArtMarketplace.FulfillmentPath.MintPool) {
                sawMint = sourceId == plan.mintSource && artwork == plan.mintArtwork;
            }
            ++purchaseCount;
        }

        assertEq(purchaseCount, 3);
        assertTrue(sawHeld);
        assertTrue(sawBurn);
        assertTrue(sawMint);
        assertEq(fame.allowance(address(smoke), address(market)), 0);
        resultValidator.validateResult(plan, fame, creatorMagic, market);
    }

    function testPreflightRejectsChangedCommitmentsAndFourthShellReuse() public {
        SmokeBaseSepoliaUniversalPoolArtMarketplace.SmokePlan memory changed = plan;
        changed.premium = plan.premium + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                SmokeBaseSepoliaUniversalPoolArtMarketplace.SmokeValueMismatch.selector,
                "premium",
                changed.premium,
                plan.premium
            )
        );
        smoke.preflight(changed, fame, creatorMagic, market);

        changed = plan;
        changed.burnShell = changed.directShell;
        vm.expectRevert(SmokeBaseSepoliaUniversalPoolArtMarketplace.InvalidSmokeTokenIds.selector);
        smoke.preflight(changed, fame, creatorMagic, market);

        changed = plan;
        changed.directArtwork = bytes32(uint256(1));
        vm.expectRevert(
            abi.encodeWithSelector(
                SmokeBaseSepoliaUniversalPoolArtMarketplace.SmokeArtworkMismatch.selector,
                changed.directShell,
                changed.directArtwork,
                plan.directArtwork
            )
        );
        smoke.preflight(changed, fame, creatorMagic, market);
    }

    function testAuthorizationRejectsDifferentSignerNonceAndPlan() public {
        bytes32 commitment = smoke.hashPlan(plan);
        vm.expectRevert(
            abi.encodeWithSelector(
                SmokeBaseSepoliaUniversalPoolArtMarketplace.UnexpectedSigner.selector, plan.buyer, address(0xBAD1)
            )
        );
        smoke.validateAuthorization(plan, address(0xBAD1), plan.expectedNonce, commitment);

        vm.expectRevert(
            abi.encodeWithSelector(
                SmokeBaseSepoliaUniversalPoolArtMarketplace.BuyerNonceMismatch.selector,
                plan.expectedNonce,
                plan.expectedNonce + 1
            )
        );
        smoke.validateAuthorization(plan, plan.buyer, plan.expectedNonce + 1, commitment);

        SmokeBaseSepoliaUniversalPoolArtMarketplace.SmokePlan memory changed = plan;
        changed.directRecipient = address(0xBAD2);
        bytes32 changedCommitment = smoke.hashPlan(changed);
        vm.expectRevert(
            abi.encodeWithSelector(
                SmokeBaseSepoliaUniversalPoolArtMarketplace.SmokePlanCommitmentMismatch.selector,
                commitment,
                changedCommitment
            )
        );
        smoke.validateAuthorization(changed, changed.buyer, changed.expectedNonce, commitment);
    }

    function testResultValidatorRejectsWrongRecipientAndArtwork() public {
        smoke.execute(plan, fame, creatorMagic, market);

        SmokeBaseSepoliaUniversalPoolArtMarketplace.SmokePlan memory changed = plan;
        changed.directRecipient = address(0xBAD1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaUniversalPoolArtMarketplaceSmokeResult.ResultAddressMismatch.selector,
                "direct.owner",
                changed.directRecipient,
                directRecipient
            )
        );
        resultValidator.validateResult(changed, fame, creatorMagic, market);

        changed = plan;
        changed.mintArtwork = bytes32(uint256(2));
        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaUniversalPoolArtMarketplaceSmokeResult.ResultArtworkMismatch.selector,
                changed.mintShell,
                changed.mintArtwork,
                plan.mintArtwork
            )
        );
        resultValidator.validateResult(changed, fame, creatorMagic, market);
    }

    function _createBurnCandidate() internal returns (uint256 sourceId) {
        address holder = address(0xB001);
        address keeper = address(0xB002);
        uint256 unit = fame.unit();
        fame.transfer(holder, unit);
        sourceId = _ownedTokenAt(holder, 0);
        fame.transfer(keeper, unit);
        vm.prank(holder);
        fame.transfer(feeRecipient, unit);
        assertTrue(creatorMagic.isTokenInBurnedPool(sourceId));
    }
}
