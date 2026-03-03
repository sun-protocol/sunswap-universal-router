// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2025 SunSwap
pragma solidity ^0.8.0;

import {ActionConstants} from "v4-periphery/src/libraries/ActionConstants.sol";
import {RouterImmutables} from "../../../base/RouterImmutables.sol";
import {Payments} from "../../Payments.sol";
import {Permit2Payments} from "../../Permit2Payments.sol";
import {Constants} from "../../../libraries/Constants.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IStableSwap} from "../../../interfaces/IStableSwap.sol";
import {IStableSwapFactory} from "../../../interfaces/IStableSwapFactory.sol";
import {SwapFlags} from "../../../libraries/SwapFlags.sol";

/// @title Router for S画丶Swap Stable Trades
abstract contract StableSwapRouter is RouterImmutables, Permit2Payments, Ownable2Step {
    using SafeTransferLib for ERC20;

    error StableTooLittleReceived();
    error StableTooMuchRequested();
    error StableInvalidPath();

    address public stableSwapFactory;

    event SetStableSwap(address indexed factory);

    constructor(address _stableSwapFactory) Ownable(msg.sender) {
        stableSwapFactory = _stableSwapFactory;
    }

    /**
     * @notice Set Sun Stable Swap Factory and Info
     * @dev Only callable by contract owner
     */
    function setStableSwap(address _factory) external onlyOwner {
        require(_factory != address(0), "Invalid factory address");

        stableSwapFactory = _factory;

        emit SetStableSwap(stableSwapFactory);
    }

    function _stableSwap(
        address[] calldata path,
        uint256[] calldata flag,
        uint256 fristAmountIn
    ) private {
        unchecked {
            if (path.length - 1 != flag.length) revert StableInvalidPath();

            for (uint256 i; i < flag.length; i++) {
                (address input, address output) = (path[i], path[i + 1]);
                (uint256 k, uint256 j, address swapContract, ) = IStableSwapFactory(stableSwapFactory).getStableInfo(
                    input,
                    output,
                    flag[i]
                );
                uint256 amountIn;
                if (i == 0 && fristAmountIn > 0) {
                    amountIn = fristAmountIn;
                } else {
                    amountIn = ERC20(input).balanceOf(address(this));
                }
                if (amountIn == 0) revert StableInvalidPath();
                ERC20(input).safeApprove(swapContract, amountIn);
                if (ERC20(input).allowance(address(this), swapContract) < amountIn) revert StableInvalidPath();
                if (SwapFlags.isMetaPool(flag[i])) {
                    IStableSwap(swapContract).exchange_underlying(int128(uint128(k)), int128(uint128(j)), amountIn, 0);
                } else if (SwapFlags.isBasePool(flag[i])) {
                    IStableSwap(swapContract).exchange(uint128(k), uint128(j), amountIn, 0);
                } else {
                    revert StableInvalidPath();
                }
            }
        }
    }

    /// @notice Performs a SunSwap stable exact input swap
    /// @param recipient The recipient of the output tokens
    /// @param amountIn The amount of input tokens for the trade
    /// @param amountOutMinimum The minimum desired amount of output tokens
    /// @param path The path of the trade as an array of token addresses
    /// @param flag token amount in a stable swap pool. 2 for 2pool, 3 for 3pool
    /// @param payer The address that will be paying the input
    function stableSwapExactInput(
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address[] calldata path,
        uint256[] calldata flag,
        address payer
    ) internal {
        if (amountIn != ActionConstants.CONTRACT_BALANCE && payer != address(this)) {
            payOrPermit2Transfer(path[0], payer, address(this), amountIn);
        } else if (amountIn == ActionConstants.CONTRACT_BALANCE) {
            address tokenIn = path[0];
            amountIn = ERC20(tokenIn).balanceOf(address(this));
        }

        ERC20 tokenOut = ERC20(path[path.length - 1]);
        uint256 balanceBefore = tokenOut.balanceOf(address(this));

        _stableSwap(path, flag, amountIn);

        uint256 amountOut = tokenOut.balanceOf(address(this)) - balanceBefore;
        if (amountOut < amountOutMinimum) revert StableTooLittleReceived();

        if (recipient != address(this)) pay(address(tokenOut), recipient, amountOut);
    }
}
