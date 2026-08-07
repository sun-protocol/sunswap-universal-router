// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IV3NonfungiblePositionManager} from "v4-periphery/src/interfaces/external/IV3NonfungiblePositionManager.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";

struct RouterParameters {
    // Payment parameters
    address permit2;
    address weth9;
    // SunSwap swapping parameters
    address v1Factory;
    address v2Factory;
    address v3Factory;
    address v3Deployer;
    bytes32 v2InitCodeHash;
    bytes32 v3InitCodeHash;
    address stableFactory;
    // address stableInfo;
    // SunSwap v4 swapping parameters, param not in this contract as stored in V4SwapRouter
    address v4Vault;
    address v4ClPoolManager;
    // SunSwap v3->v4 migration parameters
    address v3NFTPositionManager;
    address v4ClPositionManager;
    address safeVault;
}

/// @title Router Immutable Storage contract
/// @notice Used along with the `RouterParameters` struct for ease of cross-chain deployment
contract RouterImmutables {
    /// @dev WETH9 address
    IWETH9 internal immutable WETH9;

    /// @dev Permit2 address
    IPermit2 internal immutable PERMIT2;

    /// @dev The address of SunSwapV2Factory
    address internal immutable SUNSWAP_V2_FACTORY;

    /// @dev The SunSwapV2Pair initcodehash
    bytes32 internal immutable SUNSWAP_V2_PAIR_INIT_CODE_HASH;

    /// @dev The address of SunSwapV1Factory
    address internal immutable SUNSWAP_V1_FACTORY;

    ///
    /// @dev The address of SunSwapV3Factory
    address internal immutable SUNSWAP_V3_FACTORY;

    /// @dev The SunSwapV3Pool initcodehash
    bytes32 internal immutable SUNSWAP_V3_POOL_INIT_CODE_HASH;

    /// @dev The address of SunSwap V3 Deployer
    address internal immutable SUNSWAP_V3_DEPLOYER;

    /// @dev v3PositionManager address
    IV3NonfungiblePositionManager public immutable V3_POSITION_MANAGER;

    /// @dev V4 CLPositionManager address
    IPositionManager public immutable V4_CL_POSITION_MANAGER;

    constructor(RouterParameters memory params) {
        PERMIT2 = IPermit2(params.permit2);
        WETH9 = IWETH9(params.weth9);
        SUNSWAP_V1_FACTORY = params.v1Factory;
        SUNSWAP_V2_FACTORY = params.v2Factory;
        SUNSWAP_V2_PAIR_INIT_CODE_HASH = params.v2InitCodeHash;
        SUNSWAP_V3_FACTORY = params.v3Factory;
        SUNSWAP_V3_POOL_INIT_CODE_HASH = params.v3InitCodeHash;
        SUNSWAP_V3_DEPLOYER = params.v3Deployer;
        V3_POSITION_MANAGER = IV3NonfungiblePositionManager(params.v3NFTPositionManager);
        V4_CL_POSITION_MANAGER = IPositionManager(params.v4ClPositionManager);
    }
}
