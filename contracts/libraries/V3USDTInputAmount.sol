// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

/// @notice Records the USDT input paid by the original payer during a V3 exact-output swap.
/// @dev Zero for paths whose original input token is not USDT.
library V3USDTInputAmount {
    // bytes32(uint256(keccak256("V3ActualAmountIn")) - 1)
    bytes32 constant SLOT = 0x78a46660e2a355b690f6029a3a751ce8f044f7e132ea13feb30b20fc0a174b8a;

    function set(uint256 amount) internal {
        assembly ("memory-safe") {
            tstore(SLOT, amount)
        }
    }

    function get() internal view returns (uint256 amount) {
        assembly ("memory-safe") {
            amount := tload(SLOT)
        }
    }
}
