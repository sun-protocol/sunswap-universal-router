// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

/// @notice A library to implement a flag to map all pools
library SwapFlags {
    /// @dev use [0-16[ bitmap for pooltype (16bits)
    /// @dev use [16-256[ bitmap for poolindex (240bits)

    uint256 internal constant MASK_UINT16 = 0xffff;

    // get[0-15] 16bits for pool type:
    // eg:
    // 0x0001 : exactPool
    // 0x0010 : PSMPool
    // 0x0100 : stable base  pool
    // 0x1000 : stable meta pool
    //Data is for reference only; the actual situation shall prevail.

    uint256 internal constant POOL_TYPE_EXACT_POOL = 0x0001;
    uint256 internal constant POOL_TYPE_PSM_POOL = 0x0010;
    uint256 internal constant POOL_TYPE_STABLE_BASE_POOL = 0x0100;
    uint256 internal constant POOL_TYPE_STABLE_META_POOL = 0x1000;

    function getPoolType(uint256 flag) internal pure returns (uint256) {
        return flag & MASK_UINT16;
    }

    function isBasePool(uint256 flag) internal pure returns (bool) {
        return (flag & MASK_UINT16) == POOL_TYPE_STABLE_BASE_POOL;
    }

    function isMetaPool(uint256 flag) internal pure returns (bool) {
        return (flag & MASK_UINT16) == POOL_TYPE_STABLE_META_POOL;
    }

    function isExactPool(uint256 flag) internal pure returns (bool) {
        return (flag & MASK_UINT16) == POOL_TYPE_EXACT_POOL;
    }

    function isPSMPool(uint256 flag) internal pure returns (bool) {
        return (flag & MASK_UINT16) == POOL_TYPE_PSM_POOL;
    }

    function getPoolIndex(uint256 flag) public pure returns (uint256) {
        return flag >> 16;
    }
}
