// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {V2SwapRouter} from "../modules/sunswap/v2/V2SwapRouter.sol";
import {V1SwapRouter} from "../modules/sunswap/v1/V1SwapRouter.sol";
import {V3SwapRouter} from "../modules/sunswap/v3/V3SwapRouter.sol";
import {HtxSunSwapRouter} from "../modules/sunswap/htxSun/HtxSunSwapRouter.sol";
import {PSMSwapRouter} from "../modules/sunswap/PSM/PSMSwapRouter.sol";
import {V4SwapRouter} from "../modules/sunswap/v4/V4SwapRouter.sol";
import {StableSwapRouter} from "../modules/sunswap/stableswap/StableSwapRouter.sol";
import {Payments} from "../modules/Payments.sol";
import {RouterImmutables} from "../base/RouterImmutables.sol";
import {V3ToV4Migrator} from "../modules/V3ToV4Migrator.sol";
import {BytesLib} from "../libraries/BytesLib.sol";
import {Commands} from "../libraries/Commands.sol";
import {Lock} from "./Lock.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {ActionConstants} from "v4-periphery/src/libraries/ActionConstants.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {BaseActionsRouter} from "v4-periphery/src/base/BaseActionsRouter.sol";
import {CalldataDecoder} from "v4-periphery/src/libraries/CalldataDecoder.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {ICLPoolManager} from "v4-core/src/interfaces/ICLPoolManager.sol";
import {UniversalRouterHelper} from "../libraries/UniversalRouterHelper.sol";
/// @title Decodes and Executes Commands
/// @notice Called by the UniversalRouter contract to efficiently decode and execute a singular command
abstract contract Dispatcher is
    Payments,
    V1SwapRouter,
    V2SwapRouter,
    V3SwapRouter,
    StableSwapRouter,
    PSMSwapRouter,
    HtxSunSwapRouter,
    V4SwapRouter,
    V3ToV4Migrator,
    Lock
{
    using BytesLib for bytes;
    using CalldataDecoder for bytes;

    bool public enableRecipientCheck;

    error InvalidCommandType(uint256 commandType);
    error BalanceTooLow();
    error RecipientErr();

    // /// @notice Executes encoded commands along with provided inputs.
    // /// @param commands A set of concatenated commands, each 1 byte in length
    // /// @param inputs An array of byte strings containing abi encoded inputs for each command
    // function execute(bytes calldata commands, bytes[] calldata inputs) external payable virtual;

    /// @notice Public view function to be used instead of msg.sender, as the contract performs self-reentrancy and at
    /// times msg.sender == address(this). Instead msgSender() returns the initiator of the lock
    function msgSender() public view override(BaseActionsRouter) returns (address) {
        return _getLocker();
    }

    function recipientCheck(address reciptient) internal view {
        if (enableRecipientCheck) {
            if (reciptient != address(this) && reciptient != msgSender()) revert RecipientErr();
        }
    }

    /// @notice Decodes and executes the given command with the given inputs
    /// @param commandType The command type to execute
    /// @param inputs The inputs to execute the command with
    /// @dev inputs must be ABI encoded using abi.encode() to ensure proper padding. WARNING: Direct calldata
    //       manipulation or abi.encodePacked() can result in incorrect data reads.
    /// @dev 2 masks are used to enable use of a nested-if statement in execution for efficiency reasons
    /// @return success True on success of the command, false on failure
    /// @return output The outputs or error messages, if any, from the command
    function dispatch(bytes1 commandType, bytes calldata inputs)
        internal
        returns (
            bool success,
            bytes memory output,
            address[] memory tokens
        )
    {
        uint256 command = uint8(commandType & Commands.COMMAND_TYPE_MASK);

        success = true;

        // 0x00 <= command < 0x21
        if (command < Commands.EXECUTE_SUB_PLAN) {
            // 0x00 <= command < 0x10
            if (command < Commands.V4_SWAP) {
                // 0x00 <= command < 0x08
                if (command < Commands.V2_SWAP_EXACT_IN) {
                    if (command == Commands.V3_SWAP_EXACT_IN) {
                        // equivalent: abi.decode(inputs, (address, uint256, uint256, bytes, bool))
                        address recipient;
                        uint256 amountIn;
                        uint256 amountOutMin;
                        bool payerIsUser;
                        assembly {
                            recipient := calldataload(inputs.offset)
                            amountIn := calldataload(add(inputs.offset, 0x20))
                            amountOutMin := calldataload(add(inputs.offset, 0x40))
                            // 0x60 offset is the path, decoded below
                            payerIsUser := calldataload(add(inputs.offset, 0x80))
                        }

                        bytes calldata path = inputs.toBytes(3);

                        tokens = UniversalRouterHelper.decodeV3Path(path);

                        address payer = payerIsUser ? msgSender() : address(this);
                        v3SwapExactInput(map(recipient), amountIn, amountOutMin, path, payer);
                        return (success, output, tokens);
                    } else if (command == Commands.V3_SWAP_EXACT_OUT) {
                        // equivalent: abi.decode(inputs, (address, uint256, uint256, bytes, bool))
                        address recipient;
                        uint256 amountOut;
                        uint256 amountInMax;
                        bool payerIsUser;
                        assembly {
                            recipient := calldataload(inputs.offset)
                            amountOut := calldataload(add(inputs.offset, 0x20))
                            amountInMax := calldataload(add(inputs.offset, 0x40))
                            // 0x60 offset is the path, decoded below
                            payerIsUser := calldataload(add(inputs.offset, 0x80))
                        }

                        bytes calldata path = inputs.toBytes(3);

                        tokens = UniversalRouterHelper.decodeV3Path(path);

                        address payer = payerIsUser ? msgSender() : address(this);
                        v3SwapExactOutput(map(recipient), amountOut, amountInMax, path, payer);
                        return (success, output, tokens);
                    } else if (command == Commands.PERMIT2_TRANSFER_FROM) {
                        // equivalent: abi.decode(inputs, (address, address, uint160))
                        address token;
                        address recipient;
                        uint160 amount;
                        assembly {
                            token := calldataload(inputs.offset)
                            recipient := calldataload(add(inputs.offset, 0x20))
                            amount := calldataload(add(inputs.offset, 0x40))
                        }

                        permit2TransferFrom(token, msgSender(), map(recipient), amount);
                        address[] memory single = new address[](1);
                        single[0] = token;
                        return (success, output, single);
                    } else if (command == Commands.PERMIT2_PERMIT_BATCH) {
                        IAllowanceTransfer.PermitBatch calldata permitBatch;
                        assembly {
                            // this is a variable length struct, so calldataload(inputs.offset) contains the
                            // offset from inputs.offset at which the struct begins
                            permitBatch := add(inputs.offset, calldataload(inputs.offset))
                        }
                        bytes calldata data = inputs.toBytes(1);
                        (success, output) = address(PERMIT2).call(
                            abi.encodeWithSignature(
                                "permit(address,((address,uint160,uint48,uint48)[],address,uint256),bytes)",
                                msgSender(),
                                permitBatch,
                                data
                            )
                        );
                        return (success, output, tokens);
                    } else if (command == Commands.SWEEP) {
                        // equivalent:  abi.decode(inputs, (address, address, uint256))
                        address token;
                        address recipient;
                        uint160 amountMin;
                        assembly {
                            token := calldataload(inputs.offset)
                            recipient := calldataload(add(inputs.offset, 0x20))
                            amountMin := calldataload(add(inputs.offset, 0x40))
                        }

                        Payments.sweep(token, map(recipient), amountMin);
                        return (success, output, tokens);
                    } else if (command == Commands.PAY_PORTION) {
                        // equivalent:  abi.decode(inputs, (address, address, uint256))
                        address token;
                        address recipient;
                        uint256 bips;
                        assembly {
                            token := calldataload(inputs.offset)
                            recipient := calldataload(add(inputs.offset, 0x20))
                            bips := calldataload(add(inputs.offset, 0x40))
                        }
                        Payments.payPortion(token, map(recipient), bips);
                        return (success, output, tokens);
                    } else {
                        // placeholder area for command 0x07
                        revert InvalidCommandType(command);
                    }
                } else {
                    // 0x08 <= command < 0x10
                    if (command == Commands.V2_SWAP_EXACT_IN) {
                        // equivalent: abi.decode(inputs, (address, uint256, uint256, bytes, bool))
                        address recipient;
                        uint256 amountIn;
                        uint256 amountOutMin;
                        bool payerIsUser;
                        assembly {
                            recipient := calldataload(inputs.offset)
                            amountIn := calldataload(add(inputs.offset, 0x20))
                            amountOutMin := calldataload(add(inputs.offset, 0x40))
                            // 0x60 offset is the path, decoded below
                            payerIsUser := calldataload(add(inputs.offset, 0x80))
                        }
                        address[] calldata path = inputs.toAddressArray(3);
                        tokens = copyToMemory(path);
                        address payer = payerIsUser ? msgSender() : address(this);
                        v2SwapExactInput(map(recipient), amountIn, amountOutMin, path, payer);
                        return (success, output, tokens);
                    } else if (command == Commands.V2_SWAP_EXACT_OUT) {
                        // equivalent: abi.decode(inputs, (address, uint256, uint256, bytes, bool))
                        address recipient;
                        uint256 amountOut;
                        uint256 amountInMax;
                        bool payerIsUser;
                        assembly {
                            recipient := calldataload(inputs.offset)
                            amountOut := calldataload(add(inputs.offset, 0x20))
                            amountInMax := calldataload(add(inputs.offset, 0x40))
                            // 0x60 offset is the path, decoded below
                            payerIsUser := calldataload(add(inputs.offset, 0x80))
                        }
                        address[] calldata path = inputs.toAddressArray(3);
                        tokens = copyToMemory(path);
                        address payer = payerIsUser ? msgSender() : address(this);
                        v2SwapExactOutput(map(recipient), amountOut, amountInMax, path, payer);
                        return (success, output, tokens);
                    } else if (command == Commands.PERMIT2_PERMIT) {
                        // equivalent: abi.decode(inputs, (IAllowanceTransfer.PermitSingle, bytes))
                        IAllowanceTransfer.PermitSingle calldata permitSingle;
                        assembly {
                            permitSingle := inputs.offset
                        }
                        bytes calldata data = inputs.toBytes(6); // PermitSingle takes first 6 slots (0..5)
                        (success, output) = address(PERMIT2).call(
                            abi.encodeWithSignature(
                                "permit(address,((address,uint160,uint48,uint48),address,uint256),bytes)",
                                msgSender(),
                                permitSingle,
                                data
                            )
                        );
                        return (success, output, tokens);
                    } else if (command == Commands.WRAP_ETH) {
                        // equivalent: abi.decode(inputs, (address, uint256))
                        address recipient;
                        uint256 amount;
                        assembly {
                            recipient := calldataload(inputs.offset)
                            amount := calldataload(add(inputs.offset, 0x20))
                        }
                        Payments.wrapETH(map(recipient), amount);

                        address[] memory single = new address[](1);
                        single[0] = address(0);
                        return (success, output, single);
                    } else if (command == Commands.UNWRAP_WETH) {
                        // equivalent: abi.decode(inputs, (address, uint256))
                        address recipient;
                        uint256 amountMin;
                        assembly {
                            recipient := calldataload(inputs.offset)
                            amountMin := calldataload(add(inputs.offset, 0x20))
                        }
                        Payments.unwrapWETH9(map(recipient), amountMin);
                        address[] memory single = new address[](1);
                        single[0] = address(WETH9);
                        return (success, output, single);
                    } else if (command == Commands.PERMIT2_TRANSFER_FROM_BATCH) {
                        IAllowanceTransfer.AllowanceTransferDetails[] calldata batchDetails;
                        (uint256 length, uint256 offset) = inputs.toLengthOffset(0);
                        assembly {
                            batchDetails.length := length
                            batchDetails.offset := offset
                        }
                        permit2TransferFrom(batchDetails, msgSender());
                        return (success, output, tokens);
                    } else if (command == Commands.BALANCE_CHECK_ERC20) {
                        // equivalent: abi.decode(inputs, (address, address, uint256))
                        address owner;
                        address token;
                        uint256 minBalance;
                        assembly {
                            owner := calldataload(inputs.offset)
                            token := calldataload(add(inputs.offset, 0x20))
                            minBalance := calldataload(add(inputs.offset, 0x40))
                        }
                        success = (ERC20(token).balanceOf(owner) >= minBalance);
                        if (!success) output = abi.encodePacked(BalanceTooLow.selector);
                        return (success, output, tokens);
                    } else if (command == Commands.V1_SWAP_EXACT_IN) {
                        address recipient;
                        uint256 amountIn;
                        uint256 amountOutMin;
                        bool payerIsUser;
                        assembly {
                            recipient := calldataload(inputs.offset)
                            amountIn := calldataload(add(inputs.offset, 0x20))
                            amountOutMin := calldataload(add(inputs.offset, 0x40))
                            // 0x60 offset is the path, decoded below
                            payerIsUser := calldataload(add(inputs.offset, 0x80))
                        }
                        address[] calldata path = inputs.toAddressArray(3);
                        tokens = copyToMemory(path);
                        address payer = payerIsUser ? msgSender() : address(this);
                        v1SwapExactInput(map(recipient), amountIn, amountOutMin, path, payer);
                        return (success, output, tokens);
                    } else if (command == Commands.V1_SWAP_EXACT_OUT) {
                        address recipient;
                        uint256 amountOut;
                        uint256 amountInMax;
                        bool payerIsUser;
                        assembly {
                            recipient := calldataload(inputs.offset)
                            amountOut := calldataload(add(inputs.offset, 0x20))
                            amountInMax := calldataload(add(inputs.offset, 0x40))
                            // 0x60 offset is the path, decoded below
                            payerIsUser := calldataload(add(inputs.offset, 0x80))
                        }
                        address[] calldata path = inputs.toAddressArray(3);
                        tokens = copyToMemory(path);
                        address payer = payerIsUser ? msgSender() : address(this);
                        v1SwapExactOutput(map(recipient), amountOut, amountInMax, path, payer);
                        return (success, output, tokens);
                    } else {
                        // placeholder area for command 0x0f
                        revert InvalidCommandType(command);
                    }
                }
            } else {
                // 0x10 <= command < 0x21
                if (command == Commands.V4_SWAP) {
                    // pass the calldata provided to V4SwapRouter._executeActions (defined in BaseActionsRouter)
                    _executeActions(inputs);
                    tokens = UniversalRouterHelper.decodeV4Actions(inputs);
                    return (success, output, tokens);
                    // This contract MUST be approved to spend the token since its going to be doing the call on the position manager
                } else {
                    // placeholder area for commands 0x15-0x20
                    revert InvalidCommandType(command);
                }
            }
        } else {
            // 0x21 <= command
            if (command == Commands.EXECUTE_SUB_PLAN) {
                revert InvalidCommandType(command);
            } else if (command == Commands.STABLE_SWAP_EXACT_IN) {
                // equivalent: abi.decode(inputs, (address, uint256, uint256, bytes, bytes, bool))
                address recipient;
                uint256 amountIn;
                uint256 amountOutMin;
                bool payerIsUser;
                assembly {
                    recipient := calldataload(inputs.offset)
                    amountIn := calldataload(add(inputs.offset, 0x20))
                    amountOutMin := calldataload(add(inputs.offset, 0x40))
                    // 0x60 offset is the path and 0x80 is the flag, decoded below
                    payerIsUser := calldataload(add(inputs.offset, 0xa0))
                }
                address[] calldata path = inputs.toAddressArray(3);
                tokens = copyToMemory(path);
                uint256[] calldata flag = inputs.toUintArray(4);
                address payer = payerIsUser ? msgSender() : address(this);
                stableSwapExactInput(map(recipient), amountIn, amountOutMin, path, flag, payer);
                return (success, output, tokens);
            } else if (command == Commands.PSM_SWAP_EXACT_IN) {
                // equivalent: abi.decode(inputs, (address, uint256, uint256, bytes, bytes, bool))
                address recipient;
                uint256 amountIn;
                uint256 amountOutMin;
                bool payerIsUser;
                assembly {
                    recipient := calldataload(inputs.offset)
                    amountIn := calldataload(add(inputs.offset, 0x20))
                    amountOutMin := calldataload(add(inputs.offset, 0x40))
                    // 0x60 offset is the path and 0x80 is the flag,
                    payerIsUser := calldataload(add(inputs.offset, 0xa0))
                }
                address[] calldata path = inputs.toAddressArray(3);
                tokens = copyToMemory(path);
                uint256[] calldata flag = inputs.toUintArray(4);
                address payer = payerIsUser ? msgSender() : address(this);
                psmSwapExactInput(map(recipient), amountIn, amountOutMin, path, flag, payer);
                return (success, output, tokens);
            } else if (command == Commands.PSM_SWAP_EXACT_OUT) {
                // equivalent: abi.decode(inputs, (address, uint256, uint256, bytes, bytes, bool))
                address recipient;
                uint256 amountOut;
                uint256 amountInMax;
                bool payerIsUser;
                assembly {
                    recipient := calldataload(inputs.offset)
                    amountOut := calldataload(add(inputs.offset, 0x20))
                    amountInMax := calldataload(add(inputs.offset, 0x40))
                    // 0x60 offset is the path and 0x80 is the flag,
                    payerIsUser := calldataload(add(inputs.offset, 0xa0))
                }
                address[] calldata path = inputs.toAddressArray(3);
                tokens = copyToMemory(path);
                uint256[] calldata flag = inputs.toUintArray(4);
                address payer = payerIsUser ? msgSender() : address(this);
                psmSwapExactOutput(map(recipient), amountOut, amountInMax, path, flag, payer);
                return (success, output, tokens);
            } else if (command == Commands.HTX_SUN_SWAP_IN) {
                // equivalent: abi.decode(inputs, (address, uint256, bool))
                address recipient;
                uint256 amountIn;
                uint256 amountOutMin;
                bool payerIsUser;
                assembly {
                    recipient := calldataload(inputs.offset)
                    amountIn := calldataload(add(inputs.offset, 0x20))
                    amountOutMin := calldataload(add(inputs.offset, 0x40))
                    // 0x60 offset is the path and 0x80 is the flag,
                    payerIsUser := calldataload(add(inputs.offset, 0xa0))
                }
                address[] calldata path = inputs.toAddressArray(3);
                tokens = copyToMemory(path);
                uint256[] calldata flag = inputs.toUintArray(4);
                address payer = payerIsUser ? msgSender() : address(this);
                htxSunSwapExactInput(map(recipient), amountIn, amountOutMin, path, flag, payer);
                return (success, output, tokens);
            } else if (command == Commands.HTX_SUN_SWAP_OUT) {
                // equivalent: abi.decode(inputs, (address, uint256, bool))
                address recipient;
                uint256 amountOut;
                uint256 amountInMax;
                bool payerIsUser;
                assembly {
                    recipient := calldataload(inputs.offset)
                    amountOut := calldataload(add(inputs.offset, 0x20))
                    amountInMax := calldataload(add(inputs.offset, 0x40))
                    // 0x60 offset is the path and 0x80 is the flag,
                    payerIsUser := calldataload(add(inputs.offset, 0xa0))
                }
                address[] calldata path = inputs.toAddressArray(3);
                tokens = copyToMemory(path);
                uint256[] calldata flag = inputs.toUintArray(4);
                address payer = payerIsUser ? msgSender() : address(this);
                htxSunSwapExactOutput(map(recipient), amountOut, amountInMax, path, flag, payer);
                return (success, output, tokens);
            } else {
                // placeholder area for commands 0x24-0x3f
                revert InvalidCommandType(command);
            }
        }
    }

    /// @notice Calculates the recipient address for a command
    /// @param recipient The recipient or recipient-flag for the command
    /// @return output The resultant recipient for the command
    function map(address recipient) internal view returns (address) {
        if (recipient == ActionConstants.MSG_SENDER) {
            return msgSender();
        } else if (recipient == ActionConstants.ADDRESS_THIS) {
            return address(this);
        } else {
            recipientCheck(recipient);
            return recipient;
        }
    }

    function copyToMemory(address[] calldata input) internal view returns (address[] memory result) {
        result = new address[](input.length);
        for (uint256 i = 0; i < input.length; i++) {
            result[i] = input[i];
        }
    }
}
