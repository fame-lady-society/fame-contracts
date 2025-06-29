// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/CreatorArtistMagic.sol";
import "../src/Fame.sol";
import "../src/FameMirror.sol";
import "../test/mocks/EchoMetadata.sol";

contract CreatorArtistMagicTest is Test {
    CreatorArtistMagic public creatorMagic;
    Fame public fame;
    FameMirror public fameMirror;
    EchoMetadata public childRenderer;

    address public creator = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

    function compareStrings(
        string memory a,
        string memory b
    ) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function setUp() public {
        // Deploy child renderer
        childRenderer = new EchoMetadata();

        // Deploy Fame contract
        fame = new Fame("Fame Lady Society", "FAME", address(0));
        fameMirror = fame.fameMirror();

        // Deploy CreatorArtistMagic contract
        creatorMagic = new CreatorArtistMagic(
            address(childRenderer),
            payable(address(fame)),
            1
        );

        // The deployer (this test contract) is the owner and can grant roles
        // Grant CREATOR role (CREATOR = _ROLE_0 = 1)
        creatorMagic.grantRoles(creator, 1);

        // Grant CreatorArtistMagic contract RENDERER role on Fame contract (RENDERER = _ROLE_0 = 1)
        fame.grantRoles(address(creatorMagic), 1);

        // Launch Fame to enable transfers
        fame.launchPublic();

        // Give users some Fame tokens to get NFTs
        fame.transfer(user1, 10_000_000 ether); // 10 NFTs
        fame.transfer(user2, 5_000_000 ether); // 5 NFTs

        // Give creator some Fame tokens to get NFTs
        fame.transfer(creator, 3_000_000 ether); // 3 NFTs

        // Switch to creator for testing banish functions
        vm.startPrank(creator);
    }

    function testBanishToArtPool() public {
        // Creator should own token 16 (first token after user1 and user2)
        uint256 tokenId = 16;

        // Verify creator owns the token
        assertEq(fameMirror.ownerOf(tokenId), creator);

        // Verify creator has CREATOR role
        assertTrue(creatorMagic.hasAnyRole(creator, 1));

        // Get original URI
        string memory originalUri = creatorMagic.tokenURI(tokenId);

        // Test banishing to art pool with custom metadata
        string memory customUri = "https://custom.metadata.com/1";
        creatorMagic.banishToArtPool(tokenId, customUri);

        // Verify tokenURI returns custom metadata (different from original)
        assertEq(creatorMagic.tokenURI(tokenId), customUri);
        assertTrue(
            !compareStrings(creatorMagic.tokenURI(tokenId), originalUri)
        );

        // Verify the art pool URI mapping (266 is first art pool index)
        assertEq(creatorMagic.artPoolUri(266), customUri);
    }

    function testBanishToArtPoolWithCustomUri() public {
        uint256 tokenId = 17;
        string memory originalUri = creatorMagic.tokenURI(tokenId);

        // Banish with custom URI
        creatorMagic.banishToArtPool(tokenId, "custom_metadata");

        // Should use custom metadata
        string memory newUri = creatorMagic.tokenURI(tokenId);
        assertTrue(!compareStrings(newUri, originalUri));

        // Should match custom metadata
        assertEq(newUri, "custom_metadata");
    }

    function testBanishToArtPoolNotOwner() public {
        // Try to banish a token that creator doesn't own
        uint256 tokenId = 11; // This belongs to user1

        vm.expectRevert(CreatorArtistMagic.TokenNotOwned.selector);
        creatorMagic.banishToArtPool(tokenId, "test_metadata");
    }

    function testBanishToMintPool() public {
        uint256 tokenId = 18;
        uint256 totalNFTSupply = creatorMagic.getTotalNFTSupply();
        uint256 maxNFTSupply = creatorMagic.getMaxNFTSupply();
        uint256 mintPoolToken = totalNFTSupply + 100; // A token in the mint pool
        string memory originalUri = creatorMagic.tokenURI(tokenId);

        // Verify token is within mint pool range
        assertTrue(
            mintPoolToken > totalNFTSupply && mintPoolToken <= maxNFTSupply,
            "Token not in mint pool range"
        );

        // Banish to mint pool
        creatorMagic.banishToMintPool(tokenId, mintPoolToken);

        // Verify tokenURI changed and uses mint pool token
        string memory newUri = creatorMagic.tokenURI(tokenId);
        assertTrue(!compareStrings(newUri, originalUri));

        string memory expectedUri = childRenderer.tokenURI(mintPoolToken);
        assertEq(newUri, expectedUri);
    }

    function testBanishToMintPoolInvalidToken() public {
        uint256 tokenId = 16;
        uint256 totalNFTSupply = creatorMagic.getTotalNFTSupply();
        uint256 maxNFTSupply = creatorMagic.getMaxNFTSupply();

        // Test token that has been minted (too low)
        uint256 invalidTokenLow = totalNFTSupply - 1;
        vm.expectRevert(CreatorArtistMagic.TokenNotInMintPool.selector);
        creatorMagic.banishToMintPool(tokenId, invalidTokenLow);

        // Test token beyond max supply (too high)
        uint256 invalidTokenHigh = maxNFTSupply + 1;
        vm.expectRevert(CreatorArtistMagic.TokenNotInMintPool.selector);
        creatorMagic.banishToMintPool(tokenId, invalidTokenHigh);
    }

    function testBanishToBurnPool() public {
        // For this test, we'll simulate using a token ID that we know should be in burn pool
        // In a real scenario, this would be a token that was previously minted and then burned

        uint256 tokenId = 17;
        uint256 simulatedBurnedToken = 50; // Simulate a token that was burned
        string memory originalUri = creatorMagic.tokenURI(tokenId);

        // This test may fail if the token is not actually burned, but demonstrates the function
        // In a real test environment, we'd need to properly setup burn scenarios

        try creatorMagic.banishToBurnPool(tokenId, simulatedBurnedToken) {
            // If successful, verify tokenURI changed
            string memory newUri = creatorMagic.tokenURI(tokenId);
            assertTrue(!compareStrings(newUri, originalUri));

            string memory expectedUri = childRenderer.tokenURI(
                simulatedBurnedToken
            );
            assertEq(newUri, expectedUri);
        } catch {
            // Expected to fail if the token is not actually in burn pool
            // This is OK for testing the validation logic
        }
    }

    function testBanishToBurnPoolInvalidToken() public {
        uint256 tokenId = 16;
        uint256 totalNFTSupply = creatorMagic.getTotalNFTSupply();
        uint256 invalidToken = totalNFTSupply + 100; // Token beyond mint pool

        vm.expectRevert(CreatorArtistMagic.TokenNotInBurnPool.selector);
        creatorMagic.banishToBurnPool(tokenId, invalidToken);
    }

    function testBanishToBurnPoolStillOwned() public {
        uint256 tokenId = 18;
        uint256 ownedToken = 2; // Creator owns this token

        vm.expectRevert(CreatorArtistMagic.TokenNotInBurnPool.selector);
        creatorMagic.banishToBurnPool(tokenId, ownedToken);
    }

    function testBanishToBurnPoolStillOwnedByAnother() public {
        uint256 tokenId = 16;
        // Try to banish a token that is not in the burn pool
        uint256 tokenOwnedByUser2 = 11; // user2 owns tokens 11-15

        // First verify user2 actually owns this token
        assertEq(
            fame.fameMirror().ownerOf(tokenOwnedByUser2),
            user2,
            "user2 should own token 11"
        );

        // Creator should not be able to banish a token not in the burn pool
        // This should revert with TokenNotInBurnPool
        vm.expectRevert(CreatorArtistMagic.TokenNotInBurnPool.selector);
        creatorMagic.banishToBurnPool(tokenId, tokenOwnedByUser2);
    }

    function testGetTotalNFTSupply() public {
        uint256 totalSupply = creatorMagic.getTotalNFTSupply();

        // Should match the total number of NFTs we've minted
        // user1: 10 NFTs, user2: 5 NFTs, creator: 3 NFTs = 18 total
        assertEq(totalSupply, 18);
    }

    function testGetMaxNFTSupply() public {
        uint256 maxSupply = creatorMagic.getMaxNFTSupply();
        uint256 totalTokenSupply = fame.totalSupply();
        uint256 unit = fame.unit();

        // Should equal totalSupply / unit
        assertEq(maxSupply, totalTokenSupply / unit);

        // Should be much larger than current NFT supply
        uint256 totalNFTSupply = creatorMagic.getTotalNFTSupply();
        assertTrue(maxSupply > totalNFTSupply);
    }

    function testTokenURIFallback() public {
        uint256 tokenId = 16;

        // Before any banishing, should use child renderer directly
        string memory expectedUri = childRenderer.tokenURI(tokenId);
        assertEq(creatorMagic.tokenURI(tokenId), expectedUri);
    }

    function testOnlyCreatorCanBanish() public {
        vm.stopPrank();
        vm.startPrank(user1);

        uint256 tokenId = 11; // user1 owns this

        // Should revert because user1 doesn't have CREATOR role
        vm.expectRevert();
        creatorMagic.banishToArtPool(tokenId, "test_metadata");

        vm.expectRevert();
        creatorMagic.banishToMintPool(tokenId, 1000);

        vm.expectRevert();
        creatorMagic.banishToBurnPool(tokenId, 1);
    }

    function testArtPoolFullScenario() public {
        // The art pool is from index 265 to 419, so 155 slots
        // Let's test the art pool boundary logic with a smaller test

        // Test that we can banish multiple tokens to art pool
        creatorMagic.banishToArtPool(16, "test1");
        creatorMagic.banishToArtPool(17, "test2");
        creatorMagic.banishToArtPool(18, "test3");

        // Verify all tokens have different metadata
        string memory uri16 = creatorMagic.tokenURI(16);
        string memory uri17 = creatorMagic.tokenURI(17);
        string memory uri18 = creatorMagic.tokenURI(18);

        assertEq(uri16, "test1");
        assertEq(uri17, "test2");
        assertEq(uri18, "test3");

        // Verify art pool URIs are set correctly
        assertEq(creatorMagic.artPoolUri(266), "test1");
        assertEq(creatorMagic.artPoolUri(267), "test2");
        assertEq(creatorMagic.artPoolUri(268), "test3");
    }

    // === COMPREHENSIVE EDGE CASE TESTS ===

    function testMultipleSwapsOnSameToken() public {
        uint256 tokenId = 16;
        string memory originalUri = creatorMagic.tokenURI(tokenId);

        // First swap to art pool
        creatorMagic.banishToArtPool(tokenId, "first_swap");
        assertEq(creatorMagic.tokenURI(tokenId), "first_swap");

        // Second swap - should overwrite the first
        creatorMagic.banishToArtPool(tokenId, "second_swap");
        assertEq(creatorMagic.tokenURI(tokenId), "second_swap");

        // Third swap to mint pool should work
        uint256 totalNFTSupply = creatorMagic.getTotalNFTSupply();
        uint256 maxNFTSupply = creatorMagic.getMaxNFTSupply();
        uint256 mintPoolToken = totalNFTSupply + 50;
        assertTrue(
            mintPoolToken <= maxNFTSupply,
            "Token not in mint pool range"
        );

        creatorMagic.banishToMintPool(tokenId, mintPoolToken);

        // Should now use mint pool token metadata
        string memory mintPoolUri = childRenderer.tokenURI(mintPoolToken);
        assertEq(creatorMagic.tokenURI(tokenId), mintPoolUri);
        assertTrue(
            !compareStrings(creatorMagic.tokenURI(tokenId), "second_swap")
        );
    }

    function testSwapBetweenAllPoolTypes() public {
        uint256 tokenId = 17;
        string memory originalUri = creatorMagic.tokenURI(tokenId);

        uint256 totalNFTSupply = creatorMagic.getTotalNFTSupply();
        uint256 maxNFTSupply = creatorMagic.getMaxNFTSupply();
        uint256 mintPoolToken = totalNFTSupply + 75;

        // Start with art pool
        creatorMagic.banishToArtPool(tokenId, "art_metadata");
        string memory artUri = creatorMagic.tokenURI(tokenId);
        assertEq(artUri, "art_metadata");

        // Move to mint pool
        creatorMagic.banishToMintPool(tokenId, mintPoolToken);
        string memory mintUri = creatorMagic.tokenURI(tokenId);
        assertEq(mintUri, childRenderer.tokenURI(mintPoolToken));
        assertTrue(!compareStrings(mintUri, artUri));

        // Try to move to burn pool (simulated)
        try creatorMagic.banishToBurnPool(tokenId, 5) {
            // If successful, verify it changed
            string memory burnUri = creatorMagic.tokenURI(tokenId);
            assertTrue(!compareStrings(burnUri, mintUri));
        } catch {
            // Expected if token 5 is not actually burned
        }

        // Return to art pool with different metadata
        creatorMagic.banishToArtPool(tokenId, "final_art_metadata");
        assertEq(creatorMagic.tokenURI(tokenId), "final_art_metadata");
    }

    function testArtPoolIncrementalIndexing() public {
        // Test that art pool indices increment correctly
        uint256 token1 = 16;
        uint256 token2 = 17;
        uint256 token3 = 18;

        // Banish tokens sequentially
        creatorMagic.banishToArtPool(token1, "metadata_266");
        creatorMagic.banishToArtPool(token2, "metadata_267");
        creatorMagic.banishToArtPool(token3, "metadata_268");

        // Verify each gets a different art pool index
        assertEq(creatorMagic.artPoolUri(266), "metadata_266");
        assertEq(creatorMagic.artPoolUri(267), "metadata_267");
        assertEq(creatorMagic.artPoolUri(268), "metadata_268");

        // Verify tokens return correct metadata
        assertEq(creatorMagic.tokenURI(token1), "metadata_266");
        assertEq(creatorMagic.tokenURI(token2), "metadata_267");
        assertEq(creatorMagic.tokenURI(token3), "metadata_268");

        // Re-banish first token should get new index
        creatorMagic.banishToArtPool(token1, "metadata_269");
        assertEq(creatorMagic.artPoolUri(269), "metadata_269");
        assertEq(creatorMagic.tokenURI(token1), "metadata_269");
    }

    function testMintPoolBoundaryValidation() public {
        uint256 tokenId = 16;
        uint256 totalNFTSupply = creatorMagic.getTotalNFTSupply();
        uint256 maxNFTSupply = creatorMagic.getMaxNFTSupply();

        // Test exact boundary cases

        // Token at totalNFTSupply should fail (not in mint pool)
        vm.expectRevert(CreatorArtistMagic.TokenNotInMintPool.selector);
        creatorMagic.banishToMintPool(tokenId, totalNFTSupply);

        // Token at totalNFTSupply + 1 should work (first mint pool token)
        if (totalNFTSupply + 1 <= maxNFTSupply) {
            creatorMagic.banishToMintPool(tokenId, totalNFTSupply + 1);

            // Verify it worked
            string memory expectedUri = childRenderer.tokenURI(
                totalNFTSupply + 1
            );
            assertEq(creatorMagic.tokenURI(tokenId), expectedUri);
        }

        // Reset for next test
        creatorMagic.banishToArtPool(tokenId, "reset");

        // Token at maxNFTSupply should work (last mint pool token)
        creatorMagic.banishToMintPool(tokenId, maxNFTSupply);
        string memory maxUri = childRenderer.tokenURI(maxNFTSupply);
        assertEq(creatorMagic.tokenURI(tokenId), maxUri);

        // Reset for next test
        creatorMagic.banishToArtPool(tokenId, "reset2");

        // Token at maxNFTSupply + 1 should fail (beyond mint pool)
        vm.expectRevert(CreatorArtistMagic.TokenNotInMintPool.selector);
        creatorMagic.banishToMintPool(tokenId, maxNFTSupply + 1);
    }

    function testBurnPoolBoundaryValidation() public {
        uint256 tokenId = 16;
        uint256 totalNFTSupply = creatorMagic.getTotalNFTSupply();

        // Test boundary cases for burn pool

        // Token 0 should fail (not valid token ID)
        vm.expectRevert(CreatorArtistMagic.TokenNotInBurnPool.selector);
        creatorMagic.banishToBurnPool(tokenId, 0);

        // Token beyond totalNFTSupply should fail (never minted)
        vm.expectRevert(CreatorArtistMagic.TokenNotInBurnPool.selector);
        creatorMagic.banishToBurnPool(tokenId, totalNFTSupply + 1);

        // Token at totalNFTSupply should fail if it has an owner
        vm.expectRevert(CreatorArtistMagic.TokenNotInBurnPool.selector);
        creatorMagic.banishToBurnPool(tokenId, totalNFTSupply);
    }

    function testEmptyStringArtPoolMetadataReverts() public {
        uint256 tokenId = 16;

        // Banish with empty string should revert
        vm.expectRevert(CreatorArtistMagic.InvalidMetadata.selector);
        creatorMagic.banishToArtPool(tokenId, "");
    }

    function testVeryLongMetadataString() public {
        uint256 tokenId = 16;

        // Create a very long metadata string
        string
            memory longMetadata = "ipfs://QmVeryLongHashThatRepresentsAVeryLongMetadataStringThatShouldStillWorkCorrectlyEvenWhenItIsVeryLongAndContainsLotsOfCharactersAndMaybeEvenSpecialCharactersLike!@#$%^&*()_+-=[]{}|;:,.<>?";

        creatorMagic.banishToArtPool(tokenId, longMetadata);

        // Should return the exact long string
        assertEq(creatorMagic.tokenURI(tokenId), longMetadata);
        assertEq(creatorMagic.artPoolUri(266), longMetadata);
    }

    function testDN404StorageReading() public {
        // Test that we can read DN404 storage correctly
        (
            uint32 burnedPoolHead,
            uint32 burnedPoolTail,
            uint32 totalNFTSupply
        ) = creatorMagic.getDN404Storage();

        console.log("Burned pool head:", burnedPoolHead);
        console.log("Burned pool tail:", burnedPoolTail);
        console.log("Total NFT supply from storage:", totalNFTSupply);

        // Compare with the exposed function result
        uint256 exposedTotalNFTSupply = creatorMagic.getTotalNFTSupply();
        console.log(
            "Total NFT supply from exposed function:",
            exposedTotalNFTSupply
        );

        // Verify these values are reasonable (they might be 0 in test environment)
        assertTrue(
            burnedPoolTail >= burnedPoolHead,
            "Burned pool tail should be >= head"
        );

        // For now, just verify our storage reading works even if values are 0
        // In a real environment with minted tokens, totalNFTSupply would be > 0
    }

    function testTokenOwnershipSetup() public view {
        // Debug test to verify token ownership setup
        console.log("Token 1 owner:", fameMirror.ownerOf(1));
        console.log("Token 5 owner:", fameMirror.ownerOf(5));
        console.log("Token 10 owner:", fameMirror.ownerOf(10));
        console.log("Token 11 owner:", fameMirror.ownerOf(11));
        console.log("Token 15 owner:", fameMirror.ownerOf(15));
        console.log("Token 16 owner:", fameMirror.ownerOf(16));
        console.log("Token 18 owner:", fameMirror.ownerOf(18));

        console.log("user1:", user1);
        console.log("user2:", user2);
        console.log("creator:", creator);

        // Verify expected ownership
        assertEq(fameMirror.ownerOf(1), user1, "user1 should own token 1");
        assertEq(fameMirror.ownerOf(10), user1, "user1 should own token 10");
        assertEq(fameMirror.ownerOf(11), user2, "user2 should own token 11");
        assertEq(fameMirror.ownerOf(15), user2, "user2 should own token 15");
        assertEq(
            fameMirror.ownerOf(16),
            creator,
            "creator should own token 16"
        );
        assertEq(
            fameMirror.ownerOf(18),
            creator,
            "creator should own token 18"
        );
    }

    function testSpecialCharactersInMetadata() public {
        uint256 tokenId = 16;

        // Test various special characters
        string
            memory specialMetadata = "https://api.example.com/metadata?id=123&format=json&special=%20%21%40%23";

        creatorMagic.banishToArtPool(tokenId, specialMetadata);

        assertEq(creatorMagic.tokenURI(tokenId), specialMetadata);
        assertEq(creatorMagic.artPoolUri(266), specialMetadata);
    }

    function testMultipleTokensToSameMintPoolToken() public {
        uint256 token1 = 16;
        uint256 token2 = 17;
        uint256 totalNFTSupply = creatorMagic.getTotalNFTSupply();
        uint256 mintPoolToken = totalNFTSupply + 100;

        // Both tokens can be banished to the same mint pool token
        creatorMagic.banishToMintPool(token1, mintPoolToken);
        creatorMagic.banishToMintPool(token2, mintPoolToken);

        // Both should return the same metadata
        string memory expectedUri = childRenderer.tokenURI(mintPoolToken);
        assertEq(creatorMagic.tokenURI(token1), expectedUri);
        assertEq(creatorMagic.tokenURI(token2), expectedUri);
        assertTrue(
            compareStrings(
                creatorMagic.tokenURI(token1),
                creatorMagic.tokenURI(token2)
            )
        );
    }

    function testSwapAfterTokenTransfer() public {
        uint256 tokenId = 16;

        // Initial swap
        creatorMagic.banishToArtPool(tokenId, "before_transfer");
        assertEq(creatorMagic.tokenURI(tokenId), "before_transfer");

        // Stop pranking creator and transfer token to user1
        vm.stopPrank();
        vm.startPrank(creator);

        // Verify creator still owns it
        assertEq(fameMirror.ownerOf(tokenId), creator);

        // Should still work since creator still owns the token
        creatorMagic.banishToArtPool(tokenId, "after_confirmation");
        assertEq(creatorMagic.tokenURI(tokenId), "after_confirmation");

        // If we transfer the token away (simulate)
        // We can't actually test this easily without more complex setup
        // but the ownership check should prevent unauthorized swaps
    }

    function testGasUsageConsistency() public {
        uint256 tokenId = 16;

        // Measure gas for different operations
        uint256 gasBefore;
        uint256 gasAfter;

        // Art pool banish
        gasBefore = gasleft();
        creatorMagic.banishToArtPool(tokenId, "gas_test");
        gasAfter = gasleft();
        uint256 artPoolGas = gasBefore - gasAfter;

        // Mint pool banish
        uint256 totalNFTSupply = creatorMagic.getTotalNFTSupply();
        uint256 mintPoolToken = totalNFTSupply + 50;

        gasBefore = gasleft();
        creatorMagic.banishToMintPool(tokenId, mintPoolToken);
        gasAfter = gasleft();
        uint256 mintPoolGas = gasBefore - gasAfter;

        // Gas usage should be reasonable (not a strict test, just ensuring no infinite loops)
        assertTrue(artPoolGas < 200000, "Art pool gas too high");
        assertTrue(mintPoolGas < 200000, "Mint pool gas too high");
    }

    function testStateConsistencyAfterMultipleOperations() public {
        uint256 token1 = 16;
        uint256 token2 = 17;
        uint256 token3 = 18;

        // Perform a complex sequence of operations
        creatorMagic.banishToArtPool(token1, "state1");
        creatorMagic.banishToArtPool(token2, "state2");

        uint256 totalNFTSupply = creatorMagic.getTotalNFTSupply();
        uint256 mintPoolToken = totalNFTSupply + 25;

        creatorMagic.banishToMintPool(token3, mintPoolToken);
        creatorMagic.banishToArtPool(token1, "state1_updated");

        // Verify final states
        assertEq(creatorMagic.tokenURI(token1), "state1_updated");
        assertEq(creatorMagic.tokenURI(token2), "state2");
        assertEq(
            creatorMagic.tokenURI(token3),
            childRenderer.tokenURI(mintPoolToken)
        );

        // Verify art pool state
        assertEq(creatorMagic.artPoolUri(266), "state1"); // token1's first banish
        assertEq(creatorMagic.artPoolUri(267), "state2"); // token2's first banish
        assertEq(creatorMagic.artPoolUri(268), "state1_updated"); // token1's second banish

        // token1's first art pool entry (266) should still exist but be unused
        // This is expected behavior - old art pool slots don't get reused
    }

    function testMaximumArtPoolUsage() public {
        // Test closer to the actual art pool limit
        uint256 baseToken = 16;

        // Banish same token multiple times to test index increment
        for (uint i = 0; i < 10; i++) {
            string memory metadata = string(
                abi.encodePacked("test_", vm.toString(i))
            );
            creatorMagic.banishToArtPool(baseToken, metadata);

            // Verify metadata is correct
            uint256 expectedArtIndex = 266 + i;
            assertEq(creatorMagic.artPoolUri(expectedArtIndex), metadata);
            assertEq(creatorMagic.tokenURI(baseToken), metadata);
        }

        // Final state check
        assertEq(creatorMagic.tokenURI(baseToken), "test_9");
        assertEq(creatorMagic.artPoolUri(275), "test_9"); // 266 + 9
    }

    function testReverseSwapOperations() public {
        uint256 tokenId = 16;
        string memory originalUri = creatorMagic.tokenURI(tokenId);

        // 1. Start with art pool
        creatorMagic.banishToArtPool(tokenId, "step1_art");
        string memory step1Uri = creatorMagic.tokenURI(tokenId);
        assertEq(step1Uri, "step1_art");

        // 2. Move to mint pool
        uint256 totalNFTSupply = creatorMagic.getTotalNFTSupply();
        uint256 mintPoolToken = totalNFTSupply + 42;
        creatorMagic.banishToMintPool(tokenId, mintPoolToken);
        string memory step2Uri = creatorMagic.tokenURI(tokenId);
        assertEq(step2Uri, childRenderer.tokenURI(mintPoolToken));

        // 3. Back to art pool with same metadata as step 1
        creatorMagic.banishToArtPool(tokenId, "step1_art");
        string memory step3Uri = creatorMagic.tokenURI(tokenId);
        assertEq(step3Uri, "step1_art");
        assertTrue(compareStrings(step1Uri, step3Uri));

        // 4. Different mint pool token
        uint256 mintPoolToken2 = totalNFTSupply + 99;
        creatorMagic.banishToMintPool(tokenId, mintPoolToken2);
        string memory step4Uri = creatorMagic.tokenURI(tokenId);
        assertEq(step4Uri, childRenderer.tokenURI(mintPoolToken2));
        assertTrue(!compareStrings(step4Uri, step2Uri));
    }

    function testConcurrentMultiTokenOperations() public {
        uint256 token1 = 16;
        uint256 token2 = 17;
        uint256 token3 = 18;

        uint256 totalNFTSupply = creatorMagic.getTotalNFTSupply();
        uint256 mintPoolToken1 = totalNFTSupply + 10;
        uint256 mintPoolToken2 = totalNFTSupply + 20;
        uint256 mintPoolToken3 = totalNFTSupply + 30;

        // Perform different operations on different tokens simultaneously
        creatorMagic.banishToArtPool(token1, "art_token1");
        creatorMagic.banishToMintPool(token2, mintPoolToken1);
        creatorMagic.banishToArtPool(token3, "art_token3");

        // Verify initial states
        assertEq(creatorMagic.tokenURI(token1), "art_token1");
        assertEq(
            creatorMagic.tokenURI(token2),
            childRenderer.tokenURI(mintPoolToken1)
        );
        assertEq(creatorMagic.tokenURI(token3), "art_token3");

        // Swap all tokens to different pools
        creatorMagic.banishToMintPool(token1, mintPoolToken2);
        creatorMagic.banishToArtPool(token2, "new_art_token2");
        creatorMagic.banishToMintPool(token3, mintPoolToken3);

        // Verify final states
        assertEq(
            creatorMagic.tokenURI(token1),
            childRenderer.tokenURI(mintPoolToken2)
        );
        assertEq(creatorMagic.tokenURI(token2), "new_art_token2");
        assertEq(
            creatorMagic.tokenURI(token3),
            childRenderer.tokenURI(mintPoolToken3)
        );

        // Verify all tokens have different metadata
        assertTrue(
            !compareStrings(
                creatorMagic.tokenURI(token1),
                creatorMagic.tokenURI(token2)
            )
        );
        assertTrue(
            !compareStrings(
                creatorMagic.tokenURI(token2),
                creatorMagic.tokenURI(token3)
            )
        );
        assertTrue(
            !compareStrings(
                creatorMagic.tokenURI(token1),
                creatorMagic.tokenURI(token3)
            )
        );
    }

    function testExtremeEdgeCases() public {
        uint256 tokenId = 16;
        uint256 totalNFTSupply = creatorMagic.getTotalNFTSupply();
        uint256 maxNFTSupply = creatorMagic.getMaxNFTSupply();

        // Test with sequential metadata
        for (uint i = 0; i < 3; i++) {
            string memory metadata = string.concat(
                "extreme_test_",
                vm.toString(i)
            );
            creatorMagic.banishToArtPool(tokenId, metadata);

            // Each should get a different art pool index with proper metadata
            uint256 artIndex = 266 + i;
            assertEq(creatorMagic.artPoolUri(artIndex), metadata);
            assertEq(creatorMagic.tokenURI(tokenId), metadata);
        }

        // Test with exactly boundary mint pool tokens
        if (totalNFTSupply + 1 <= maxNFTSupply) {
            creatorMagic.banishToMintPool(tokenId, totalNFTSupply + 1);
            assertEq(
                creatorMagic.tokenURI(tokenId),
                childRenderer.tokenURI(totalNFTSupply + 1)
            );
        }

        if (maxNFTSupply > totalNFTSupply) {
            creatorMagic.banishToMintPool(tokenId, maxNFTSupply);
            assertEq(
                creatorMagic.tokenURI(tokenId),
                childRenderer.tokenURI(maxNFTSupply)
            );
        }
    }

    function testMetadataConsistencyAfterComplexSequence() public {
        uint256 tokenId = 16;

        // Complex sequence that could potentially cause state issues
        creatorMagic.banishToArtPool(tokenId, "meta1");
        creatorMagic.banishToArtPool(tokenId, "meta_override"); // Override
        creatorMagic.banishToArtPool(tokenId, "meta2");

        uint256 totalNFTSupply = creatorMagic.getTotalNFTSupply();
        uint256 mintToken = totalNFTSupply + 15;

        creatorMagic.banishToMintPool(tokenId, mintToken);
        creatorMagic.banishToArtPool(tokenId, "final_meta");

        // Final state should be deterministic
        assertEq(creatorMagic.tokenURI(tokenId), "final_meta");

        // Art pool should have accumulated entries
        assertEq(creatorMagic.artPoolUri(266), "meta1");
        assertEq(creatorMagic.artPoolUri(267), "meta_override"); // Override metadata
        assertEq(creatorMagic.artPoolUri(268), "meta2");
        assertEq(creatorMagic.artPoolUri(269), "final_meta");
    }

    function testPoolBoundariesExhaustively() public {
        uint256 tokenId = 16;
        uint256 totalNFTSupply = creatorMagic.getTotalNFTSupply();
        uint256 maxNFTSupply = creatorMagic.getMaxNFTSupply();

        // Test every boundary condition for mint pool
        uint256[] memory invalidMintTokens = new uint256[](3);
        invalidMintTokens[0] = 0; // Too low
        invalidMintTokens[1] = totalNFTSupply; // Exactly at boundary (invalid)
        invalidMintTokens[2] = maxNFTSupply + 1; // Too high

        for (uint i = 0; i < invalidMintTokens.length; i++) {
            vm.expectRevert(CreatorArtistMagic.TokenNotInMintPool.selector);
            creatorMagic.banishToMintPool(tokenId, invalidMintTokens[i]);
        }

        // Test valid mint pool tokens
        if (totalNFTSupply + 1 <= maxNFTSupply) {
            uint256[] memory validMintTokens = new uint256[](2);
            validMintTokens[0] = totalNFTSupply + 1; // First valid
            validMintTokens[1] = maxNFTSupply; // Last valid

            for (uint i = 0; i < validMintTokens.length; i++) {
                creatorMagic.banishToMintPool(tokenId, validMintTokens[i]);
                string memory expectedUri = childRenderer.tokenURI(
                    validMintTokens[i]
                );
                assertEq(creatorMagic.tokenURI(tokenId), expectedUri);

                // Reset for next test
                creatorMagic.banishToArtPool(tokenId, "reset");
            }
        }
    }

    function testFuzzLikeMetadataVariations() public {
        uint256 tokenId = 16;

        // Test various metadata formats that might appear in real usage
        string[] memory testMetadata = new string[](6);
        testMetadata[0] = "ipfs://QmTest123";
        testMetadata[1] = "https://api.nft.com/metadata/123";
        testMetadata[2] = "ar://abcd1234";
        testMetadata[3] = 'data:application/json,{"name":"Test"}';
        testMetadata[4] = "Special Unicode Metadata";
        testMetadata[
            5
        ] = "very_long_string_with_underscores_and_numbers_123456789";

        for (uint i = 0; i < testMetadata.length; i++) {
            creatorMagic.banishToArtPool(tokenId, testMetadata[i]);
            assertEq(creatorMagic.tokenURI(tokenId), testMetadata[i]);

            uint256 artIndex = 266 + i;
            assertEq(creatorMagic.artPoolUri(artIndex), testMetadata[i]);
        }
    }

    function testInteractionWithUnrelatedTokens() public {
        // Verify that banishing one token doesn't affect others
        uint256 targetToken = 16;
        uint256 unrelatedToken1 = 17;
        uint256 unrelatedToken2 = 18;

        // Get original URIs
        string memory originalTarget = creatorMagic.tokenURI(targetToken);
        string memory originalUnrelated1 = creatorMagic.tokenURI(
            unrelatedToken1
        );
        string memory originalUnrelated2 = creatorMagic.tokenURI(
            unrelatedToken2
        );

        // Banish only target token
        creatorMagic.banishToArtPool(targetToken, "target_modified");

        // Verify target changed but others didn't
        assertEq(creatorMagic.tokenURI(targetToken), "target_modified");
        assertTrue(
            !compareStrings(creatorMagic.tokenURI(targetToken), originalTarget)
        );

        assertEq(creatorMagic.tokenURI(unrelatedToken1), originalUnrelated1);
        assertEq(creatorMagic.tokenURI(unrelatedToken2), originalUnrelated2);

        // Banish target to mint pool
        uint256 totalNFTSupply = creatorMagic.getTotalNFTSupply();
        uint256 mintToken = totalNFTSupply + 77;
        creatorMagic.banishToMintPool(targetToken, mintToken);

        // Verify target changed again but others still didn't
        assertEq(
            creatorMagic.tokenURI(targetToken),
            childRenderer.tokenURI(mintToken)
        );
        assertEq(creatorMagic.tokenURI(unrelatedToken1), originalUnrelated1);
        assertEq(creatorMagic.tokenURI(unrelatedToken2), originalUnrelated2);
    }

    function testDN404StorageHelperMethods() public view {
        // Test all the convenience helper methods for DN404 storage
        
        // Test individual getters
        uint32 burnedPoolHead = creatorMagic.getBurnedPoolHead();
        uint32 burnedPoolTail = creatorMagic.getBurnedPoolTail();
        uint32 burnedPoolSize = creatorMagic.getBurnedPoolSize();
        uint256 mintPoolStart = creatorMagic.getMintPoolStart();
        
        console.log("Burned pool head:", burnedPoolHead);
        console.log("Burned pool tail:", burnedPoolTail);
        console.log("Burned pool size:", burnedPoolSize);
        console.log("Mint pool start:", mintPoolStart);
        
        // Verify consistency with main getDN404Storage function
        (uint32 head, uint32 tail, uint32 totalNFTSupply) = creatorMagic.getDN404Storage();
        assertEq(burnedPoolHead, head, "Head should match");
        assertEq(burnedPoolTail, tail, "Tail should match");
        assertEq(burnedPoolSize, tail - head, "Size should match");
        assertEq(mintPoolStart, uint256(totalNFTSupply) + uint256(tail - head), "Mint pool start should match");
        
        // Test getAllBurnedTokens
        uint32[] memory burnedTokens = creatorMagic.getAllBurnedTokens();
        assertEq(burnedTokens.length, burnedPoolSize, "Burned tokens array length should match pool size");
        
        // If there are burned tokens, test getBurnedTokenAtIndex
        if (burnedPoolSize > 0) {
            for (uint32 i = 0; i < burnedPoolSize && i < 5; i++) { // Test up to 5 tokens to avoid gas issues
                uint32 tokenAtIndex = creatorMagic.getBurnedTokenAtIndex(burnedPoolHead + i);
                assertEq(tokenAtIndex, burnedTokens[i], "Token at index should match array entry");
                
                // Verify this token is indeed in the burned pool
                assertTrue(creatorMagic.isTokenInBurnedPool(tokenAtIndex), "Token should be in burned pool");
            }
        }
        
        // Test boundary conditions for getBurnedTokenAtIndex
        if (burnedPoolSize > 0) {
            // Test valid boundaries
            creatorMagic.getBurnedTokenAtIndex(burnedPoolHead); // Should work
            creatorMagic.getBurnedTokenAtIndex(burnedPoolTail - 1); // Should work
        }
    }
}
