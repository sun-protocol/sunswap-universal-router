// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

import {TokenFixture} from "v4-periphery/test/helpers/TokenFixture.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {Plan, Planner} from "v4-periphery/src/libraries/Planner.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {ActionConstants} from "v4-periphery/src/libraries/ActionConstants.sol";

abstract contract BaseSunSwapV4 is TokenFixture, Test, DeployPermit2 {
    using Planner for Plan;

    function _approvePermit2ForCurrency(address from, Currency currency, address to, IAllowanceTransfer permit2)
        internal
    {
        vm.startPrank(from);

        // 1. First, the caller must approve permit2 on the token.
        IERC20(Currency.unwrap(currency)).approve(address(permit2), type(uint256).max);

        // 2. Then, the caller must approve POSM as a spender of permit2.
        permit2.approve(Currency.unwrap(currency), to, type(uint160).max, type(uint48).max);

        vm.stopPrank();
    }

    /// @dev Replacement for Planner.finalizeSwap that encodes TAKE_ALL / TAKE
    ///      with the recipient address required by V4Router._handleAction.
    function _finalizeSwap(
        Plan memory plan,
        Currency inputCurrency,
        Currency outputCurrency,
        address takeRecipient
    ) internal pure returns (bytes memory) {
        if (takeRecipient == ActionConstants.MSG_SENDER) {
            plan = plan.add(Actions.SETTLE_ALL, abi.encode(inputCurrency, type(uint256).max));
            plan = plan.add(Actions.TAKE_ALL, abi.encode(outputCurrency, takeRecipient, uint256(0)));
        } else {
            plan = plan.add(Actions.SETTLE, abi.encode(inputCurrency, ActionConstants.OPEN_DELTA, true));
            plan = plan.add(Actions.TAKE, abi.encode(outputCurrency, takeRecipient, ActionConstants.OPEN_DELTA));
        }
        return plan.encode();
    }
}
