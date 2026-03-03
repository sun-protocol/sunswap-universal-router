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

/// @title Router for SunSwap v2 Trades
abstract contract V1SwapRouter is RouterImmutables, Permit2Payments {
    using SafeTransferLib for ERC20;
    error V1TooLittleReceived();
    error V1TooMuchRequested();
    error V1InvalidPath();
    error V1InvalidExchange();

    function _v1SwapExactIn(address[] calldata path, address recipient, address exchange, uint256 amountIn) private returns (uint256 amountOut) {
        unchecked {
            if (path.length < 2) revert V1InvalidPath();

            // cached to save on duplicate operations
            uint256 finalPairIndex = path.length - 1;
            uint256 penultimatePairIndex = finalPairIndex - 1;
            for(uint256 i; i < finalPairIndex; i++) {
                (address input, address output) = (path[i], path[i + 1]);
                if(exchange == address(0)) {
                    exchange = IV1Factory(SUNSWAP_V1_FACTORY).getExchange(input == Constants.ETH ? output : input);
                    if(exchange == address(0)) revert V1InvalidExchange();
                }
                if(input == Constants.ETH) {
                    amountOut = ISunswapExchange(exchange).trxToTokenTransferInput{value: amountIn}(
                        1, block.timestamp + 1, i < penultimatePairIndex ? address(this) : recipient
                    );
                } else if(output == Constants.ETH) {
                    ERC20(input).safeApprove(exchange, amountIn);
                    amountOut = ISunswapExchange(exchange).tokenToTrxTransferInput(
                        amountIn, 1, block.timestamp + 1, i < penultimatePairIndex ? address(this) : recipient
                    );
                } else {
                    ERC20(input).safeApprove(exchange, amountIn);
                    amountOut = ISunswapExchange(exchange).tokenToTokenTransferInput(
                        amountIn, 1, 1, block.timestamp + 1, i < penultimatePairIndex ? address(this) : recipient, output
                    );
                }
                exchange = address(0); // reset exchange to fetch the next one in the next iteration
            }
        }
            // (address input, address output) = (path[0], path[1]);
            // if(input == Constants.ETH) {
            //     address payable exchange =IV1Factory(SUNSWAP_V1_FACTORY).getExchange(output);
            //     amountIn = address(this).balance;
            //     if(exchange == address(0)) revert V1InvalidExchange();
            //     amountOut = ISunswapExchange(exchange).trxToTokenTransferInput{value: amountIn}(
            //         1, block.timestamp + 1, recipient
            //     );
            // } else if(output == Constants.ETH) {
            //    address payable exchange =IV1Factory(SUNSWAP_V1_FACTORY).getExchange(input);
            //     if(exchange == address(0)) revert V1InvalidExchange(); 
            //     amountIn = ERC20(input).balanceOf(address(this));                   
            //     ERC20(input).safeApprove(exchange, amountIn);
            //     amountOut = ISunswapExchange(exchange).tokenToTrxTransferInput(
            //        amountIn, 1, block.timestamp + 1, recipient
            //     );
            // }
        // }
    }

    /// @notice Performs a SunSwap v2 exact input swap
    /// @param recipient The recipient of the output tokens
    /// @param amountIn The amount of input tokens for the trade
    /// @param amountOutMinimum The minimum desired amount of output tokens
    /// @param path The path of the trade as an array of token addresses
    /// @param payer The address that will be paying the input
    function v1SwapExactInput(
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address[] calldata path,
        address payer
    ) internal {
        if( amountIn != ActionConstants.CONTRACT_BALANCE && payer != address(this)){
            payOrPermit2Transfer(path[0], payer, address(this), amountIn);
        }else if (amountIn == ActionConstants.CONTRACT_BALANCE) {
            address tokenIn = path[0];
            if(tokenIn == Constants.ETH){
                amountIn = address(this).balance;
            } else {
                amountIn = ERC20(tokenIn).balanceOf(address(this));
            }
        }
        
        uint256 balanceBefore;
        uint256 amountOut;
        if(path[path.length - 1] == Constants.ETH) {
            balanceBefore = address(recipient).balance;
            _v1SwapExactIn(path, recipient, address(0),amountIn);
            amountOut = address(recipient).balance - balanceBefore;
        }else {
            ERC20 tokenOut = ERC20(path[path.length - 1]);
            balanceBefore = tokenOut.balanceOf(recipient);
            _v1SwapExactIn(path, recipient, address(0),amountIn);
            amountOut = tokenOut.balanceOf(recipient) - balanceBefore;
        }

        if (amountOut < amountOutMinimum) revert V1TooLittleReceived();
    }

    /// @notice Performs a SunSwap v2 exact output swap
    /// @param recipient The recipient of the output tokens
    /// @param amountOut The amount of output tokens to receive for the trade
    /// @param amountInMaximum The maximum desired amount of input tokens
    /// @param path The path of the trade as an array of token addresses
    /// @param payer The address that will be paying the input
    function v1SwapExactOutput(
        address recipient,
        uint256 amountOut,
        uint256 amountInMaximum,
        address[] calldata path,
        address payer
    ) internal {
        (uint256 amountIn, address firstPair) = UniversalRouterHelper.getAmountInMultihopV1(
            SUNSWAP_V1_FACTORY, path, amountOut
        );
        if (amountIn > amountInMaximum) revert V1TooMuchRequested();

        if(path[0] == Constants.ETH){
            if(address(this).balance < amountIn) revert V1TooMuchRequested();
        } else if(payer != address(this)){
            payOrPermit2Transfer(path[0], payer, address(this), amountIn);
        } else {
            if (ERC20(path[0]).balanceOf(address(this)) < amountIn) {
                revert V1TooMuchRequested();
            }
        }
        _v1SwapExactIn(path, recipient, firstPair,amountIn);
    }
}
