// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2025 SunSwap
pragma solidity ^0.8.24;

import {Constants} from "../libraries/Constants.sol";
import {ActionConstants} from "v4-periphery/src/libraries/ActionConstants.sol";
import {BipsLibrary} from "v4-periphery/src/libraries/BipsLibrary.sol";
import {RouterImmutables} from "../base/RouterImmutables.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ERC721} from "solmate/src/tokens/ERC721.sol";
import {ERC1155} from "solmate/src/tokens/ERC1155.sol";
import {IReferralVault} from "../interfaces/IReferralVault.sol";

/// @title Payments contract
/// @notice Performs various operations around the payment of ETH and tokens
abstract contract Payments is RouterImmutables {
    // using SafeTransferLib for ERC20;
    // using SafeTransferLib for address;
    using BipsLibrary for uint256;

    error InsufficientToken();
    error InsufficientETH();

    /// @notice Pays an amount of ETH or ERC20 to a recipient
    /// @param token The token to pay (can be ETH using Constants.ETH)
    /// @param recipient The address that will receive the payment
    /// @param value The amount to pay
    function pay(address token, address recipient, uint256 value) internal {
        if (token == Constants.ETH) {
            // recipient.safeTransferETH(value);
            require(SafeTransferLib.safeTransferETH(recipient, value), "TransferHelper: ETH_TRANSFER_FAILED");
        } else {
            if (value == ActionConstants.CONTRACT_BALANCE) {
                value = ERC20(token).balanceOf(address(this));
            }

            // ERC20(token).safeTransfer(recipient, value);
            require(SafeTransferLib.safeTransfer(token, recipient, value),"TransferHelper: TRANSFER_FAILED");
        }
    }

    /// @notice Pays a proportion of the contract's ETH or ERC20 to a recipient
    /// @param token The token to pay (can be ETH using Constants.ETH)
    /// @param recipient The address that will receive payment
    /// @param bips Portion in bips of whole balance of the contract
    function payPortion(address token, address recipient, uint256 bips) internal {
        if (token == Constants.ETH) {
            uint256 balance = address(this).balance;
            uint256 amount = balance.calculatePortion(bips);
            // recipient.safeTransferETH(amount);
            require(SafeTransferLib.safeTransferETH(recipient, amount), "TransferHelper: ETH_TRANSFER_FAILED");
        } else {
            uint256 balance = ERC20(token).balanceOf(address(this));
            uint256 amount = balance.calculatePortion(bips);
            // ERC20(token).safeTransfer(recipient, amount);
            require(SafeTransferLib.safeTransfer(token, recipient, amount),"TransferHelper: TRANSFER_FAILED");
        }
    }



    /// @notice Pushes a bips-portion of this contract's `token` balance into the referral
    ///         vault and books the rebate accrual.
    /// @dev    The body is a strict 3-step ritual that the vault relies on for correct
    ///         donation isolation:
    ///           1. `updateLastTokenBalance` — snapshots vault.balance(token) BEFORE inflow,
    ///              so any pre-existing vault balance (donations / residuals) is excluded
    ///              from this round's delta.
    ///           2. `payPortion`              — moves bips% of router's current balance into
    ///              the vault. This is the only step that can reenter (via the user-supplied
    ///              `token` contract); the vault's `updateLastTokenBalance` is `onlyRouter`,
    ///              so a malicious token cannot shift the snapshot mid-transfer.
    ///           3. `allocateReferral`        — vault recomputes a fresh snapshot, derives
    ///              delta = current - lastTokenBalance == this round's payPortion only, and
    ///              splits per current bips between the rebate recipient and protocol.
    ///         All three calls MUST stay in this order; see ReferralVault.allocateReferral
    ///         for the corresponding vault-side invariant.
    function payReferral(
        address token,
        address rebateRecipient,
        uint256 bips,
        address referralVault
    ) internal {
        require(bips <= IReferralVault(referralVault).maxReferralBips(), "Bips exceeds maxReferralBips");
        IReferralVault(referralVault).updateLastTokenBalance(token);
        payPortion(token, referralVault, bips);
        IReferralVault(referralVault).allocateReferral(token, rebateRecipient);
    }

    /// @notice Sweeps all of the contract's ERC20 or ETH to an address
    /// @param token The token to sweep (can be ETH using Constants.ETH)
    /// @param recipient The address that will receive payment
    /// @param amountMinimum The minimum desired amount
    function sweep(address token, address recipient, uint256 amountMinimum) internal {
        uint256 balance;
        if (token == Constants.ETH) {
            balance = address(this).balance;
            if (balance < amountMinimum) revert InsufficientETH();
            if (balance > 0) require(SafeTransferLib.safeTransferETH(recipient, balance), "TransferHelper: ETH_TRANSFER_FAILED");
            // recipient.safeTransferETH(balance);
        } else {
            balance = ERC20(token).balanceOf(address(this));
            if (balance < amountMinimum) revert InsufficientToken();
            if (balance > 0)  require(SafeTransferLib.safeTransfer(token, recipient, balance),"TransferHelper: TRANSFER_FAILED");
            // ERC20(token).safeTransfer(recipient, balance);
        }
    }

    /// @notice Wraps an amount of ETH into WETH
    /// @param recipient The recipient of the WETH
    /// @param amount The amount to wrap (can be CONTRACT_BALANCE)
    function wrapETH(address recipient, uint256 amount) internal {
        if (amount == ActionConstants.CONTRACT_BALANCE) {
            amount = address(this).balance;
        } else if (amount > address(this).balance) {
            revert InsufficientETH();
        }
        if (amount > 0) {
            WETH9.deposit{value: amount}();
            if (recipient != address(this)) {
                WETH9.transfer(recipient, amount);
            }
        }
    }

    /// @notice Unwraps all of the contract's WETH into ETH
    /// @param recipient The recipient of the ETH
    /// @param amountMinimum The minimum amount of ETH desired
    function unwrapWETH9(address recipient, uint256 amountMinimum) internal {
        uint256 value = WETH9.balanceOf(address(this));
        if (value < amountMinimum) {
            revert InsufficientETH();
        }
        if (value > 0) {
            WETH9.withdraw(value);
            if (recipient != address(this)) {
                require(SafeTransferLib.safeTransferETH(recipient, value), "TransferHelper: ETH_TRANSFER_FAILED");
                // recipient.safeTransferETH(value);
            }
        }
    }
}
