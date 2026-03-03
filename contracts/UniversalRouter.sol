// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2025 SunSwap
pragma solidity ^0.8.24;

// Command implementations
import {Dispatcher} from "./base/Dispatcher.sol";
import {RouterParameters, RouterImmutables} from "./base/RouterImmutables.sol";
import {V4SwapRouter} from "./modules/sunswap/v4/V4SwapRouter.sol";
import {Commands} from "./libraries/Commands.sol";
import {Constants} from "./libraries/Constants.sol";
import {IUniversalRouter} from "./interfaces/IUniversalRouter.sol";
import {StableSwapRouter} from "./modules/sunswap/stableswap/StableSwapRouter.sol";
import {HtxSunSwapRouter} from "./modules/sunswap/htxSun/HtxSunSwapRouter.sol";
import {PSMSwapRouter} from "./modules/sunswap/PSM/PSMSwapRouter.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ActionConstants} from "v4-periphery/src/libraries/ActionConstants.sol";

contract UniversalRouter is RouterImmutables, IUniversalRouter, Dispatcher, Pausable {
    address public safeVault;
    error InvalidSafeVault();

    constructor(RouterParameters memory params)
        RouterImmutables(params)
        StableSwapRouter(params.stableFactory)
        V4SwapRouter(params.v4Vault, params.v4ClPoolManager)
        PSMSwapRouter(params.stableFactory)
        HtxSunSwapRouter(params.stableFactory)
    {
        safeVault = params.safeVault;
    }

    modifier checkDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert TransactionDeadlinePassed();
        _;
    }

    /// @notice To receive ETH from WETH
    receive() external payable {}

    /// @inheritdoc IUniversalRouter
    function execute(
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 deadline
    ) external payable checkDeadline(deadline) {
        executeCommands(commands, inputs);
    }

    function executeCommands(bytes calldata commands, bytes[] calldata inputs) internal isNotLocked whenNotPaused {
        bool success;
        bytes memory output;
        address[] memory tokens;
        uint256 numCommands = commands.length;
        if (inputs.length != numCommands) revert LengthMismatch();
        address[] memory allTokens;
        // loop through all given commands, execute them and pass along outputs as defined
        for (uint256 commandIndex = 0; commandIndex < numCommands; commandIndex++) {
            bytes1 command = commands[commandIndex];

            bytes calldata input = inputs[commandIndex];

            (success, output, tokens) = dispatch(command, input);

            if (!success && successRequired(command)) {
                revert ExecutionFailed({commandIndex: commandIndex, message: output});
            }
            allTokens = concat(allTokens, tokens);
        }
        if (allTokens.length != 0) {
            for (uint256 i = 0; i < allTokens.length; i++) {
                sweep(allTokens[i], safeVault, 0);
            }
        }
    }

    function successRequired(bytes1 command) internal pure returns (bool) {
        return command & Commands.FLAG_ALLOW_REVERT == 0;
    }

    /**
     * @dev called by the owner to pause, triggers stopped state
     */
    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    /**
     * @dev called by the owner to unpause, returns to normal state
     */
    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    function setEnableRecipientCheck(bool isEnable) external onlyOwner {
        enableRecipientCheck = isEnable;
    }

    function setSafeVault(address _safeVault) external onlyOwner {
        if (_safeVault == address(0)) revert InvalidSafeVault();
        safeVault = _safeVault;
    }

    function concat(address[] memory a, address[] memory b) internal pure returns (address[] memory result) {
        result = new address[](a.length + b.length);

        for (uint256 i = 0; i < a.length; i++) {
            result[i] = a[i];
        }
        for (uint256 j = 0; j < b.length; j++) {
            result[a.length + j] = b[j];
        }
    }
}
