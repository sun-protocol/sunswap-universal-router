// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {PSMExactOutputTest} from "./PSMExactOutput.t.sol";
import {PSMSwapRouter} from "src/modules/sunswap/PSM/PSMSwapRouter.sol";

contract PSMReviewTest is PSMExactOutputTest {
    function roundTrip() internal view returns (address[] memory path) {
        path = new address[](3);
        path[0] = address(gem);
        path[1] = address(usdd);
        path[2] = address(gem);
    }

    function test_roundTripRejectedWithZeroMinimum() public {
        vm.expectRevert(PSMSwapRouter.PSMInvalidPath.selector);
        router.swapInput(recipient, 10, 0, roundTrip(), new uint256[](2));
        assertEq(gem.balanceOf(recipient), 0);
        assertEq(gem.balanceOf(address(router)), 100);
        assertEq(gem.balanceOf(address(pool)), 0);
    }

    function test_roundTripRejectedWithPositiveMinimum() public {
        vm.expectRevert(PSMSwapRouter.PSMInvalidPath.selector);
        router.swapInput(recipient, 10, 10, roundTrip(), new uint256[](2));
        assertEq(gem.balanceOf(address(router)), 100);
        assertEq(gem.balanceOf(recipient), 0);
    }
}
