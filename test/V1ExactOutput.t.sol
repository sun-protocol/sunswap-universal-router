// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {V1SwapRouter} from "src/modules/sunswap/v1/V1SwapRouter.sol";
import {RouterImmutables, RouterParameters} from "src/base/RouterImmutables.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {ISunswapExchange} from "src/modules/sunswap/v1/interfaces/ISunswapExchange.sol";
import {ActionConstants} from "v4-periphery/src/libraries/ActionConstants.sol";

contract V1OutputHarness is V1SwapRouter {
    constructor(RouterParameters memory params) RouterImmutables(params) {}

    function swap(address recipient, uint256 amountOut, uint256 maximum, address[] calldata path, address payer)
        external payable
    {
        v1SwapExactOutput(recipient, amountOut, maximum, path, payer);
    }

    function refund(address token, address recipient) external {
        sweep(token, recipient, 0);
    }

    function swapExactInput(address recipient, uint256 amountIn, address[] calldata path, address payer) external {
        v1SwapExactInput(recipient, amountIn, 0, path, payer);
    }

    receive() external payable {}
}

contract V1OutputFactory {
    mapping(address => address payable) public getExchange;

    function set(address token, address payable exchange) external {
        getExchange[token] = exchange;
    }
}

// Only output entrypoints are implemented: any accidental input swap fails.
contract V1OutputExchange {
    MockERC20 public token;
    V1OutputFactory public factory;

    constructor(MockERC20 token_, V1OutputFactory factory_) {
        token = token_;
        factory = factory_;
    }

    function price(uint256 out, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        return reserveIn * out * 1000 / ((reserveOut - out) * 997) + 1;
    }

    function getTrxToTokenOutputPrice(uint256 out) external view returns (uint256) {
        return price(out, address(this).balance, token.balanceOf(address(this)));
    }

    function getTokenToTrxOutputPrice(uint256 out) external view returns (uint256) {
        return price(out, token.balanceOf(address(this)), address(this).balance);
    }

    function trxToTokenTransferOutput(uint256 out, uint256 deadline, address recipient)
        external payable returns (uint256 spent)
    {
        require(deadline >= block.timestamp);
        spent = price(out, address(this).balance - msg.value, token.balanceOf(address(this)));
        require(spent <= msg.value);
        token.transfer(recipient, out);
        if (msg.value > spent) {
            (bool ok,) = msg.sender.call{value: msg.value - spent}("");
            require(ok);
        }
    }

    function tokenToTrxTransferOutput(uint256 out, uint256 maximum, uint256 deadline, address recipient)
        external returns (uint256 spent)
    {
        require(deadline >= block.timestamp);
        spent = price(out, token.balanceOf(address(this)), address(this).balance);
        require(spent <= maximum);
        token.transferFrom(msg.sender, address(this), spent);
        (bool ok,) = recipient.call{value: out}("");
        require(ok);
    }

    function tokenToTokenTransferOutput(
        uint256 out, uint256 maximum, uint256 maxTrx, uint256 deadline, address recipient, address output
    ) external returns (uint256 spent) {
        V1OutputExchange next = V1OutputExchange(factory.getExchange(output));
        uint256 trx = next.getTrxToTokenOutputPrice(out);
        require(trx <= maxTrx);
        spent = price(trx, token.balanceOf(address(this)), address(this).balance);
        require(spent <= maximum);
        token.transferFrom(msg.sender, address(this), spent);
        next.trxToTokenTransferOutput{value: trx}(out, deadline, recipient);
    }

    receive() external payable {}
}

contract V1OutputPermit2 {
    function transferFrom(address from, address to, uint160 amount, address token) external {
        MockERC20(token).transferFrom(from, to, amount);
    }
}

