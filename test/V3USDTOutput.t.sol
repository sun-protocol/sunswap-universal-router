// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {V3SwapRouter} from "src/modules/sunswap/v3/V3SwapRouter.sol";
import {RouterImmutables, RouterParameters} from "src/base/RouterImmutables.sol";
import {UniversalRouterHelper} from "src/libraries/UniversalRouterHelper.sol";
import {V3USDTInputAmount} from "src/libraries/V3USDTInputAmount.sol";
import {CalldataDecoder} from "v4-periphery/src/libraries/CalldataDecoder.sol";
import {UniversalRouter} from "src/UniversalRouter.sol";
import {Commands} from "src/libraries/Commands.sol";
import {MaxInputAmount} from "src/libraries/MaxInputAmount.sol";
import {ActionConstants} from "v4-periphery/src/libraries/ActionConstants.sol";

contract V3OutputToken {
    mapping(address => uint256) public balanceOf;

    function mint(address recipient, uint256 amount) external {
        balanceOf[recipient] += amount;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }
}

contract V3OutputPoolMock {
    using CalldataDecoder for bytes;
    using UniversalRouterHelper for bytes;

    address internal immutable outputToken;
    uint256 internal immutable outputAmount;
    bool internal immutable transferOutput;
    uint256 public exactOutputInput;
    uint256 public shortfall;
    uint256 public reportedShortfall;

    constructor(address outputToken_, uint256 outputAmount_, bool transferOutput_) {
        outputToken = outputToken_;
        outputAmount = outputAmount_;
        transferOutput = transferOutput_;
    }

    function setExactOutputInput(uint256 amount) external {
        exactOutputInput = amount;
    }

    function setShortfall(uint256 amount) external {
        shortfall = amount;
    }

    function setReportedShortfall(uint256 amount) external {
        reportedShortfall = amount;
    }

    function swap(address recipient, bool zeroForOne, int256 amountSpecified, uint160, bytes calldata data)
        external
        returns (int256 amount0, int256 amount1)
    {
        bytes calldata path = data.toBytes(0);
        (address first,, address last) = path.decodeFirstPool();
        address inputToken = amountSpecified > 0 ? first : last;
        uint256 inputBefore = V3OutputToken(inputToken).balanceOf(address(this));
        uint256 delivered = amountSpecified < 0 ? uint256(-amountSpecified) : outputAmount;
        if (transferOutput) V3OutputToken(outputToken).mint(recipient, delivered - shortfall);
        int256 amountIn = amountSpecified > 0 ? amountSpecified : int256(exactOutputInput == 0 ? 1 : exactOutputInput);
        int256 amountOut = -int256(delivered - reportedShortfall);
        (amount0, amount1) = zeroForOne ? (amountIn, amountOut) : (amountOut, amountIn);
        V3SwapRouter(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
        require(V3OutputToken(inputToken).balanceOf(address(this)) >= inputBefore + uint256(amountIn), "INPUT_NOT_PAID");
    }
}

contract V3OutputPermit2Mock {
    function transferFrom(address sender, address recipient, uint160 amount, address token) external {
        V3OutputToken(token).transferFrom(sender, recipient, amount);
    }
}

contract V3SwapRouterHarness is V3SwapRouter {
    constructor(RouterParameters memory params) RouterImmutables(params) {}

    function exactInput(address recipient, uint256 amountOutMinimum, bytes calldata path) external {
        v3SwapExactInput(recipient, 1, amountOutMinimum, path, address(this));
    }

    function exactOutput(address recipient, uint256 amountOut, bytes calldata path) external {
        v3SwapExactOutput(recipient, amountOut, type(uint256).max, path, address(this));
    }

    function exactOutputWithLimit(address recipient, uint256 amountOut, uint256 maximum, bytes calldata path) external {
        v3SwapExactOutput(recipient, amountOut, maximum, path, address(this));
    }

    function exactOutputFrom(address recipient, uint256 amountOut, bytes calldata path, address payer) external {
        v3SwapExactOutput(recipient, amountOut, type(uint256).max, path, payer);
    }

    function recordedInput() external view returns (uint256) {
        return V3USDTInputAmount.get();
    }

    function maximumInput() external view returns (uint256) {
        return MaxInputAmount.get();
    }
}

contract V3USDTOutputTest is Test {
    address internal constant USDT = 0xa614f803B6FD780986A42c78Ec9c7f77e6DeD13C;
    address internal constant TOKEN_IN = address(0x1000000000000000000000000000000000000000);
    address internal constant TOKEN_HIGH = address(type(uint160).max);
    uint24 internal constant FEE = 3000;
    uint256 internal constant AMOUNT_OUT = 100;

    address internal recipient = address(0xBEEF);
    address internal deployer = address(0xD);
    bytes32 internal initCodeHash = keccak256("V3OutputPoolMock");
    V3SwapRouterHarness internal router;

    function setUp() public {
        RouterParameters memory params;
        params.v3Deployer = deployer;
        params.v3InitCodeHash = initCodeHash;
        params.permit2 = address(new V3OutputPermit2Mock());
        router = new V3SwapRouterHarness(params);

        V3OutputToken tokenImplementation = new V3OutputToken();
        vm.etch(USDT, address(tokenImplementation).code);
        vm.etch(TOKEN_IN, address(tokenImplementation).code);
        V3OutputToken(TOKEN_IN).mint(address(router), 1000);
    }

    function test_exactInputRevertsWhenPoolReportsUndeliveredUSDT() public {
        bytes memory path = abi.encodePacked(TOKEN_IN, FEE, USDT);
        _installPool(TOKEN_IN, USDT, false);

        vm.expectRevert(V3SwapRouter.V3InvalidAmountOut.selector);
        router.exactInput(recipient, AMOUNT_OUT, path);
    }

    function test_exactOutputRevertsWhenPoolReportsUndeliveredUSDT() public {
        bytes memory reversePath = abi.encodePacked(USDT, FEE, TOKEN_IN);
        _installPool(TOKEN_IN, USDT, false);
        V3OutputToken(USDT).mint(recipient, 1000);

        vm.expectRevert(V3SwapRouter.V3InvalidAmountOut.selector);
        router.exactOutput(recipient, AMOUNT_OUT, reversePath);
    }

    function test_exactOutputAcceptsDeliveredUSDT() public {
        _installPool(TOKEN_IN, USDT, true);
        router.exactOutput(recipient, AMOUNT_OUT, abi.encodePacked(USDT, FEE, TOKEN_IN));
        assertEq(V3OutputToken(USDT).balanceOf(recipient), AMOUNT_OUT);
        assertEq(V3OutputToken(TOKEN_IN).balanceOf(address(router)), 999);
    }

    function test_exactOutputCycleAddsBackActualInput() public {
        _installPool(TOKEN_IN, USDT, true);
        _installPoolWithFee(USDT, TOKEN_IN, 500, true);
        V3OutputToken(USDT).mint(address(router), 1000);

        router.exactOutput(address(router), AMOUNT_OUT, abi.encodePacked(USDT, FEE, TOKEN_IN, uint24(500), USDT));

        assertEq(V3OutputToken(USDT).balanceOf(address(router)), 1000 + AMOUNT_OUT - 1);
        assertEq(V3OutputToken(TOKEN_IN).balanceOf(address(router)), 1000);
        assertEq(router.recordedInput(), 0);
    }

    function test_exactOutputCycleCanSpendMoreThanOutput() public {
        _prepareCycle(true);
        _pool(500).setExactOutputInput(120);
        router.exactOutput(address(router), AMOUNT_OUT, _cyclePath());
        assertEq(V3OutputToken(USDT).balanceOf(address(router)), 980);
        assertEq(router.recordedInput(), 0);
    }

    function test_exactOutputCycleRejectsPartialDelivery() public {
        _prepareCycle(true);
        _pool(FEE).setShortfall(1);
        _pool(500).setExactOutputInput(80);
        vm.expectRevert(V3SwapRouter.V3InvalidAmountOut.selector);
        router.exactOutput(address(router), AMOUNT_OUT, _cyclePath());
        assertEq(V3OutputToken(USDT).balanceOf(address(router)), 1000);
        assertEq(router.recordedInput(), 0);
    }

    function test_exactOutputCycleWithExternalPayerAndRecipient() public {
        _prepareCycle(true);
        _pool(500).setExactOutputInput(80);
        V3OutputToken(USDT).mint(recipient, 1000);
        router.exactOutputFrom(recipient, AMOUNT_OUT, _cyclePath(), recipient);
        assertEq(V3OutputToken(USDT).balanceOf(recipient), 1020);
        assertEq(V3OutputToken(USDT).balanceOf(address(router)), 1000);
    }

    function test_exactOutputDoesNotAddBackAnotherPayersInput() public {
        _prepareCycle(true);
        _pool(FEE).setShortfall(1);
        vm.expectRevert(V3SwapRouter.V3InvalidAmountOut.selector);
        router.exactOutput(recipient, AMOUNT_OUT, _cyclePath());
    }

    function test_exactOutputDoesNotAddBackDifferentInputToken() public {
        _installPool(TOKEN_IN, USDT, true);
        _pool(FEE).setShortfall(1);
        vm.expectRevert(V3SwapRouter.V3InvalidAmountOut.selector);
        router.exactOutput(address(router), AMOUNT_OUT, abi.encodePacked(USDT, FEE, TOKEN_IN));
    }

    function test_consecutiveExactOutputSwapsClearAccounting() public {
        _prepareCycle(true);
        _pool(500).setExactOutputInput(80);
        router.exactOutput(address(router), AMOUNT_OUT, _cyclePath());
        assertEq(router.recordedInput(), 0);
        _pool(500).setExactOutputInput(20);
        router.exactOutput(address(router), AMOUNT_OUT, _cyclePath());
        assertEq(V3OutputToken(USDT).balanceOf(address(router)), 1100);
        assertEq(router.recordedInput(), 0);
    }

    function test_exactOutputCycleRejectsUndeliveredUSDTDespiteExistingBalance() public {
        _installPool(TOKEN_IN, USDT, false);
        _installPoolWithFee(USDT, TOKEN_IN, 500, true);
        V3OutputToken(USDT).mint(address(router), 1000);

        vm.expectRevert(V3SwapRouter.V3InvalidAmountOut.selector);
        router.exactOutput(address(router), AMOUNT_OUT, abi.encodePacked(USDT, FEE, TOKEN_IN, uint24(500), USDT));
    }

    function test_exactOutputStillEnforcesMaximumInput() public {
        _installPool(TOKEN_IN, USDT, true);
        vm.expectRevert(V3SwapRouter.V3TooMuchRequested.selector);
        router.exactOutputWithLimit(recipient, AMOUNT_OUT, 0, abi.encodePacked(USDT, FEE, TOKEN_IN));
    }

    function test_callbackStillAuthenticatesPoolWithOriginalDataFormat() public {
        bytes memory data = abi.encode(abi.encodePacked(USDT, FEE, TOKEN_IN), address(router));
        vm.expectRevert(V3SwapRouter.V3InvalidCaller.selector);
        router.uniswapV3SwapCallback(1, -int256(AMOUNT_OUT), data);
    }

    function test_acceptsDeliveredUSDT() public {
        bytes memory path = abi.encodePacked(TOKEN_IN, FEE, USDT);
        _installPool(TOKEN_IN, USDT, true);

        router.exactInput(recipient, AMOUNT_OUT, path);

        assertEq(V3OutputToken(USDT).balanceOf(recipient), AMOUNT_OUT);
    }

    function test_doesNotApplyBalanceCheckToOtherTokens() public {
        V3OutputToken otherToken = new V3OutputToken();
        bytes memory path = abi.encodePacked(TOKEN_IN, FEE, address(otherToken));
        _installPool(TOKEN_IN, address(otherToken), false);

        router.exactInput(recipient, AMOUNT_OUT, path);

        assertEq(otherToken.balanceOf(recipient), 0);
    }

    function test_exactOutputOtherTokenDoesNotCheckUSDTBalance() public {
        _installPool(USDT, TOKEN_IN, true);
        V3OutputToken(USDT).mint(address(router), 1000);
        router.exactOutput(recipient, AMOUNT_OUT, abi.encodePacked(TOKEN_IN, FEE, USDT));
        assertEq(V3OutputToken(TOKEN_IN).balanceOf(recipient), AMOUNT_OUT);
        assertEq(V3OutputToken(USDT).balanceOf(address(router)), 999);
        assertEq(router.recordedInput(), 0);
        assertEq(router.maximumInput(), 0);
    }

    function test_exactOutputWithoutUSDT() public {
        vm.etch(TOKEN_HIGH, address(new V3OutputToken()).code);
        _installPool(TOKEN_IN, TOKEN_HIGH, true);
        router.exactOutput(recipient, AMOUNT_OUT, abi.encodePacked(TOKEN_HIGH, FEE, TOKEN_IN));
        assertEq(V3OutputToken(TOKEN_HIGH).balanceOf(recipient), AMOUNT_OUT);
        assertEq(V3OutputToken(TOKEN_IN).balanceOf(address(router)), 999);
        assertEq(router.recordedInput(), 0);
        assertEq(router.maximumInput(), 0);
    }

    function test_exactOutputOtherTokenStillRequiresReportedAmount() public {
        _installPool(USDT, TOKEN_IN, true);
        V3OutputToken(USDT).mint(address(router), 1000);
        _pool(FEE).setReportedShortfall(1);
        vm.expectRevert(V3SwapRouter.V3InvalidAmountOut.selector);
        router.exactOutput(recipient, AMOUNT_OUT, abi.encodePacked(TOKEN_IN, FEE, USDT));
        assertEq(V3OutputToken(TOKEN_IN).balanceOf(recipient), 0);
        assertEq(V3OutputToken(USDT).balanceOf(address(router)), 1000);
    }

    function test_exactOutputUSDTStillRequiresReportedAmount() public {
        _installPool(TOKEN_IN, USDT, true);
        _pool(FEE).setReportedShortfall(1);
        vm.expectRevert(V3SwapRouter.V3InvalidAmountOut.selector);
        router.exactOutput(recipient, AMOUNT_OUT, abi.encodePacked(USDT, FEE, TOKEN_IN));
        assertEq(V3OutputToken(USDT).balanceOf(recipient), 0);
    }

    // Exercise both token address orderings and three nested callbacks. The deepest
    // input is 120, while outer hops ask for 7 and 3: overwriting it must fail.
    function test_threeHopCyclePreservesDeepestInputBothDirections() public {
        for (uint256 direction; direction < 2; ++direction) {
            bytes memory path = _prepareThreeHopCycle(direction == 1);
            uint256 balanceBefore = V3OutputToken(USDT).balanceOf(address(router));
            router.exactOutput(address(router), AMOUNT_OUT, path);
            assertEq(V3OutputToken(USDT).balanceOf(address(router)), balanceBefore + AMOUNT_OUT - 120);
            assertEq(router.recordedInput(), 0);
            assertEq(router.maximumInput(), 0);
        }
    }

    function test_threeHopCycleRejectsShortDelivery() public {
        bytes memory path = _prepareThreeHopCycle(false);
        _poolAt(TOKEN_HIGH, USDT, FEE).setShortfall(1);
        vm.expectRevert(V3SwapRouter.V3InvalidAmountOut.selector);
        router.exactOutput(address(router), AMOUNT_OUT, path);
        assertEq(V3OutputToken(USDT).balanceOf(address(router)), 1000);
        assertEq(router.recordedInput(), 0);
    }

    function test_exactOutputIntermediateUSDTMustPayNextPool() public {
        _installPool(TOKEN_IN, USDT, false);
        _installPoolWithFee(USDT, TOKEN_HIGH, 500, true);
        vm.etch(TOKEN_HIGH, address(new V3OutputToken()).code);
        bytes memory path = abi.encodePacked(TOKEN_HIGH, uint24(500), USDT, FEE, TOKEN_IN);
        vm.expectRevert(bytes("INPUT_NOT_PAID"));
        router.exactOutput(recipient, AMOUNT_OUT, path);
        assertEq(V3OutputToken(TOKEN_HIGH).balanceOf(recipient), 0);
        assertEq(V3OutputToken(TOKEN_IN).balanceOf(address(router)), 1000);
    }

    function test_exactInputIntermediateUSDTShortfallCannotUseExistingBalance() public {
        vm.etch(TOKEN_HIGH, address(new V3OutputToken()).code);
        _installPool(TOKEN_IN, USDT, true);
        _pool(FEE).setShortfall(1);
        _installPoolWithFee(USDT, TOKEN_HIGH, 500, true);
        V3OutputToken(USDT).mint(address(router), 1000);
        vm.expectRevert(V3SwapRouter.V3InvalidAmountOut.selector);
        router.exactInput(recipient, AMOUNT_OUT, abi.encodePacked(TOKEN_IN, FEE, USDT, uint24(500), TOKEN_HIGH));
        assertEq(V3OutputToken(USDT).balanceOf(address(router)), 1000);
        assertEq(V3OutputToken(TOKEN_HIGH).balanceOf(recipient), 0);
    }

    function test_exactInputMultiHopDeliversUSDT() public {
        vm.etch(TOKEN_HIGH, address(new V3OutputToken()).code);
        _installPool(TOKEN_IN, TOKEN_HIGH, true);
        _installPoolWithFee(TOKEN_HIGH, USDT, 500, true);
        router.exactInput(recipient, AMOUNT_OUT, abi.encodePacked(TOKEN_IN, FEE, TOKEN_HIGH, uint24(500), USDT));
        assertEq(V3OutputToken(USDT).balanceOf(recipient), AMOUNT_OUT);
        assertEq(V3OutputToken(TOKEN_HIGH).balanceOf(address(router)), 0);
        assertEq(router.recordedInput(), 0);
    }

    function test_failedExactOutputCanBeFollowedBySuccessfulSwap() public {
        _prepareCycle(true);
        _pool(500).setExactOutputInput(120);
        _pool(FEE).setShortfall(1);
        vm.expectRevert(V3SwapRouter.V3InvalidAmountOut.selector);
        router.exactOutput(address(router), AMOUNT_OUT, _cyclePath());
        assertEq(router.recordedInput(), 0);
        assertEq(router.maximumInput(), 0);
        assertEq(V3OutputToken(USDT).balanceOf(address(router)), 1000);

        _pool(FEE).setShortfall(0);
        router.exactOutputWithLimit(address(router), AMOUNT_OUT, 120, _cyclePath());
        assertEq(V3OutputToken(USDT).balanceOf(address(router)), 980);
        assertEq(router.recordedInput(), 0);
        assertEq(router.maximumInput(), 0);
    }

    function test_cycleMaximumInputBoundaryAndRollback() public {
        _prepareCycle(true);
        _pool(500).setExactOutputInput(120);
        vm.expectRevert(V3SwapRouter.V3TooMuchRequested.selector);
        router.exactOutputWithLimit(address(router), AMOUNT_OUT, 119, _cyclePath());
        assertEq(V3OutputToken(USDT).balanceOf(address(router)), 1000);
        router.exactOutputWithLimit(address(router), AMOUNT_OUT, 120, _cyclePath());
        assertEq(V3OutputToken(USDT).balanceOf(address(router)), 980);
    }

    function testFuzz_threeHopCycleDelivery(uint96 input, uint96 output, bool reverse, bool shortDelivery) public {
        uint256 actualInput = bound(uint256(input), 1, 1000);
        uint256 expectedOutput = bound(uint256(output), 1, 1000);
        bytes memory path = _prepareThreeHopCycle(reverse);
        address first = reverse ? TOKEN_HIGH : TOKEN_IN;
        address last = reverse ? TOKEN_IN : TOKEN_HIGH;
        _poolAt(USDT, first, 500).setExactOutputInput(actualInput);
        if (shortDelivery) {
            _poolAt(last, USDT, FEE).setShortfall(1);
            vm.expectRevert(V3SwapRouter.V3InvalidAmountOut.selector);
        }
        router.exactOutputWithLimit(address(router), expectedOutput, actualInput, path);
        assertEq(
            V3OutputToken(USDT).balanceOf(address(router)), shortDelivery ? 1000 : 1000 + expectedOutput - actualInput
        );
        assertEq(router.recordedInput(), 0);
        assertEq(router.maximumInput(), 0);
    }

    function test_executeUserPaidCycleAndRecipientMapping() public {
        _prepareCycle(true);
        _pool(500).setExactOutputInput(120);
        UniversalRouter executor = _executor();
        V3OutputToken(USDT).mint(address(this), 1000);
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT_OUT, uint256(120), _cyclePath(), true);
        executor.execute(abi.encodePacked(bytes1(uint8(Commands.V3_SWAP_EXACT_OUT))), inputs, block.timestamp);
        assertEq(V3OutputToken(USDT).balanceOf(address(this)), 980);
        assertEq(V3OutputToken(USDT).balanceOf(address(executor)), 0);
    }

    function test_executeRouterPaidCycleAndSweep() public {
        _prepareCycle(true);
        _pool(500).setExactOutputInput(120);
        UniversalRouter executor = _executor();
        V3OutputToken(USDT).mint(address(executor), 1000);
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.ADDRESS_THIS, AMOUNT_OUT, uint256(120), _cyclePath(), false);
        executor.execute(abi.encodePacked(bytes1(uint8(Commands.V3_SWAP_EXACT_OUT))), inputs, block.timestamp);
        assertEq(V3OutputToken(USDT).balanceOf(address(executor)), 0);
        assertEq(V3OutputToken(USDT).balanceOf(address(0xCAFE)), 980);
    }

    function test_executeMixedCommandsDoNotReuseAccounting() public {
        _prepareCycle(true);
        _pool(500).setExactOutputInput(120);
        UniversalRouter executor = _executor();
        V3OutputToken(USDT).mint(address(this), 1000);
        V3OutputToken(TOKEN_IN).mint(address(this), 1000);
        bytes[] memory inputs = new bytes[](3);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT_OUT, uint256(120), _cyclePath(), true);
        inputs[1] =
            abi.encode(ActionConstants.MSG_SENDER, uint256(1), AMOUNT_OUT, abi.encodePacked(TOKEN_IN, FEE, USDT), true);
        inputs[2] =
            abi.encode(ActionConstants.MSG_SENDER, AMOUNT_OUT, uint256(1), abi.encodePacked(USDT, FEE, TOKEN_IN), true);
        executor.execute(
            abi.encodePacked(
                bytes1(uint8(Commands.V3_SWAP_EXACT_OUT)),
                bytes1(uint8(Commands.V3_SWAP_EXACT_IN)),
                bytes1(uint8(Commands.V3_SWAP_EXACT_OUT))
            ),
            inputs,
            block.timestamp
        );
        assertEq(V3OutputToken(USDT).balanceOf(address(this)), 1180);
        assertEq(V3OutputToken(TOKEN_IN).balanceOf(address(this)), 998);
    }

    function test_executeNonUSDTOutputThenShortUSDTDeliveryRevertsBatch() public {
        _prepareCycle(true);
        _pool(500).setExactOutputInput(120);
        _pool(FEE).setShortfall(1);
        UniversalRouter executor = _executor();
        V3OutputToken(USDT).mint(address(this), 1000);
        V3OutputToken(TOKEN_IN).mint(address(this), 1000);
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(
            ActionConstants.MSG_SENDER, AMOUNT_OUT, uint256(120), abi.encodePacked(TOKEN_IN, uint24(500), USDT), true
        );
        inputs[1] =
            abi.encode(ActionConstants.MSG_SENDER, AMOUNT_OUT, uint256(1), abi.encodePacked(USDT, FEE, TOKEN_IN), true);
        vm.expectRevert(V3SwapRouter.V3InvalidAmountOut.selector);
        executor.execute(
            abi.encodePacked(bytes1(uint8(Commands.V3_SWAP_EXACT_OUT)), bytes1(uint8(Commands.V3_SWAP_EXACT_OUT))),
            inputs,
            block.timestamp
        );
        assertEq(V3OutputToken(USDT).balanceOf(address(this)), 1000);
        assertEq(V3OutputToken(TOKEN_IN).balanceOf(address(this)), 1000);
        assertEq(V3OutputToken(USDT).balanceOf(address(0xCAFE)), 0);
    }

    function test_executeFailedCallThenSuccessfulCall() public {
        _prepareCycle(true);
        _pool(500).setExactOutputInput(120);
        _pool(FEE).setShortfall(1);
        UniversalRouter executor = _executor();
        V3OutputToken(USDT).mint(address(this), 1000);
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT_OUT, uint256(120), _cyclePath(), true);
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.V3_SWAP_EXACT_OUT)));
        vm.expectRevert(V3SwapRouter.V3InvalidAmountOut.selector);
        executor.execute(commands, inputs, block.timestamp);
        assertEq(V3OutputToken(USDT).balanceOf(address(this)), 1000);
        _pool(FEE).setShortfall(0);
        executor.execute(commands, inputs, block.timestamp);
        assertEq(V3OutputToken(USDT).balanceOf(address(this)), 980);
    }

    function _executor() private returns (UniversalRouter) {
        RouterParameters memory params;
        params.v3Deployer = deployer;
        params.v3InitCodeHash = initCodeHash;
        params.permit2 = address(new V3OutputPermit2Mock());
        params.safeVault = address(0xCAFE);
        return new UniversalRouter(params);
    }

    function _prepareThreeHopCycle(bool reverse) private returns (bytes memory) {
        vm.etch(TOKEN_HIGH, address(new V3OutputToken()).code);
        address first = reverse ? TOKEN_HIGH : TOKEN_IN;
        address last = reverse ? TOKEN_IN : TOKEN_HIGH;
        _installPoolWithFee(USDT, first, 500, true);
        _installPoolWithFee(first, last, 10000, true);
        _installPoolWithFee(last, USDT, FEE, true);
        _poolAt(USDT, first, 500).setExactOutputInput(120);
        _poolAt(first, last, 10000).setExactOutputInput(7);
        _poolAt(last, USDT, FEE).setExactOutputInput(3);
        V3OutputToken(USDT).mint(address(router), 1000);
        return abi.encodePacked(USDT, FEE, last, uint24(10000), first, uint24(500), USDT);
    }

    function _poolAt(address tokenA, address tokenB, uint24 fee) private view returns (V3OutputPoolMock) {
        return V3OutputPoolMock(UniversalRouterHelper.computePoolAddress(deployer, initCodeHash, tokenA, tokenB, fee));
    }

    function _installPool(address tokenA, address tokenB, bool transferOutput) private {
        _installPoolWithFee(tokenA, tokenB, FEE, transferOutput);
    }

    function _prepareCycle(bool transferOutput) private {
        _installPool(TOKEN_IN, USDT, transferOutput);
        _installPoolWithFee(USDT, TOKEN_IN, 500, true);
        V3OutputToken(USDT).mint(address(router), 1000);
    }

    function _pool(uint24 fee) private view returns (V3OutputPoolMock) {
        return V3OutputPoolMock(UniversalRouterHelper.computePoolAddress(deployer, initCodeHash, TOKEN_IN, USDT, fee));
    }

    function _cyclePath() private pure returns (bytes memory) {
        return abi.encodePacked(USDT, FEE, TOKEN_IN, uint24(500), USDT);
    }

    function _installPoolWithFee(address tokenA, address tokenB, uint24 fee, bool transferOutput) private {
        address outputToken = tokenB;
        V3OutputPoolMock implementation = new V3OutputPoolMock(outputToken, AMOUNT_OUT, transferOutput);
        address pool = UniversalRouterHelper.computePoolAddress(deployer, initCodeHash, tokenA, tokenB, fee);
        vm.etch(pool, address(implementation).code);
    }
}
