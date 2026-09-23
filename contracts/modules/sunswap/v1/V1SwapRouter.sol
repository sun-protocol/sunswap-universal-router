// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2025 SunSwap
pragma solidity ^0.8.0;

import {IV1Factory} from "./interfaces/IV1Factory.sol";
import {ISunswapExchange} from "./interfaces/ISunswapExchange.sol";
import {RouterImmutables} from "../../../base/RouterImmutables.sol";
import {Permit2Payments} from "../../Permit2Payments.sol";
import {Constants} from "../../../libraries/Constants.sol";
import {UniversalRouterHelper} from "../../../libraries/UniversalRouterHelper.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ActionConstants} from "v4-periphery/src/libraries/ActionConstants.sol";

/// @title Router for SunSwap V1 swaps
/// @dev Paths contain only the input and output currencies; Constants.ETH represents native TRX.
/// Token-to-token swaps use TRX as an intermediate currency inside the exchanges.
abstract contract V1SwapRouter is RouterImmutables, Permit2Payments {
    using SafeTransferLib for ERC20;
    error V1TooLittleReceived();
    error V1TooMuchRequested();
    error V1InvalidPath();
    error V1InvalidExchange();

    /// @notice Performs a SunSwap V1 exact input swap
    /// @dev Checks the output using the recipient's balance increase. Native TRX must already be in the Router.
    /// @param recipient The recipient of the output tokens or TRX
    /// @param amountIn The input amount, or CONTRACT_BALANCE to use the Router's entire input currency balance
    /// @param amountOutMinimum The minimum acceptable output amount
    /// @param path The two distinct input and output currency addresses, in swap order
    /// @param payer The input source; use address(this) for native TRX. Ignored when amountIn is CONTRACT_BALANCE
    function v1SwapExactInput(
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address[] calldata path,
        address payer
    ) internal {
        if (path.length != 2 || path[0] == path[1]) revert V1InvalidPath();

        if (amountIn == ActionConstants.CONTRACT_BALANCE) {
            amountIn = UniversalRouterHelper.getBalance(path[0], address(this));
        } else if (payer != address(this)) {
            payOrPermit2Transfer(path[0], payer, address(this), amountIn);
        }
        
        address tokenOut = path[1];
        uint256 balanceBefore = UniversalRouterHelper.getBalance(tokenOut, recipient);

        _v1SwapExactIn(path, recipient, amountIn);

        uint256 balanceAfter = UniversalRouterHelper.getBalance(tokenOut, recipient);
        uint256 amountOut = balanceAfter - balanceBefore;

        if (amountOut < amountOutMinimum) revert V1TooLittleReceived();
    }

    /// @notice Performs a SunSwap V1 exact output swap
    /// @dev Native TRX must already be in the Router. Unspent input remains available for subsequent commands;
    /// append a refund command before the Router's final safeVault sweep to return it to the user.
    /// @param recipient The recipient of the output tokens or TRX
    /// @param amountOut The requested output amount
    /// @param amountInMaximum The maximum acceptable input amount
    /// @param path The two distinct input and output currency addresses, in swap order
    /// @param payer The address supplying input tokens; must be address(this) for native TRX input
    function v1SwapExactOutput(
        address recipient,
        uint256 amountOut,
        uint256 amountInMaximum,
        address[] calldata path,
        address payer
    ) internal {
        // Keep only the input and output currencies; exchanges handle the intermediate TRX for token-to-token swaps.
        // Distinct endpoints prevent reuse of the same exchange in that internal route.
        if (path.length != 2 || path[0] == path[1]) revert V1InvalidPath();

        address tokenIn = path[0];
        (uint256 amountIn, address exchange, uint256 trxRequired) = _getV1AmountIn(path, amountOut);
        if (amountIn > amountInMaximum) revert V1TooMuchRequested();

        if (payer == address(this)) {
            if (UniversalRouterHelper.getBalance(tokenIn, address(this)) < amountIn) {
                revert V1TooMuchRequested();
            }
        } else {
            payOrPermit2Transfer(tokenIn, payer, address(this), amountIn);
        }
        _v1SwapExactOut(path, recipient, exchange, amountOut, amountIn, trxRequired);
    }

    /// @dev Quotes the required input using the exchanges' exact output prices.
    /// The caller must validate that the path contains two distinct currency addresses.
    /// @return amountIn The required input amount
    /// @return exchange The exchange to call: the output token's exchange for TRX input, otherwise the input token's
    /// @return trxRequired The intermediate TRX required for token-to-token swaps; zero for other directions
    function _getV1AmountIn(address[] calldata path, uint256 amountOut)
        private view returns (uint256 amountIn, address exchange, uint256 trxRequired)
    {
        address tokenIn = path[0];
        address tokenOut = path[1];
        exchange = IV1Factory(SUNSWAP_V1_FACTORY).getExchange(tokenIn == Constants.ETH ? tokenOut : tokenIn);
        if (exchange == address(0)) revert V1InvalidExchange();

        if (tokenIn == Constants.ETH) {
            amountIn = ISunswapExchange(exchange).getTrxToTokenOutputPrice(amountOut);
        } else if (tokenOut == Constants.ETH) {
            amountIn = ISunswapExchange(exchange).getTokenToTrxOutputPrice(amountOut);
        } else {
            // Token-to-token swaps bridge through TRX: quote the output pool first.
            address outputExchange = IV1Factory(SUNSWAP_V1_FACTORY).getExchange(tokenOut);
            if (outputExchange == address(0)) revert V1InvalidExchange();
            trxRequired = ISunswapExchange(outputExchange).getTrxToTokenOutputPrice(amountOut);
            amountIn = ISunswapExchange(exchange).getTokenToTrxOutputPrice(trxRequired);
        }
    }

    /// @dev Executes an exact input swap using funds held by the Router.
    /// The caller must validate the path and check the recipient's output against the requested minimum.
    function _v1SwapExactIn(address[] calldata path, address recipient, uint256 amountIn) private {
        (address input, address output) = (path[0], path[1]);
        address exchange = IV1Factory(SUNSWAP_V1_FACTORY).getExchange(input == Constants.ETH ? output : input);
        if (exchange == address(0)) revert V1InvalidExchange();

        if (input == Constants.ETH) {
            ISunswapExchange(exchange).trxToTokenTransferInput{value: amountIn}(
                1, block.timestamp + 1, recipient
            );
        } else {
            ERC20(input).safeApprove(exchange, amountIn);
            if (output == Constants.ETH) {
                ISunswapExchange(exchange).tokenToTrxTransferInput(
                    amountIn, 1, block.timestamp + 1, recipient
                );
            } else {
                ISunswapExchange(exchange).tokenToTokenTransferInput(
                    amountIn, 1, 1, block.timestamp + 1, recipient, output
                );
            }
        }
    }

    /// @dev Executes an exact output swap using Router funds and the limits returned by _getV1AmountIn.
    /// The caller must validate the path and fund the Router. Any unused token allowance is cleared after the swap.
    function _v1SwapExactOut(
        address[] calldata path,
        address recipient,
        address exchange,
        uint256 amountOut,
        uint256 amountIn,
        uint256 trxRequired
    ) private {
        address tokenIn = path[0];
        address tokenOut = path[1];
        uint256 actualAmountIn;
        if (tokenIn == Constants.ETH) {
            actualAmountIn = ISunswapExchange(exchange).trxToTokenTransferOutput{value: amountIn}(
                amountOut, block.timestamp + 1, recipient
            );
        } else {
            ERC20(tokenIn).safeApprove(exchange, amountIn);
            if (tokenOut == Constants.ETH) {
                actualAmountIn = ISunswapExchange(exchange).tokenToTrxTransferOutput(
                    amountOut, amountIn, block.timestamp + 1, recipient
                );
            } else {
                actualAmountIn = ISunswapExchange(exchange).tokenToTokenTransferOutput(
                    amountOut, amountIn, trxRequired, block.timestamp + 1, recipient, tokenOut
                );
            }
            ERC20(tokenIn).safeApprove(exchange, 0);
        }
        if (actualAmountIn > amountIn) revert V1TooMuchRequested();
    }
}