contract V1ExactOutputTest is Test {
    MockERC20 a;
    MockERC20 b;
    V1OutputFactory factory;
    V1OutputExchange poolA;
    V1OutputExchange poolB;
    V1OutputHarness router;
    V1OutputPermit2 permit2;
    address recipient = address(0xBEEF);

    function setUp() public {
        a = new MockERC20();
        b = new MockERC20();
        factory = new V1OutputFactory();
        poolA = new V1OutputExchange(a, factory);
        poolB = new V1OutputExchange(b, factory);
        factory.set(address(a), payable(address(poolA)));
        factory.set(address(b), payable(address(poolB)));
        a.mint(address(poolA), 1_000_000);
        b.mint(address(poolB), 1_000_000);
        vm.deal(address(poolA), 1_000_000);
        vm.deal(address(poolB), 1_000_000);
        permit2 = new V1OutputPermit2();
        RouterParameters memory params;
        params.v1Factory = address(factory);
        params.permit2 = address(permit2);
        router = new V1OutputHarness(params);
        a.mint(address(router), 100_000);
        vm.deal(address(this), 100_000);
    }

    function path(address input, address output) internal pure returns (address[] memory result) {
        result = new address[](2);
        result[0] = input;
        result[1] = output;
    }

    function test_nativeToTokenAndExplicitRefund() public {
        router.swap{value: 20_000}(recipient, 10_000, 20_000, path(address(0), address(b)), address(router));
        assertEq(b.balanceOf(recipient), 10_000);
        assertEq(address(router).balance, 20_000 - 10_132);
        router.refund(address(0), recipient);
        assertEq(recipient.balance, 20_000 - 10_132);
        assertEq(address(router).balance, 0);
    }

    function test_nativeQuoteUsesExchangePrice() public {
        vm.mockCall(address(poolB), abi.encodeCall(ISunswapExchange.getTrxToTokenOutputPrice, (10_000)), abi.encode(12_345));
        vm.expectCall(address(poolB), 12_345, abi.encodeCall(
            ISunswapExchange.trxToTokenTransferOutput, (10_000, block.timestamp + 1, recipient)
        ));
        router.swap{value: 12_345}(recipient, 10_000, 12_345, path(address(0), address(b)), address(router));
        assertEq(b.balanceOf(recipient), 10_000);
    }

    function test_tokenQuoteUsesExchangePriceAndEnforcesMaximum() public {
        vm.mockCall(address(poolA), abi.encodeCall(ISunswapExchange.getTokenToTrxOutputPrice, (10_000)), abi.encode(12_345));
        vm.expectRevert(V1SwapRouter.V1TooMuchRequested.selector);
        router.swap(recipient, 10_000, 12_344, path(address(a), address(0)), address(router));
        assertEq(a.balanceOf(address(router)), 100_000);
        vm.expectCall(address(poolA), abi.encodeCall(
            ISunswapExchange.tokenToTrxTransferOutput, (10_000, 12_345, block.timestamp + 1, recipient)
        ));
        router.swap(recipient, 10_000, 12_345, path(address(a), address(0)), address(router));
        assertEq(recipient.balance, 10_000);
    }

    function test_tokenToTokenQuotesOutputPoolThenInputPool() public {
        vm.mockCall(address(poolB), abi.encodeCall(ISunswapExchange.getTrxToTokenOutputPrice, (10_000)), abi.encode(12_345));
        vm.mockCall(address(poolA), abi.encodeCall(ISunswapExchange.getTokenToTrxOutputPrice, (12_345)), abi.encode(23_456));
        vm.expectCall(address(poolA), abi.encodeCall(ISunswapExchange.getTokenToTrxOutputPrice, (12_345)));
        vm.expectCall(address(poolA), abi.encodeCall(
            ISunswapExchange.tokenToTokenTransferOutput,
            (10_000, 23_456, 12_345, block.timestamp + 1, recipient, address(b))
        ));
        router.swap(recipient, 10_000, 23_456, path(address(a), address(b)), address(router));
        assertEq(b.balanceOf(recipient), 10_000);
    }

    function test_tokenToNative() public {
        router.swap(recipient, 10_000, 10_132, path(address(a), address(0)), address(router));
        assertEq(recipient.balance, 10_000);
        assertEq(a.balanceOf(address(router)), 100_000 - 10_132);
        assertEq(a.allowance(address(router), address(poolA)), 0);
    }

    function test_tokenToTokenUsesBothPools() public {
        router.swap(recipient, 10_000, 10_267, path(address(a), address(b)), address(router));
        assertEq(b.balanceOf(recipient), 10_000);
        assertEq(a.balanceOf(address(router)), 100_000 - 10_267);
        assertEq(address(poolB).balance, 1_000_000 + 10_132);
        assertEq(a.allowance(address(router), address(poolA)), 0);
    }

    function test_userPaysOnlyRequiredInput() public {
        a.mint(address(this), 20_000);
        a.approve(address(permit2), 20_000);
        router.swap(recipient, 10_000, 20_000, path(address(a), address(b)), address(this));
        assertEq(a.balanceOf(address(this)), 20_000 - 10_267);
        assertEq(a.balanceOf(address(router)), 100_000);
        assertEq(b.balanceOf(recipient), 10_000);
    }

    function test_outputToRouter() public {
        router.swap(address(router), 10_000, 10_267, path(address(a), address(b)), address(router));
        assertEq(b.balanceOf(address(router)), 10_000);
    }

    function test_inputLimitRevertsBeforePayment() public {
        vm.expectRevert(V1SwapRouter.V1TooMuchRequested.selector);
        router.swap(recipient, 10_000, 10_266, path(address(a), address(b)), address(this));
        assertEq(a.balanceOf(address(router)), 100_000);
    }

    function test_insufficientNativeBalance() public {
        vm.expectRevert(V1SwapRouter.V1TooMuchRequested.selector);
        router.swap(recipient, 10_000, 20_000, path(address(0), address(b)), address(router));
    }

    function test_insufficientTokenBalance() public {
        vm.expectRevert(V1SwapRouter.V1TooMuchRequested.selector);
        router.swap(recipient, 100_000, 1_000_000, path(address(a), address(b)), address(router));
    }

    function test_invalidPaths() public {
        for (uint256 length; length <= 3; length++) {
            if (length == 2) continue;
            vm.expectRevert(V1SwapRouter.V1InvalidPath.selector);
            router.swap(recipient, 1, 100, new address[](length), address(router));
        }
        vm.expectRevert(V1SwapRouter.V1InvalidPath.selector);
        router.swap(recipient, 1, 100, path(address(a), address(a)), address(router));
    }

    function test_exactInputRejectsInvalidPathLengthBeforePayment() public {
        for (uint256 length; length <= 4; length++) {
            if (length == 2) continue;
            address[] memory route = new address[](length);
            if (length > 0) route[0] = address(a);
            // No user funds or approval: validation must run before Permit2 payment.
            vm.expectRevert(V1SwapRouter.V1InvalidPath.selector);
            router.swapExactInput(recipient, 100, route, address(this));
        }
        assertEq(a.balanceOf(address(router)), 100_000);
    }

    function test_exactInputTwoAddressPathReachesExchangeLookup() public {
        factory.set(address(a), payable(address(0)));
        vm.expectRevert(V1SwapRouter.V1InvalidExchange.selector);
        router.swapExactInput(recipient, 100, path(address(a), address(b)), address(router));
    }

    function test_exactInputRejectsIdenticalTokensBeforePayment() public {
        vm.expectRevert(V1SwapRouter.V1InvalidPath.selector);
        router.swapExactInput(recipient, 100, path(address(a), address(a)), address(this));
        vm.expectRevert(V1SwapRouter.V1InvalidPath.selector);
        router.swapExactInput(recipient, 100, path(address(0), address(0)), address(router));
    }

    function test_exactInputNonzeroContractBalanceReachesExchangeLookup() public {
        factory.set(address(a), payable(address(0)));
        vm.expectRevert(V1SwapRouter.V1InvalidExchange.selector);
        router.swapExactInput(recipient, ActionConstants.CONTRACT_BALANCE, path(address(a), address(b)), address(router));
    }

    function test_missingOutputPool() public {
        factory.set(address(b), payable(address(0)));
        vm.expectRevert(V1SwapRouter.V1InvalidExchange.selector);
        router.swap(recipient, 10_000, 20_000, path(address(a), address(b)), address(router));
    }

    function test_missingInputPool() public {
        factory.set(address(a), payable(address(0)));
        vm.expectRevert(V1SwapRouter.V1InvalidExchange.selector);
        router.swap(recipient, 10_000, 20_000, path(address(a), address(b)), address(router));
    }
}
