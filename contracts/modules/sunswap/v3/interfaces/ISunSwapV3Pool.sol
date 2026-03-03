// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./pool/ISunSwapV3PoolImmutables.sol";
import "./pool/ISunSwapV3PoolState.sol";
import "./pool/ISunSwapV3PoolDerivedState.sol";
import "./pool/ISunSwapV3PoolActions.sol";
import "./pool/ISunSwapV3PoolOwnerActions.sol";
import "./pool/ISunSwapV3PoolEvents.sol";

/// @title The interface for a SunSwap V3 Pool
/// @notice A SunSwap pool facilitates swapping and automated market making between any two assets that strictly conform
/// to the ERC20 specification
/// @dev The pool interface is broken up into many smaller pieces
interface ISunSwapV3Pool is
    ISunSwapV3PoolImmutables,
    ISunSwapV3PoolState,
    ISunSwapV3PoolDerivedState,
    ISunSwapV3PoolActions,
    ISunSwapV3PoolOwnerActions,
    ISunSwapV3PoolEvents
{}
