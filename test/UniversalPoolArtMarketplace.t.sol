// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC721} from "@openzeppelin5/contracts/token/ERC721/ERC721.sol";
import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {EchoMetadata} from "./mocks/EchoMetadata.sol";
import {MockERC20} from "./router/mocks/MockERC20.sol";

contract MarketplaceMockERC721 is ERC721 {
    constructor() ERC721("Unrelated", "OTHER") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

contract UniversalPoolArtMarketplaceTest is Test {
    uint256 internal constant FAME_RENDERER_ROLE = 1;
    uint256 internal constant FAME_METADATA_ROLE = 2;

    address internal owner = address(this);
    address internal buyer = address(0x1002);
    address internal recipient = address(0x1003);
    address internal feeRecipient = address(0x1004);

    EchoMetadata internal childRenderer;
    Fame internal fame;
    FameMirror internal mirror;
    CreatorArtistMagic internal creatorMagic;
    UniversalPoolArtMarketplace internal market;

    function setUp() public {
        childRenderer = new EchoMetadata();
        fame = new Fame("Fame Lady Society", "FAME", address(0));
        mirror = fame.fameMirror();
        creatorMagic = new CreatorArtistMagic(address(childRenderer), payable(address(fame)), 500);

        fame.grantRoles(address(creatorMagic), FAME_RENDERER_ROLE);
        fame.grantRoles(address(this), FAME_METADATA_ROLE);
        fame.setRenderer(address(creatorMagic));
        fame.launchPublic();

        vm.prank(feeRecipient);
        fame.setSkipNFT(true);

        market = _deployMarket(fame.unit() / 10, feeRecipient, owner);
    }

    function testConstructorInitializesPausedCanonicalMarket() public view {
        assertEq(address(market.fame()), address(fame));
        assertEq(address(market.mirror()), address(mirror));
        assertEq(address(market.creatorMagic()), address(creatorMagic));
        assertEq(market.owner(), owner);
        assertEq(market.premium(), fame.unit() / 10);
        assertEq(market.feeRecipient(), feeRecipient);
        assertTrue(market.paused());
        assertFalse(fame.getSkipNFT(address(market)));
        assertEq(market.inventory(), 0);
        assertEq(market.artworkHash(7), keccak256(bytes(creatorMagic.tokenURI(7))));
    }

    function testConstructorRejectsInvalidPremiumOwnerAndFeeRecipient() public {
        vm.expectRevert(UniversalPoolArtMarketplace.ZeroPremium.selector);
        _deployMarket(0, feeRecipient, owner);

        uint256 oversized = uint256(type(uint96).max) + 1;
        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.PremiumTooLarge.selector, oversized));
        _deployMarket(oversized, feeRecipient, owner);

        vm.expectRevert(UniversalPoolArtMarketplace.ZeroAddress.selector);
        _deployMarket(1, feeRecipient, address(0));

        address nonSkip = address(0xBEEF);
        vm.expectRevert(
            abi.encodeWithSelector(UniversalPoolArtMarketplace.FeeRecipientNotSkippingNFT.selector, nonSkip)
        );
        _deployMarket(1, nonSkip, owner);
    }

    function testConstructorRejectsInvalidDependenciesAndStack() public {
        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.InvalidDependency.selector, address(0)));
        new UniversalPoolArtMarketplace(payable(address(0)), address(creatorMagic), 1, feeRecipient, owner);

        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.InvalidDependency.selector, buyer));
        new UniversalPoolArtMarketplace(payable(buyer), address(creatorMagic), 1, feeRecipient, owner);

        Fame otherFame = new Fame("Other", "OTHER", address(0));
        vm.expectRevert(UniversalPoolArtMarketplace.StackMismatch.selector);
        new UniversalPoolArtMarketplace(payable(address(otherFame)), address(creatorMagic), 1, feeRecipient, owner);
    }

    function testOwnerUpdatesGlobalConfigurationAndPause() public {
        uint256 updatedPremium = fame.unit() / 5;
        market.setPremium(updatedPremium);
        assertEq(market.premium(), updatedPremium);

        address updatedRecipient = address(0x2001);
        vm.prank(updatedRecipient);
        fame.setSkipNFT(true);
        market.setFeeRecipient(updatedRecipient);
        assertEq(market.feeRecipient(), updatedRecipient);

        market.unpause();
        assertFalse(market.paused());
        market.pause();
        assertTrue(market.paused());
    }

    function testOwnerUpdatesRejectInvalidValuesAndUnauthorizedCaller() public {
        vm.startPrank(buyer);
        vm.expectRevert();
        market.setPremium(1);
        vm.expectRevert();
        market.setFeeRecipient(feeRecipient);
        vm.expectRevert();
        market.unpause();
        vm.stopPrank();

        vm.expectRevert(UniversalPoolArtMarketplace.ZeroPremium.selector);
        market.setPremium(0);

        uint256 oversized = uint256(type(uint96).max) + 1;
        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.PremiumTooLarge.selector, oversized));
        market.setPremium(oversized);

        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.FeeRecipientNotSkippingNFT.selector, buyer));
        market.setFeeRecipient(buyer);

        vm.expectRevert(
            abi.encodeWithSelector(UniversalPoolArtMarketplace.InvalidFeeRecipient.selector, address(market))
        );
        market.setFeeRecipient(address(market));
    }

    function testOwnershipTransferAndHandoverWorkButRenunciationIsDisabled() public {
        address nextOwner = address(0x3001);
        market.transferOwnership(nextOwner);
        assertEq(market.owner(), nextOwner);

        vm.prank(nextOwner);
        vm.expectRevert(UniversalPoolArtMarketplace.OwnershipRenunciationDisabled.selector);
        market.renounceOwnership();

        address pendingOwner = address(0x3002);
        vm.prank(pendingOwner);
        market.requestOwnershipHandover();
        vm.prank(nextOwner);
        market.completeOwnershipHandover(pendingOwner);
        assertEq(market.owner(), pendingOwner);
    }

    function testCanonicalSocietyShellReceiptAndUnrelatedReceiverRejection() public {
        fame.transfer(buyer, fame.unit());
        uint256 shellId = _ownedTokenAt(buyer, 0);

        vm.prank(buyer);
        mirror.safeTransferFrom(buyer, address(market), shellId);
        assertEq(mirror.ownerOf(shellId), address(market));
        assertEq(market.inventory(), 1);

        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.UnsupportedNFT.selector, address(this)));
        market.onERC721Received(address(this), buyer, shellId, "");
    }

    function testPausedRecoveryOnlyAllowsUnrelatedAssets() public {
        MockERC20 token = new MockERC20("Other", "OTHER", 18);
        token.mint(address(market), 10 ether);
        market.rescueERC20(address(token), recipient, 10 ether);
        assertEq(token.balanceOf(recipient), 10 ether);

        MarketplaceMockERC721 nft = new MarketplaceMockERC721();
        nft.mint(address(market), 7);
        market.rescueERC721(address(nft), recipient, 7);
        assertEq(nft.ownerOf(7), recipient);

        vm.expectRevert(UniversalPoolArtMarketplace.CoreAssetRescueBlocked.selector);
        market.rescueERC20(address(fame), recipient, 1);
        vm.expectRevert(UniversalPoolArtMarketplace.CoreAssetRescueBlocked.selector);
        market.rescueERC721(address(mirror), recipient, 1);

        market.unpause();
        vm.expectRevert(UniversalPoolArtMarketplace.MarketNotPaused.selector);
        market.rescueERC20(address(token), recipient, 0);
    }

    function _deployMarket(uint256 premium_, address feeRecipient_, address owner_)
        internal
        returns (UniversalPoolArtMarketplace deployed)
    {
        deployed = new UniversalPoolArtMarketplace(
            payable(address(fame)), address(creatorMagic), premium_, feeRecipient_, owner_
        );
    }

    function _ownedTokenAt(address account, uint256 index) internal view returns (uint256) {
        uint256 seen;
        for (uint256 tokenId = 1; tokenId <= 888; ++tokenId) {
            if (mirror.ownerAt(tokenId) == account) {
                if (seen == index) return tokenId;
                ++seen;
            }
        }
        revert("OWNED_TOKEN_NOT_FOUND");
    }
}
