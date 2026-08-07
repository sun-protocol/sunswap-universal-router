// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

// helper methods for interacting with TRC20 tokens  that do not consistently return true/false
library SafeTransferLib {
    uint256 constant NILE_CHAIN_ID = 0xcd8690dc;
    uint256 constant MAIN_CHAIN_ID = 0x2b6653dc;

    address constant USDTNileAddr = 0xECa9bC828A3005B9a3b909f2cc5c2a54794DE05F;
    address constant USDTMainAddr = 0xa614f803B6FD780986A42c78Ec9c7f77e6DeD13C;

    function safeApprove(
        address token,
        address to,
        uint256 value
    ) internal returns (bool) {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        return (success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal returns (bool) {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));

        if ((token == USDTMainAddr) && (block.chainid == MAIN_CHAIN_ID)) {
            return success;
        } else if ((token == USDTNileAddr) && (block.chainid == NILE_CHAIN_ID)) {
            return success;
        }
        return (success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal returns (bool) {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        return (success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function safeTransferETH(address to, uint256 value) internal returns (bool) {
        (bool success, ) = to.call{value: value}("");
        return success;
    }
}
