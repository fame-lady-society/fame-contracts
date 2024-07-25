// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {LibBitmap} from "solady/utils/LibBitmap.sol";

contract Bitmap {
    using LibBitmap for LibBitmap.Bitmap;

    LibBitmap.Bitmap bitmap;

    function get(uint256 index) public view returns (bool) {
        return bitmap.get(index);
    }

    function set(uint256 index) public {
        bitmap.set(index);
    }
}
