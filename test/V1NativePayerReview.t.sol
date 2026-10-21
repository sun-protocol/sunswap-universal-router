// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {V1ExactOutputTest, V1OutputHarness, V1OutputPermit2} from "./V1ExactOutput.t.sol";
import {RouterParameters} from "src/base/RouterImmutables.sol";
import {MockERC20} from "./mock/MockERC20.sol";

contract V1NativeReviewHarness is V1OutputHarness {
    constructor(RouterParameters memory params) V1OutputHarness(params) {}

    function nativeInput(address recipient, address[] calldata route, address payer) external payable {
        v1SwapExactInput(recipient, msg.value, 1, route, payer);
    }
}

contract V1NativeReviewExchange {
    MockERC20 immutable token;

    constructor(MockERC20 token_) { token = token_; }

    function trxToTokenTransferInput(uint256 minimum, uint256 deadline, address recipient)
        external payable returns (uint256)
    {
        require(block.timestamp <= deadline && msg.value >= minimum);
        token.mint(recipient, msg.value);
        return msg.value;
    }
}

contract V1NativePayerReviewTest is V1ExactOutputTest {
    V1NativeReviewHarness nativeRouter;

    function prepareNativeRouter() internal {
        RouterParameters memory params;
        params.v1Factory = address(factory);
        params.permit2 = address(permit2);
        nativeRouter = new V1NativeReviewHarness(params);
        factory.set(address(b), payable(address(new V1NativeReviewExchange(b))));
    }

    function test_reviewNativeUserPayerCallsPermit2AndRevertsDespiteValue() public {
        prepareNativeRouter();
        vm.expectCall(address(permit2), abi.encodeCall(
            V1OutputPermit2.transferFrom, (address(this), address(nativeRouter), uint160(1000), address(0))
        ));
        vm.expectRevert();
        nativeRouter.nativeInput{value: 1000}(recipient, path(address(0), address(b)), address(this));
        assertEq(b.balanceOf(recipient), 0);
        assertEq(address(nativeRouter).balance, 0);
    }

    function test_reviewNativeRouterPayerSucceedsWithSameValue() public {
        prepareNativeRouter();
        nativeRouter.nativeInput{value: 1000}(recipient, path(address(0), address(b)), address(nativeRouter));
        assertEq(b.balanceOf(recipient), 1000);
        assertEq(address(nativeRouter).balance, 0);
    }
}
