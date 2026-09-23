// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {V1SwapRouter} from "src/modules/sunswap/v1/V1SwapRouter.sol";
import {RouterParameters} from "src/base/RouterImmutables.sol";
import {V1OutputHarness, V1OutputFactory} from "./V1ExactOutput.t.sol";
import {MockERC20} from "./mock/MockERC20.sol";

contract V1InputHarness is V1OutputHarness {
    constructor(RouterParameters memory params) V1OutputHarness(params) {}

    function swapInput(address recipient, uint256 input, uint256 minimum, address[] calldata path) external {
        v1SwapExactInput(recipient, input, minimum, path, address(this));
    }
}

// Deterministic rates keep the regression focused on amount propagation and custody.
contract V1InputExchange {
    MockERC20 token;
    uint256 public lastInput;

    constructor(MockERC20 token_) { token = token_; }

    function tokenToTrxTransferInput(uint256 input, uint256, uint256, address recipient)
        external returns (uint256 output)
    {
        lastInput = input;
        token.transferFrom(msg.sender, address(this), input);
        output = input / 2;
        (bool ok,) = recipient.call{value: output}("");
        require(ok);
    }

    function trxToTokenTransferInput(uint256, uint256, address recipient)
        external payable returns (uint256 output)
    {
        lastInput = msg.value;
        output = msg.value * 3;
        token.mint(recipient, output);
    }

    function tokenToTokenTransferInput(uint256 input, uint256, uint256, uint256, address recipient, address outToken)
        external returns (uint256 output)
    {
        lastInput = input;
        token.transferFrom(msg.sender, address(this), input);
        output = input * 4;
        MockERC20(outToken).mint(recipient, output);
    }
}

contract V1ExactInputTest is Test {
    MockERC20 a;
    MockERC20 b;
    V1InputExchange poolA;
    V1InputExchange poolB;
    V1InputHarness router;
    address recipient = address(0xBEEF);

    function setUp() public {
        a = new MockERC20();
        b = new MockERC20();
        V1OutputFactory factory = new V1OutputFactory();
        poolA = new V1InputExchange(a);
        poolB = new V1InputExchange(b);
        factory.set(address(a), payable(address(poolA)));
        factory.set(address(b), payable(address(poolB)));
        RouterParameters memory params;
        params.v1Factory = address(factory);
        router = new V1InputHarness(params);
        a.mint(address(router), 10);
        vm.deal(address(poolA), 100);
    }

    function route(address input, address output) internal pure returns (address[] memory result) {
        result = new address[](2);
        result[0] = input;
        result[1] = output;
    }

    function test_tokenToNative() public {
        router.swapInput(recipient, 10, 5, route(address(a), address(0)));
        assertEq(poolA.lastInput(), 10);
        assertEq(recipient.balance, 5);
        assertEq(a.balanceOf(address(router)), 0);
        assertEq(a.allowance(address(router), address(poolA)), 0);
    }

    function test_nativeToToken() public {
        vm.deal(address(router), 5);
        router.swapInput(recipient, 5, 15, route(address(0), address(b)));
        assertEq(poolB.lastInput(), 5);
        assertEq(b.balanceOf(recipient), 15);
        assertEq(address(router).balance, 0);
    }

    function test_tokenToTokenPreservesUnrelatedBalances() public {
        vm.deal(address(router), 100);
        b.mint(address(router), 200);
        router.swapInput(recipient, 10, 40, route(address(a), address(b)));
        assertEq(poolA.lastInput(), 10);
        assertEq(b.balanceOf(recipient), 40);
        assertEq(a.balanceOf(address(router)), 0);
        assertEq(a.allowance(address(router), address(poolA)), 0);
        assertEq(address(router).balance, 100);
        assertEq(b.balanceOf(address(router)), 200);
    }

    function test_minimumOutputStillEnforced() public {
        vm.expectRevert(V1SwapRouter.V1TooLittleReceived.selector);
        router.swapInput(recipient, 10, 41, route(address(a), address(b)));
        assertEq(a.balanceOf(address(router)), 10);
        assertEq(b.balanceOf(recipient), 0);
    }

    function test_nativeMinimumOutputStillEnforced() public {
        vm.expectRevert(V1SwapRouter.V1TooLittleReceived.selector);
        router.swapInput(recipient, 10, 6, route(address(a), address(0)));
        assertEq(a.balanceOf(address(router)), 10);
        assertEq(recipient.balance, 0);
    }
}
