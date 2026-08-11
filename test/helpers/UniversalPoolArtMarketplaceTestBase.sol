// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {UniversalPoolArtMarketplace} from "../../src/UniversalPoolArtMarketplace.sol";
import {CreatorArtistMagic} from "../../src/CreatorArtistMagic.sol";
import {Fame} from "../../src/Fame.sol";
import {FameMirror} from "../../src/FameMirror.sol";
import {EchoMetadata} from "../mocks/EchoMetadata.sol";

abstract contract UniversalPoolArtMarketplaceTestBase is Test {
    uint256 internal constant FAME_RENDERER_ROLE = 1;
    uint256 internal constant FAME_METADATA_ROLE = 2;
    uint256 internal constant CREATOR_MAGIC_BANISHER_ROLE = 4;
    uint256 internal constant TEST_ACTIVE_PROVIDER_CAP = 16;

    address internal owner = address(this);
    address internal buyer = address(0x1002);
    address internal recipient = address(0x1003);
    address internal feeRecipient = address(0x1004);

    EchoMetadata internal childRenderer;
    Fame internal fame;
    FameMirror internal mirror;
    CreatorArtistMagic internal creatorMagic;
    UniversalPoolArtMarketplace internal market;

    function setUp() public virtual {
        childRenderer = new EchoMetadata();
        fame = new Fame(_fameName(), _fameSymbol(), address(0));
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

    function _fameName() internal pure virtual returns (string memory) {
        return "Fame Lady Society";
    }

    function _fameSymbol() internal pure virtual returns (string memory) {
        return "FAME";
    }

    function _deployMarket(uint256 premium_, address feeRecipient_, address owner_)
        internal
        returns (UniversalPoolArtMarketplace deployed)
    {
        return _deployMarketWithFees(premium_, 0, feeRecipient_, owner_, TEST_ACTIVE_PROVIDER_CAP);
    }

    function _deployMarketWithFees(
        uint256 communityFee_,
        uint256 providerFee_,
        address feeRecipient_,
        address owner_,
        uint256 providerCap_
    ) internal returns (UniversalPoolArtMarketplace deployed) {
        deployed = new UniversalPoolArtMarketplace(
            payable(address(fame)),
            address(creatorMagic),
            communityFee_,
            providerFee_,
            feeRecipient_,
            owner_,
            providerCap_
        );
    }

    function _seedShells(UniversalPoolArtMarketplace target, uint256 count) internal returns (uint256 firstShellId) {
        fame.transfer(address(target), count * fame.unit());
        firstShellId = _ownedTokenAt(address(target), 0);
    }

    function _enablePoolPurchases(UniversalPoolArtMarketplace target) internal {
        creatorMagic.grantRoles(address(target), CREATOR_MAGIC_BANISHER_ROLE);
        target.unpause();
    }

    function _findMintPoolToken() internal view returns (uint256) {
        uint256 start = creatorMagic.getMintPoolStart();
        uint256 end = creatorMagic.getMintPoolEnd();
        for (uint256 tokenId = start; tokenId < end; ++tokenId) {
            if (creatorMagic.isTokenInMintPool(tokenId)) return tokenId;
        }
        revert("MINT_POOL_TOKEN_NOT_FOUND");
    }

    function _prepareBurnPoolPurchase() internal returns (uint256 shellId, uint256 sourceId) {
        address burnHolder = address(0x4001);
        fame.transfer(burnHolder, fame.unit());
        sourceId = _ownedTokenAt(burnHolder, 0);
        shellId = _seedShells(market, 2);

        uint256 unit = fame.unit();
        vm.prank(burnHolder);
        fame.transfer(feeRecipient, unit);
        assertTrue(creatorMagic.isTokenInBurnedPool(sourceId));

        vm.prank(buyer);
        fame.setSkipNFT(true);
        _fundAndApprove(buyer, market, fame.unit() + market.premium());
    }

    function _fundAndApprove(address account, UniversalPoolArtMarketplace target, uint256 amount) internal {
        fame.transfer(account, amount);
        vm.prank(account);
        fame.approve(address(target), amount);
    }

    function _depositUnits(UniversalPoolArtMarketplace target, address provider, uint256 count) internal {
        fame.transfer(provider, count * fame.unit());
        vm.startPrank(provider);
        for (uint256 i; i < count; ++i) {
            uint256 tokenId = _ownedTokenAt(provider, 0);
            mirror.approve(address(target), tokenId);
            target.depositInventory(tokenId);
        }
        vm.stopPrank();
    }

    function _prepareBatch(address provider, uint256 count, UniversalPoolArtMarketplace target)
        internal
        returns (uint256[] memory tokenIds)
    {
        fame.transfer(provider, count * fame.unit());
        tokenIds = _ownedTokenIds(provider, count);
        vm.prank(provider);
        mirror.setApprovalForAll(address(target), true);
    }

    function _ownedTokenIds(address account, uint256 count) internal view returns (uint256[] memory tokenIds) {
        tokenIds = new uint256[](count);
        uint256 found;
        for (uint256 tokenId = 1; tokenId <= 888 && found < count; ++tokenId) {
            if (mirror.ownerAt(tokenId) == account) tokenIds[found++] = tokenId;
        }
        if (found != count) revert("OWNED_TOKENS_NOT_FOUND");
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
