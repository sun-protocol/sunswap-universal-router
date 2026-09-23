// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {V3SwapRouter} from "src/modules/sunswap/v3/V3SwapRouter.sol";
import {RouterImmutables, RouterParameters} from "src/base/RouterImmutables.sol";
import {UniversalRouterHelper} from "src/libraries/UniversalRouterHelper.sol";

contract V3OutputToken {
    mapping(address => uint256) public balanceOf;

    function mint(address recipient, uint256 amount) external {
        balanceOf[recipient] += amount;
    }
}

contract V3OutputPoolMock {
    address internal immutable outputToken;
    uint256 internal immutable outputAmount;
    bool internal immutable transferOutput;

    constructor(address outputToken_, uint256 outputAmount_, bool transferOutput_) {
        outputToken = outputToken_;
        outputAmount = outputAmount_;
        transferOutput = transferOutput_;
    }

    function swap(address recipient, bool zeroForOne, int256 amountSpecified, uint160, bytes calldata)
        external
        returns (int256 amount0, int256 amount1)
    {
        if (transferOutput) V3OutputToken(outputToken).mint(recipient, outputAmount);

        int256 amountIn = amountSpecified > 0 ? amountSpecified : int256(1);
        int256 amountOut = -int256(outputAmount);
        return zeroForOne ? (amountIn, amountOut) : (amountOut, amountIn);
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
}

contract V3USDTOutputTest is Test {
    address internal constant USDT = 0xa614f803B6FD780986A42c78Ec9c7f77e6DeD13C;
    address internal constant TOKEN_IN = address(0x1000000000000000000000000000000000000000);
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
        router = new V3SwapRouterHarness(params);

        V3OutputToken tokenImplementation = new V3OutputToken();
        vm.etch(USDT, address(tokenImplementation).code);
    }

    function test_exactInputRevertsWhenPoolReportsUndeliveredUSDT() public {
        bytes memory path = abi.encodePacked(TOKEN_IN, FEE, USDT);
        _installPool(TOKEN_IN, USDT, false);

        vm.expectRevert(V3SwapRouter.V3InvalidAmountOut.selector);
        router.exactInput(recipient, AMOUNT_OUT, path);
    }

    function test_exactOutputRevertsWhenPoolReportsUndeliveredUSDT() public {
        bytes memory reversePath = abi.encodePacked(USDT, FEE, TOKEN_IN);
        _installPool(USDT, TOKEN_IN, false);

        vm.expectRevert(V3SwapRouter.V3InvalidAmountOut.selector);
        router.exactOutput(recipient, AMOUNT_OUT, reversePath);
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

    function _installPool(address tokenA, address tokenB, bool transferOutput) private {
        address outputToken = tokenB;
        V3OutputPoolMock implementation = new V3OutputPoolMock(outputToken, AMOUNT_OUT, transferOutput);
        address pool = UniversalRouterHelper.computePoolAddress(deployer, initCodeHash, tokenA, tokenB, FEE);
        vm.etch(pool, address(implementation).code);
    }
}
