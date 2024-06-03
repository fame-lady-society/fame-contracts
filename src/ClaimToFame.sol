// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin5/contracts/token/ERC20/IERC20.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";
import {LibBitmap} from "solady/utils/LibBitmap.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";

import "forge-std/console.sol";

contract ClaimToFame is OwnableRoles {
    using SignatureCheckerLib for address;
    using LibBitmap for LibBitmap.Bitmap;
    IERC20 public fameToken;
    mapping(address => uint256) private signatureNonces;
    LibBitmap.Bitmap private claimedBitmap;
    address private signer;

    constructor(address _fameToken, address _signer) {
        fameToken = IERC20(_fameToken);
        signer = _signer;
        _initializeOwner(msg.sender);
    }

    uint256 internal constant SIGNER = _ROLE_0;

    /**
     * @dev Returns the role that controls the trust and safety of the contract. This role can clear the metadata of a token in cases of vulgar or illegal content.
     */
    function roleSigner() public pure returns (uint256) {
        return SIGNER;
    }

    function claim(uint256 _amount) public {}

    /**
     * @dev Sets the signer address.
     * @param _signer address Signer address to assign.
     */
    function setSigner(address _signer) external onlyRolesOrOwner(SIGNER) {
        signer = _signer;
    }

    /**
     * @dev Returns the hash of an update request.
     * @param tokenId uint256 ID of the token to set its URI.
     * @param uri string URI to assign.
     * @param nonce uint256 Nonce of the update request.
     */
    function hashUpdateRequest(
        uint256 tokenId,
        string calldata uri,
        uint256 nonce
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenId, uri, nonce));
    }

    uint256 internal constant MAX_TOKENS = 8888;
    /**
     * @dev Returns packed byte bitmap data that represents all token ids in a packed format.
     * @param tokenIds uint256[] Array of token ids to pack.  Assumed to be sorted in ascending order.
     * @return bytes Packed byte data.
     */
    function generatePackedData(
        uint256[] calldata tokenIds
    ) public pure returns (bytes memory) {
        // First find the maximum token id in the array to determine the size of the bitmap.
        uint256 maxTokenId = tokenIds[tokenIds.length - 1];

        // Create a new bitmap with the maximum token id.
        bytes memory packedData = new bytes((maxTokenId / 8) + 1);

        // Now fill in the bitmap with the token ids by setting each bit to 1 that corresponds to a token id.
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            uint256 byteIndex = tokenId / 8;
            uint256 bitIndex = tokenId % 8;

            packedData[byteIndex] = bytes1(
                uint8(packedData[byteIndex]) | uint8(1 << bitIndex)
            );
        }

        return packedData;
    }

    function generateTokenIds(
        bytes calldata packedData
    ) public pure returns (uint256[] memory) {
        uint256 maxToken = packedData.length * 8;
        uint256[] memory tokenIds = new uint256[](maxToken);
        uint256 count = 0;
        for (uint256 i = 0; i < packedData.length; i++) {
            uint8 byteValue = uint8(packedData[i]);
            for (uint256 j = 0; j < 8; j++) {
                if (byteValue & (1 << j) != 0) {
                    tokenIds[count] = i * 8 + j;
                    count++;
                }
            }
        }
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = tokenIds[i];
        }
        return result;
    }

    error AlreadyCalimed(uint256 tokenId);
    /**
     * @dev Sets the claimed tokens for a user by walking through the bits in the packed token ids and setting the corresponding token ids in claimedBitmap.
     * @param packedTokenIds bytes Packed byte data that represents all token ids in a packed format.
     */
    function setClaimedData(bytes calldata packedTokenIds) internal {
        // Walk through the packedTokenIds to check each bit
        for (uint256 i = 0; i < packedTokenIds.length; i++) {
            uint8 byteValue = uint8(packedTokenIds[i]);
            for (uint256 j = 0; j < 8; j++) {
                if (byteValue & (1 << j) != 0) {
                    uint256 index = i * 8 + j;
                    if (claimedBitmap.get(index)) {
                        revert AlreadyCalimed(index);
                    }
                    claimedBitmap.set(index);
                }
            }
        }
    }

    function setClaimedTokens(uint16[] calldata tokenIds) public {
        uint16 length = uint16(tokenIds.length);
        for (uint16 i = 0; i < length; i++) {
            uint16 tokenId = tokenIds[i];
            if (claimedBitmap.get(tokenId)) {
                revert AlreadyCalimed(tokenId);
            }
            claimedBitmap.set(tokenId);
        }
    }

    function hashClaimDataRequest(
        address account,
        address contractAddress,
        uint256 amount,
        uint256 deadline,
        bytes calldata packedTokenIds,
        uint256 nonce
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    account,
                    contractAddress,
                    amount,
                    deadline,
                    packedTokenIds,
                    nonce
                )
            );
    }

    function hashClaimTokensRequest(
        address account,
        uint256 amount,
        uint256 deadline,
        uint16[] calldata tokenIds,
        uint256 nonce
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(account, amount, deadline, tokenIds, nonce)
            );
    }

    error InvalidSignature();
    error PastDeadline();
    function verifyClaimDataRequest(
        address account,
        address contractAddress,
        uint256 amount,
        uint256 deadline,
        bytes calldata packedTokenIds,
        bytes calldata signature
    ) public {
        if (block.timestamp > deadline) {
            revert PastDeadline();
        }
        bytes32 hash = hashClaimDataRequest(
            account,
            contractAddress,
            amount,
            deadline,
            packedTokenIds,
            signatureNonces[msg.sender]
        );
        if (
            !signer.isValidSignatureNow(
                SignatureCheckerLib.toEthSignedMessageHash(hash),
                signature
            )
        ) {
            revert InvalidSignature();
        }
        signatureNonces[msg.sender]++;
    }

    function verifyClaimTokensRequest(
        address account,
        uint256 amount,
        uint256 deadline,
        uint16[] calldata tokenIds,
        bytes calldata signature
    ) public {
        if (block.timestamp > deadline) {
            revert PastDeadline();
        }
        bytes32 hash = hashClaimTokensRequest(
            account,
            amount,
            deadline,
            tokenIds,
            signatureNonces[msg.sender]
        );
        if (
            !signer.isValidSignatureNow(
                SignatureCheckerLib.toEthSignedMessageHash(hash),
                signature
            )
        ) {
            revert InvalidSignature();
        }
        signatureNonces[msg.sender]++;
    }

    function claimWithData(
        address account,
        address contractAddress,
        uint256 amount,
        uint256 deadline,
        bytes calldata packedTokenIds,
        bytes calldata signature
    ) public {
        verifyClaimDataRequest(
            account,
            contractAddress,
            amount,
            deadline,
            packedTokenIds,
            signature
        );
        setClaimedData(packedTokenIds);
        fameToken.transfer(account, amount);
    }

    function claimWithTokens(
        address account,
        uint256 amount,
        uint256 deadline,
        uint16[] calldata tokenIds,
        bytes calldata signature
    ) public {
        verifyClaimTokensRequest(
            account,
            amount,
            deadline,
            tokenIds,
            signature
        );
        setClaimedTokens(tokenIds);
        fameToken.transfer(account, amount);
    }
}
