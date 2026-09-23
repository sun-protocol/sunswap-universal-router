// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PSMSwapRouter, Ownable} from "src/modules/sunswap/PSM/PSMSwapRouter.sol";
import {RouterImmutables, RouterParameters} from "src/base/RouterImmutables.sol";
import {MockERC20} from "./mock/MockERC20.sol";

contract PSMOutputHarness is PSMSwapRouter {
    constructor(RouterParameters memory params)
        RouterImmutables(params) PSMSwapRouter(params.stableFactory) Ownable(msg.sender) {}

    function swap(address recipient, uint256 output, uint256 maximum, address[] calldata path, uint256[] calldata flags)
        external
    {
        psmSwapExactOutput(recipient, output, maximum, path, flags, address(this));
    }

    function swapInput(address recipient, uint256 input, uint256 minimum, address[] calldata path, uint256[] calldata flags)
        external
    {
        psmSwapExactInput(recipient, input, minimum, path, flags, address(this));
    }
}

contract PSMOutputPool {
    MockERC20 public usdd;
    MockERC20 public gem;
    uint256 public immutable RATIO;
    uint256 public payoutBps = 10_000;

    constructor(MockERC20 usdd_, MockERC20 gem_, uint256 ratio_) { usdd = usdd_; gem = gem_; RATIO = ratio_; }
    function gemJoin() external view returns (address) { return address(this); }
    function setPayoutBps(uint256 value) external { payoutBps = value; }
    function sellGem(address recipient, uint256 amount) external {
        gem.transferFrom(msg.sender, address(this), amount);
        usdd.mint(recipient, amount * RATIO * payoutBps / 10_000);
    }
    function buyGem(address recipient, uint256 amount) external {
        usdd.transferFrom(msg.sender, address(this), amount * RATIO);
        gem.mint(recipient, amount * payoutBps / 10_000);
    }
    function getStableInfo(address, address, uint256) external view returns (uint256, uint256, address, uint256) {
        return (0, 0, address(this), RATIO);
    }
}

contract PSMOutputFactory {
    mapping(uint256 => PSMOutputPool) public pools;

    function set(uint256 flag, PSMOutputPool pool) external { pools[flag] = pool; }

    function getStableInfo(address input, address output, uint256 flag)
        external view returns (uint256, uint256, address, uint256)
    {
        PSMOutputPool pool = pools[flag];
        if (address(pool) == address(0)) return (0, 0, address(0), 0);
        require(
            (input == address(pool.gem()) && output == address(pool.usdd())) ||
            (input == address(pool.usdd()) && output == address(pool.gem()))
        );
        return (0, 0, address(pool), pool.RATIO());
    }
}

