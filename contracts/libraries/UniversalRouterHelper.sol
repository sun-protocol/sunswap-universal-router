// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import {ISunswapExchange} from "../modules/sunswap/v1/interfaces/ISunswapExchange.sol";
import {IV1Factory} from "../modules/sunswap/v1/interfaces/IV1Factory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISunSwapV2Pair} from "../modules/sunswap/v2/interfaces/ISunSwapV2Pair.sol";
import {ISunSwapV3Pool} from "../modules/sunswap/v3/interfaces/ISunSwapV3Pool.sol";
import {IStableSwapFactory} from "../interfaces/IStableSwapFactory.sol";
import {BytesLib} from "./BytesLib.sol";
import {Constants} from "./Constants.sol";
import {CalldataDecoder} from "v4-periphery/src/libraries/CalldataDecoder.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";

library UniversalRouterHelper {
    using BytesLib for bytes;

    error InvalidPoolAddress();
    error InvalidPoolLength();
    error InvalidReserves();
    error InvalidPath();

    /**
     * Stable *************************************************
     */

    // get the pool info in stable swap
    function getStableInfo(
        address stableSwapFactory,
        address input,
        address output,
        uint256 flag
    )
        internal
        view
        returns (
            uint256 i,
            uint256 j,
            address swapContract,
            uint256 extension
        )
    {
        (i, j, swapContract, extension) = IStableSwapFactory(stableSwapFactory).getStableInfo(input, output, flag);
    }

    // function getStableAmountsIn(
    //     address stableSwapFactory,
    //     address stableSwapInfo,
    //     address[] calldata path,
    //     uint256[] calldata flag,
    //     uint256 amountOut
    // ) internal view returns (uint256[] memory amounts) {
    //     uint256 length = path.length;
    //     if (length < 2) revert InvalidPoolLength();

    //     amounts = new uint256[](length);
    //     amounts[length - 1] = amountOut;

    //     for (uint256 i = length - 1; i > 0; i--) {
    //         uint256 last = i - 1;
    //         (uint256 k, uint256 j, address swapContract) =
    //             getStableInfo(stableSwapFactory, path[last], path[i], flag[last]);
    //         amounts[last] = IStableSwapInfo(stableSwapInfo).get_dx(swapContract, k, j, amounts[i], type(uint256).max);
    //     }
    // }

    /**
     * V2 *************************************************
     */
    /// @notice Sorts two tokens to return token0 and token1
    /// @param tokenA The first token to sort
    /// @param tokenB The other token to sort
    /// @return token0 The smaller token by address value
    /// @return token1 The larger token by address value
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    /// @notice Calculates the v2 address for a pair assuming the input tokens are pre-sorted
    /// @param factory The address of the v2 factory
    /// @param initCodeHash The hash of the pair initcode
    /// @param token0 The pair's token0
    /// @param token1 The pair's token1
    /// @return pair The resultant v2 pair address
    function pairForPreSorted(
        address factory,
        bytes32 initCodeHash,
        address token0,
        address token1
    ) private pure returns (address pair) {
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(hex"41", factory, keccak256(abi.encodePacked(token0, token1)), initCodeHash)
                    )
                )
            )
        );
    }

    /// @notice Calculates the v2 address for a pair without making any external calls
    /// @param factory The address of the v2 factory
    /// @param initCodeHash The hash of the pair initcode
    /// @param tokenA One of the tokens in the pair
    /// @param tokenB The other token in the pair
    /// @return pair The resultant v2 pair address
    function pairFor(
        address factory,
        bytes32 initCodeHash,
        address tokenA,
        address tokenB
    ) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = pairForPreSorted(factory, initCodeHash, token0, token1);
    }

    /// @notice Calculates the v2 address for a pair and the pair's token0
    /// @param factory The address of the v2 factory
    /// @param initCodeHash The hash of the pair initcode
    /// @param tokenA One of the tokens in the pair
    /// @param tokenB The other token in the pair
    /// @return pair The resultant v2 pair address
    /// @return token0 The token considered token0 in this pair
    function pairAndToken0For(
        address factory,
        bytes32 initCodeHash,
        address tokenA,
        address tokenB
    ) internal pure returns (address pair, address token0) {
        address token1;
        (token0, token1) = sortTokens(tokenA, tokenB);
        pair = pairForPreSorted(factory, initCodeHash, token0, token1);
    }

    /// @notice Calculates the v2 address for a pair and fetches the reserves for each token
    /// @param factory The address of the v2 factory
    /// @param initCodeHash The hash of the pair initcode
    /// @param tokenA One of the tokens in the pair
    /// @param tokenB The other token in the pair
    /// @return pair The resultant v2 pair address
    /// @return reserveA The reserves for tokenA
    /// @return reserveB The reserves for tokenB
    function pairAndReservesFor(
        address factory,
        bytes32 initCodeHash,
        address tokenA,
        address tokenB
    )
        private
        view
        returns (
            address pair,
            uint256 reserveA,
            uint256 reserveB
        )
    {
        address token0;
        (pair, token0) = pairAndToken0For(factory, initCodeHash, tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1, ) = ISunSwapV2Pair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function exchangeAndReservesFor(
        address factory,
        address tokenA,
        address tokenB
    )
        internal
        view
        returns (
            address exchange,
            uint256 reserveA,
            uint256 reserveB
        )
    {
        if (tokenA == Constants.ETH) {
            exchange = IV1Factory(factory).getExchange(tokenB);
            reserveA = exchange.balance;
            reserveB = IERC20(tokenB).balanceOf(exchange);
        } else {
            exchange = IV1Factory(factory).getExchange(tokenA);
            reserveA = IERC20(tokenA).balanceOf(exchange);
            reserveB = exchange.balance;
        }
    }

    function getAmountInMultihopV1(
        address factory,
        address[] calldata path,
        uint256 amountOut
    ) internal view returns (uint256 amount, address exchange) {
        if (path.length < 2) revert InvalidPath();
        amount = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            uint256 reserveIn;
            uint256 reserveOut;

            (exchange, reserveIn, reserveOut) = exchangeAndReservesFor(factory, path[i - 1], path[i]);
            amount = getAmountIn(amount, reserveIn, reserveOut);
        }
    }

    /// @notice Given an input asset amount returns the maximum output amount of the other asset
    /// @param amountIn The token input amount
    /// @param reserveIn The reserves available of the input token
    /// @param reserveOut The reserves available of the output token
    /// @return amountOut The output amount of the output token
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        if (reserveIn == 0 || reserveOut == 0) revert InvalidReserves();
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /// @notice Returns the input amount needed for a desired output amount in a single-hop trade
    /// @param amountOut The desired output amount
    /// @param reserveIn The reserves available of the input token
    /// @param reserveOut The reserves available of the output token
    /// @return amountIn The input amount of the input token
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        if (reserveIn == 0 || reserveOut == 0) revert InvalidReserves();
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    /// @notice Returns the input amount needed for a desired output amount in a multi-hop trade
    /// @param factory The address of the v2 factory
    /// @param initCodeHash The hash of the pair initcode
    /// @param amountOut The desired output amount
    /// @param path The path of the multi-hop trade
    /// @return amount The input amount of the input token
    /// @return pair The first pair in the trade
    function getAmountInMultihop(
        address factory,
        bytes32 initCodeHash,
        uint256 amountOut,
        address[] calldata path
    ) internal view returns (uint256 amount, address pair) {
        if (path.length < 2) revert InvalidPath();
        amount = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            uint256 reserveIn;
            uint256 reserveOut;

            (pair, reserveIn, reserveOut) = pairAndReservesFor(factory, initCodeHash, path[i - 1], path[i]);
            amount = getAmountIn(amount, reserveIn, reserveOut);
        }
    }

    /**
     * V3 *************************************************
     */
    /// @notice Returns true iff the path contains two or more pools
    /// @param path The encoded swap path
    /// @return True if path contains two or more pools, otherwise false
    function hasMultiplePools(bytes calldata path) internal pure returns (bool) {
        return path.length >= Constants.MULTIPLE_V3_POOLS_MIN_LENGTH;
    }

    /// @notice Decodes the first pool in path
    /// @param path The bytes encoded swap path
    /// @return tokenA The first token of the given pool
    /// @return fee The fee level of the pool
    /// @return tokenB The second token of the given pool
    function decodeFirstPool(bytes calldata path)
        internal
        pure
        returns (
            address,
            uint24,
            address
        )
    {
        return path.toPool();
    }

    /// @notice Gets the segment corresponding to the first pool in the path
    /// @param path The bytes encoded swap path
    /// @return The segment containing all data necessary to target the first pool in the path
    function getFirstPool(bytes calldata path) internal pure returns (bytes calldata) {
        return path[:Constants.V3_POP_OFFSET];
    }

    function decodeFirstToken(bytes calldata path) internal pure returns (address tokenA) {
        tokenA = path.toAddress();
    }

    /// @notice Skips a token + fee element
    /// @param path The swap path
    function skipToken(bytes calldata path) internal pure returns (bytes calldata) {
        return path[Constants.NEXT_V3_POOL_OFFSET:];
    }

    function computePoolAddress(
        address deployer,
        bytes32 initCodeHash,
        address tokenA,
        address tokenB,
        uint24 fee
    ) internal pure returns (address pool) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(hex"41", deployer, keccak256(abi.encode(tokenA, tokenB, fee)), initCodeHash)
                    )
                )
            )
        );
    }

    /// @notice get v3 path（address[]） from v3 path（bytes）
    /// @param path v3 Path type bytes
    /// @return tokens for v3 path
    function decodeV3Path(bytes calldata path) internal pure returns (address[] memory tokens) {
        uint256 hops = (path.length - Constants.ADDR_SIZE) / Constants.NEXT_V3_POOL_OFFSET;
        uint256 numTokens = hops + 1;
        tokens = new address[](numTokens);

        uint256 offset = 0;
        for (uint256 i = 0; i < numTokens; i++) {
            tokens[i] = address(bytes20(path[offset:offset + Constants.ADDR_SIZE]));
            offset += (i < hops) ? Constants.NEXT_V3_POOL_OFFSET : Constants.ADDR_SIZE; // skip fee if not last
        }
    }

    /// @notice get v4 paths from v4 input bytes for a loop
    /// @dev Developer notes
    /// @param inputs v4 actions data, typed bytes
    /// @return tokens for v4 take/settle token addresses

    function decodeV4Actions(bytes calldata inputs) internal pure returns (address[] memory tokens) {
        (bytes calldata actions, bytes[] calldata params) = CalldataDecoder.decodeActionsRouterParams(inputs);
        tokens = new address[](params.length);

        for (uint256 i = 0; i < params.length; i++) {
            uint256 action = uint8(actions[i]);
            tokens[i] = _handleV4Action(action, params[i]);
        }
    }

    /// @notice handle v4 action to get token address
    /// @param action v4 action type
    /// @param params v4 action params
    /// @return token address for take/settle action

    function _handleV4Action(uint256 action, bytes calldata params) internal pure returns (address) {
        // swap actions and payment actions in different blocks for gas efficiency
        if (action == Actions.SETTLE_ALL) {
            (Currency currency, ) = CalldataDecoder.decodeCurrencyAndUint256(params);
            return Currency.unwrap(currency);
        } else if (action == Actions.TAKE_ALL) {
            (Currency currency, ) = CalldataDecoder.decodeCurrencyAndUint256(params);
            return Currency.unwrap(currency);
        } else if (action == Actions.SETTLE) {
            (Currency currency, , ) = CalldataDecoder.decodeCurrencyUint256AndBool(params);
            return Currency.unwrap(currency);
        } else if (action == Actions.TAKE) {
            (Currency currency, , ) = CalldataDecoder.decodeCurrencyAddressAndUint256(params);
            return Currency.unwrap(currency);
        } else if (action == Actions.TAKE_PORTION) {
            (Currency currency, , ) = CalldataDecoder.decodeCurrencyAddressAndUint256(params);
            return Currency.unwrap(currency);
        } else {
            return address(0);
        }
    }
}