contract PSMExactOutputTest is Test {
    MockERC20 usdd;
    MockERC20 gem;
    PSMOutputPool pool;
    PSMOutputHarness router;
    address recipient = address(0xBEEF);
    uint256 constant RATIO = 1e12;

    function setUp() public {
        usdd = new MockERC20();
        gem = new MockERC20();
        pool = new PSMOutputPool(usdd, gem, RATIO);
        RouterParameters memory params;
        params.stableFactory = address(pool);
        router = new PSMOutputHarness(params);
        gem.mint(address(router), 100);
        usdd.mint(address(router), 100 * RATIO);
    }

    function swap(uint256 output, uint256 maximum, bool reverse, address receiver) internal {
        address[] memory path = new address[](2);
        path[0] = reverse ? address(usdd) : address(gem);
        path[1] = reverse ? address(gem) : address(usdd);
        router.swap(receiver, output, maximum, path, new uint256[](1));
    }

    function test_roundsUpAndPreservesPriorBalance() public {
        swap(RATIO + 1, 2, false, recipient);
        assertEq(usdd.balanceOf(recipient), 2 * RATIO);
        assertEq(usdd.balanceOf(address(router)), 100 * RATIO);
        assertEq(gem.balanceOf(address(router)), 98);
    }

    function test_exactDivisionDoesNotOvercharge() public {
        swap(RATIO, 1, false, recipient);
        assertEq(usdd.balanceOf(recipient), RATIO);
        assertEq(gem.balanceOf(address(router)), 99);
    }

    function test_roundedInputExceedsMaximum() public {
        vm.expectRevert(PSMSwapRouter.PSMTooMuchRequested.selector);
        swap(RATIO + 1, 1, false, recipient);
        assertEq(gem.balanceOf(address(router)), 100);
    }

    function test_reverseDirectionPreservesPriorBalance() public {
        swap(2, 2 * RATIO, true, recipient);
        assertEq(gem.balanceOf(recipient), 2);
        assertEq(gem.balanceOf(address(router)), 100);
        assertEq(usdd.balanceOf(address(router)), 98 * RATIO);
    }

    function test_outputToRouter() public {
        swap(RATIO, 1, false, address(router));
        assertEq(usdd.balanceOf(address(router)), 101 * RATIO);
    }

    function test_shortfallCannotUsePriorBalance() public {
        pool.setPayoutBps(5_000);
        vm.expectRevert(PSMSwapRouter.PSMTooLittleReceived.selector);
        swap(RATIO, 1, false, recipient);
        vm.expectRevert(PSMSwapRouter.PSMTooLittleReceived.selector);
        swap(RATIO, 1, false, address(router));
        vm.expectRevert(PSMSwapRouter.PSMTooLittleReceived.selector);
        swap(2, 2 * RATIO, true, recipient);
        assertEq(usdd.balanceOf(address(router)), 100 * RATIO);
        assertEq(gem.balanceOf(address(router)), 100);
        assertEq(usdd.balanceOf(recipient), 0);
        assertEq(gem.balanceOf(recipient), 0);
    }

    function test_transfersActualSurplus() public {
        pool.setPayoutBps(11_000);
        swap(RATIO, 1, false, recipient);
        assertEq(usdd.balanceOf(recipient), RATIO * 11 / 10);
        assertEq(usdd.balanceOf(address(router)), 100 * RATIO);
    }

    function test_rejectsSameTokenRoundTrip() public {
        address[] memory path = new address[](3);
        path[0] = address(gem);
        path[1] = address(usdd);
        path[2] = address(gem);
        vm.expectRevert(PSMSwapRouter.PSMInvalidPath.selector);
        router.swap(recipient, 1, 1, path, new uint256[](2));
        assertEq(gem.balanceOf(address(router)), 100);
        assertEq(usdd.balanceOf(address(router)), 100 * RATIO);
    }

    function multiHop() internal returns (MockERC20 gemB, address[] memory path, uint256[] memory flags) {
        gemB = new MockERC20();
        PSMOutputFactory factory = new PSMOutputFactory();
        factory.set(0, pool);
        factory.set(1, new PSMOutputPool(usdd, gemB, 1e6));
        RouterParameters memory params;
        params.stableFactory = address(factory);
        router = new PSMOutputHarness(params);
        gem.mint(address(router), 100);
        usdd.mint(address(router), 100 * RATIO);
        gemB.mint(address(router), 50);
        path = new address[](3);
        path[0] = address(gem);
        path[1] = address(usdd);
        path[2] = address(gemB);
        flags = new uint256[](2);
        flags[1] = 1;
    }

    function test_threeAddressPathQuotesBothHopsAndRoundsUp() public {
        (MockERC20 gemB, address[] memory path, uint256[] memory flags) = multiHop();
        router.swap(recipient, 1e6 + 1, 2, path, flags);
        assertEq(gem.balanceOf(address(router)), 98);
        assertEq(usdd.balanceOf(address(router)), 100 * RATIO);
        assertEq(gemB.balanceOf(recipient), 2e6);
        assertEq(gemB.balanceOf(address(router)), 50);
    }

    function test_threeAddressPathEnforcesInputMaximum() public {
        (, address[] memory path, uint256[] memory flags) = multiHop();
        vm.expectRevert(PSMSwapRouter.PSMTooMuchRequested.selector);
        router.swap(recipient, 1e6 + 1, 1, path, flags);
        assertEq(gem.balanceOf(address(router)), 100);
    }

    function test_threeAddressPathOutputToRouter() public {
        (MockERC20 gemB, address[] memory path, uint256[] memory flags) = multiHop();
        router.swap(address(router), 1e6, 1, path, flags);
        assertEq(gemB.balanceOf(address(router)), 50 + 1e6);
        assertEq(usdd.balanceOf(address(router)), 100 * RATIO);
        assertEq(gem.balanceOf(address(router)), 99);
    }

    function test_threeAddressExactInputPropagatesAmounts() public {
        (MockERC20 gemB, address[] memory path, uint256[] memory flags) = multiHop();
        router.swapInput(recipient, 2, 2e6, path, flags);
        assertEq(gemB.balanceOf(recipient), 2e6);
        assertEq(gemB.balanceOf(address(router)), 50);
        assertEq(usdd.balanceOf(address(router)), 100 * RATIO);
        assertEq(gem.balanceOf(address(router)), 98);
    }

    function test_missingSecondExchange() public {
        (, address[] memory path, uint256[] memory flags) = multiHop();
        flags[1] = 2;
        vm.expectRevert(PSMSwapRouter.PSMInvalidExchange.selector);
        router.swap(recipient, 1e6, 1, path, flags);
        assertEq(gem.balanceOf(address(router)), 100);
    }

    function test_invalidPaths() public {
        for (uint256 length; length <= 3; length++) {
            if (length == 2) continue;
            vm.expectRevert(PSMSwapRouter.PSMInvalidPath.selector);
            router.swap(recipient, 1, 1, new address[](length), new uint256[](1));
        }
        address[] memory path = new address[](2);
        path[0] = address(gem);
        path[1] = address(usdd);
        vm.expectRevert(PSMSwapRouter.PSMInvalidPath.selector);
        router.swap(recipient, 1, 1, path, new uint256[](0));
        path[1] = path[0];
        vm.expectRevert(PSMSwapRouter.PSMInvalidPath.selector);
        router.swap(recipient, 1, 1, path, new uint256[](1));
    }
}
