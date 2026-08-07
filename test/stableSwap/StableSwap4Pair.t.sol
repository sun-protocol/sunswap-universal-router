// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ActionConstants} from "v4-periphery/src/libraries/ActionConstants.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {PoolStableMock} from "../mock/PoolStableMock.sol";
import {SwapInfoManager} from "src/modules/SwapInfoManager.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {UniversalRouter} from "src/UniversalRouter.sol";
import {Constants} from "src/libraries/Constants.sol";
import {Commands} from "src/libraries/Commands.sol";
import {RouterParameters} from "src/base/RouterImmutables.sol";
import {IStableSwapFactory} from "src/interfaces/IStableSwapFactory.sol";
import {IStableSwapInfo} from "src/interfaces/IStableSwapInfo.sol";
import {StableSwapRouter} from "src/modules/sunswap/stableswap/StableSwapRouter.sol";
import {Permit2SignatureHelpers} from "v4-periphery/test/shared/Permit2SignatureHelpers.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";
import {StructBuilder} from "permit2/test/utils/StructBuilder.sol";
import {SafeVault} from "src/SafeVault.sol";

contract StableSwap4PairTest is Test, DeployPermit2 {
    address constant RECIPIENT = address(10);
    uint256 constant AMOUNT = 1 ether;
    uint256 constant BALANCE = 100000 ether;
    ERC20 WETH9;
    IAllowanceTransfer permit2;
    address constant FROM = address(1234);

    address stablepool;
    address stableInfo;
    address token0;
    address token1;
    address token2;
    address token3;
    uint256[] flag;
    address admin = makeAddr("admin");
    SafeVault safeVault;

    UniversalRouter public router;

    function setUp() public {
        token0 = address(new MockERC20());
        token1 = address(new MockERC20());
        token2 = address(new MockERC20());
        token3 = address(new MockERC20());
        address[] memory tokens = new address[](4);
        tokens[0] = token0;
        tokens[1] = token1;
        tokens[2] = token2;
        tokens[3] = token3;
        flag = new uint256[](1);
        flag[0] = 0x11010; // 2 is the flag to indicate Stable
        // tokenOut is the amount of token1 received when swapping AMOUNT of token0,
        // then the amount of token0 received when swapping AMOUNT of token1, and so on.

        stablepool = address(new PoolStableMock(tokens));
        stableInfo = address(new SwapInfoManager());
        safeVault = new SafeVault(admin);
        // struct StableSwapPairInfo {
        //     address swapContract;
        //     address token0;
        //     address token1;
        //     address LPContract;
        // }
        IStableSwapFactory(stableInfo).setSwapPoolInfo(
            0x11010,
            address(stablepool),
            tokens,
            address(0),
            0
        );

        permit2 = IAllowanceTransfer(deployPermit2());
        WETH9 = new MockERC20();
        RouterParameters memory params = RouterParameters({
            permit2: address(permit2),
            weth9: address(WETH9),
            v1Factory: address(0),
            v2Factory: address(0),
            v3Factory: address(0),
            v3Deployer: address(0),
            v2InitCodeHash: bytes32(0),
            v3InitCodeHash: bytes32(0),
            stableFactory: stableInfo,
            
            v4Vault: address(0),
            v4ClPoolManager: address(0),
            v3NFTPositionManager: address(0),
            v4ClPositionManager: address(0),
            safeVault: address(safeVault)
        });
        router = new UniversalRouter(params);

        // pair doesn't exist, revert to keep this test simple without adding to lp etc

        vm.startPrank(FROM);
        deal(FROM, BALANCE);
        deal(token0, FROM, BALANCE);
        deal(token1, FROM, BALANCE);
        deal(token2, FROM, BALANCE);
        deal(token3, FROM, BALANCE);
        deal(token0, stablepool, BALANCE);
        deal(token1, stablepool, BALANCE);
        deal(token2, stablepool, BALANCE);
        deal(token3, stablepool, BALANCE);
        ERC20(token0).approve(address(permit2), type(uint256).max);
        ERC20(token1).approve(address(permit2), type(uint256).max);
        ERC20(token2).approve(address(permit2), type(uint256).max);
        ERC20(token3).approve(address(permit2), type(uint256).max);

        permit2.approve(token0, address(router), type(uint160).max, type(uint48).max);
        permit2.approve(token1, address(router), type(uint160).max, type(uint48).max);
        permit2.approve(token2, address(router), type(uint160).max, type(uint48).max);
        permit2.approve(token3, address(router), type(uint160).max, type(uint48).max);
    }

    function test_SetStableSwap_OnlyOwner() public {
        address bob = makeAddr("bob");
        address newStableSwapFactory = makeAddr("newStableSwapFactory");

        // random user cannot set
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        vm.startPrank(bob);
        router.setStableSwap(newStableSwapFactory);
        vm.stopPrank();

        // owner can set - before
        assertEq(router.stableSwapFactory(), stableInfo);

        // owner can set
        vm.prank(router.owner());
        vm.expectEmit();
        emit StableSwapRouter.SetStableSwap(newStableSwapFactory);
        router.setStableSwap(newStableSwapFactory);

        // owner can set - after
        assertEq(router.stableSwapFactory(), newStableSwapFactory);
    }

    function test_SetStableSwap_EmptyAddress() public {
        vm.startPrank(router.owner());

        vm.expectRevert();
        router.setStableSwap(address(0));

        vm.stopPrank();
    }

    function test_stableSwap_ExactInput0For1() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));

        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token0;
        path[1] = token1;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, true);

        router.execute(commands, inputs, block.timestamp + 100);
        vm.snapshotGasLastCall("test_stableSwap_ExactInput0For1");
        assertEq(ERC20(token0).balanceOf(FROM), BALANCE - AMOUNT);
        assertGt(ERC20(token1).balanceOf(FROM), BALANCE);
    }

    function test_stableSwap_ExactInput0For2() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));

        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token0;
        path[1] = token2;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, true);

        router.execute(commands, inputs, block.timestamp + 100);
        vm.snapshotGasLastCall("test_stableSwap_ExactInput0For1");
        assertEq(ERC20(token0).balanceOf(FROM), BALANCE - AMOUNT);
        assertGt(ERC20(token2).balanceOf(FROM), BALANCE);
    }

    function test_stableSwap_ExactInput0For3() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));

        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token0;
        path[1] = token3;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, true);

        router.execute(commands, inputs, block.timestamp + 100);
        vm.snapshotGasLastCall("test_stableSwap_ExactInput0For1");
        assertEq(ERC20(token0).balanceOf(FROM), BALANCE - AMOUNT);
        assertGt(ERC20(token3).balanceOf(FROM), BALANCE);
    }

    function test_stableSwap_ExactInput1For0() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));

        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token1;
        path[1] = token0;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, true);

        router.execute(commands, inputs, block.timestamp + 100);
        vm.snapshotGasLastCall("test_stableSwap_ExactInput1For0");
        assertEq(ERC20(token1).balanceOf(FROM), BALANCE - AMOUNT);
        assertGt(ERC20(token0).balanceOf(FROM), BALANCE);
    }

    function test_stableSwap_ExactInput1For2() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));

        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token1;
        path[1] = token2;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, true);

        router.execute(commands, inputs, block.timestamp + 100);
        vm.snapshotGasLastCall("test_stableSwap_ExactInput1For0");
        assertEq(ERC20(token1).balanceOf(FROM), BALANCE - AMOUNT);
        assertGt(ERC20(token2).balanceOf(FROM), BALANCE);
    }

    function test_stableSwap_ExactInput1For3() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));

        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token1;
        path[1] = token3;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, true);

        router.execute(commands, inputs, block.timestamp + 100);
        vm.snapshotGasLastCall("test_stableSwap_ExactInput1For0");
        assertEq(ERC20(token1).balanceOf(FROM), BALANCE - AMOUNT);
        assertGt(ERC20(token3).balanceOf(FROM), BALANCE);
    }

    function test_stableSwap_ExactInput2For0() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));

        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token2;
        path[1] = token0;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, true);

        router.execute(commands, inputs, block.timestamp + 100);
        vm.snapshotGasLastCall("test_stableSwap_ExactInput1For0");
        assertEq(ERC20(token2).balanceOf(FROM), BALANCE - AMOUNT);
        assertGt(ERC20(token0).balanceOf(FROM), BALANCE);
    }

    function test_stableSwap_ExactInput2For1() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));

        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token2;
        path[1] = token1;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, true);

        router.execute(commands, inputs, block.timestamp + 100);
        vm.snapshotGasLastCall("test_stableSwap_ExactInput0For1");
        assertEq(ERC20(token2).balanceOf(FROM), BALANCE - AMOUNT);
        assertGt(ERC20(token1).balanceOf(FROM), BALANCE);
    }

    function test_stableSwap_ExactInput2For3() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));

        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token2;
        path[1] = token3;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, true);

        router.execute(commands, inputs, block.timestamp + 100);
        vm.snapshotGasLastCall("test_stableSwap_ExactInput0For1");
        assertEq(ERC20(token2).balanceOf(FROM), BALANCE - AMOUNT);
        assertGt(ERC20(token3).balanceOf(FROM), BALANCE);
    }

    function test_stableSwap_ExactInput3For0() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));

        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token3;
        path[1] = token0;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, true);

        router.execute(commands, inputs, block.timestamp + 100);
        vm.snapshotGasLastCall("test_stableSwap_ExactInput1For0");
        assertEq(ERC20(token3).balanceOf(FROM), BALANCE - AMOUNT);
        assertGt(ERC20(token0).balanceOf(FROM), BALANCE);
    }

    function test_stableSwap_ExactInput3For1() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));

        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token3;
        path[1] = token1;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, true);

        router.execute(commands, inputs, block.timestamp + 100);
        vm.snapshotGasLastCall("test_stableSwap_ExactInput0For1");
        assertEq(ERC20(token3).balanceOf(FROM), BALANCE - AMOUNT);
        assertGt(ERC20(token1).balanceOf(FROM), BALANCE);
    }

    function test_stableSwap_ExactInput3For2() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));

        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token3;
        path[1] = token2;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, true);

        router.execute(commands, inputs, block.timestamp + 100);
        vm.snapshotGasLastCall("test_stableSwap_ExactInput0For1");
        assertEq(ERC20(token3).balanceOf(FROM), BALANCE - AMOUNT);
        assertGt(ERC20(token2).balanceOf(FROM), BALANCE);
    }

    function test_stableSwap_exactInput0For1FromRouter() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));
        deal(token0, address(router), AMOUNT);
        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token0;
        path[1] = token1;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, false);

        router.execute(commands, inputs, block.timestamp + 100);
        assertEq(ERC20(token0).balanceOf(FROM), BALANCE); // no token0 taken from user, taken from router
        assertGt(ERC20(token1).balanceOf(FROM), BALANCE); // token1 received
    }

    function test_stableSwap_exactInput0For2FromRouter() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));
        deal(token0, address(router), AMOUNT);
        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token0;
        path[1] = token2;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, false);

        router.execute(commands, inputs, block.timestamp + 100);
        assertEq(ERC20(token0).balanceOf(FROM), BALANCE); // no token0 taken from user, taken from router
        assertGt(ERC20(token2).balanceOf(FROM), BALANCE); // token1 received
    }

    function test_stableSwap_exactInput0For3FromRouter() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));
        deal(token0, address(router), AMOUNT);
        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token0;
        path[1] = token3;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, false);

        router.execute(commands, inputs, block.timestamp + 100);
        assertEq(ERC20(token0).balanceOf(FROM), BALANCE); // no token0 taken from user, taken from router
        assertGt(ERC20(token3).balanceOf(FROM), BALANCE); // token1 received
    }

    function test_stableSwap_exactInput1For0FromRouter() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));
        deal(token1, address(router), AMOUNT);
        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token1;
        path[1] = token0;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, false);

        router.execute(commands, inputs, block.timestamp + 100);
        assertGt(ERC20(token0).balanceOf(FROM), BALANCE); // token0 received
        assertEq(ERC20(token1).balanceOf(FROM), BALANCE); // no token1 taken from user, taken from router
    }

    function test_stableSwap_exactInput1For2FromRouter() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));
        deal(token1, address(router), AMOUNT);
        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token1;
        path[1] = token2;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, false);

        router.execute(commands, inputs, block.timestamp + 100);
        assertGt(ERC20(token2).balanceOf(FROM), BALANCE); // token0 received
        assertEq(ERC20(token1).balanceOf(FROM), BALANCE); // no token1 taken from user, taken from router
    }

    function test_stableSwap_exactInput1For3FromRouter() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));
        deal(token1, address(router), AMOUNT);
        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token1;
        path[1] = token3;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, false);

        router.execute(commands, inputs, block.timestamp + 100);
        assertGt(ERC20(token3).balanceOf(FROM), BALANCE); // token0 received
        assertEq(ERC20(token1).balanceOf(FROM), BALANCE); // no token1 taken from user, taken from router
    }

    function test_stableSwap_exactInput2For0FromRouter() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));
        deal(token2, address(router), AMOUNT);
        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token2;
        path[1] = token0;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, false);

        router.execute(commands, inputs, block.timestamp + 100);
        assertGt(ERC20(token0).balanceOf(FROM), BALANCE); // token0 received
        assertEq(ERC20(token2).balanceOf(FROM), BALANCE); // no token1 taken from user, taken from router
    }

    function test_stableSwap_exactInput2For1FromRouter() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));
        deal(token2, address(router), AMOUNT);
        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token2;
        path[1] = token1;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, false);

        router.execute(commands, inputs, block.timestamp + 100);
        assertEq(ERC20(token2).balanceOf(FROM), BALANCE); // no token0 taken from user, taken from router
        assertGt(ERC20(token1).balanceOf(FROM), BALANCE); // token1 received
    }

    function test_stableSwap_exactInput2For3FromRouter() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));
        deal(token2, address(router), AMOUNT);
        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token2;
        path[1] = token3;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, false);

        router.execute(commands, inputs, block.timestamp + 100);
        assertEq(ERC20(token2).balanceOf(FROM), BALANCE); // no token0 taken from user, taken from router
        assertGt(ERC20(token3).balanceOf(FROM), BALANCE); // token3 received
    }

    function test_stableSwap_exactInput3For0FromRouter() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));
        deal(token3, address(router), AMOUNT);
        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token3;
        path[1] = token0;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, false);

        router.execute(commands, inputs, block.timestamp + 100);
        assertGt(ERC20(token0).balanceOf(FROM), BALANCE); // token0 received
        assertEq(ERC20(token3).balanceOf(FROM), BALANCE); // no token1 taken from user, taken from router
    }

    function test_stableSwap_exactInput3For1FromRouter() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));
        deal(token3, address(router), AMOUNT);
        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token3;
        path[1] = token1;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, false);

        router.execute(commands, inputs, block.timestamp + 100);
        assertGt(ERC20(token1).balanceOf(FROM), BALANCE); // token0 received
        assertEq(ERC20(token3).balanceOf(FROM), BALANCE); // no token1 taken from user, taken from router
    }

    function test_stableSwap_exactInput3For2FromRouter() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));
        deal(token3, address(router), AMOUNT);
        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token3;
        path[1] = token2;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, false);

        router.execute(commands, inputs, block.timestamp + 100);
        assertGt(ERC20(token2).balanceOf(FROM), BALANCE); // token0 received
        assertEq(ERC20(token3).balanceOf(FROM), BALANCE); // no token1 taken from user, taken from router
    }

    function test_stableSwap_exactInput0For1_StableTooLittleReceived() public {
        // have some AMOUNT * 2 token1 in router, assumed from previous commands
        deal(token1, address(router), AMOUNT * 2);

        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_IN)));
        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token0;
        path[1] = token1;
        bytes[] memory inputs = new bytes[](1);
        // set minOut as amount * 2 which is not achievable
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, AMOUNT * 2, path, flag, true);

        vm.expectRevert(StableSwapRouter.StableTooLittleReceived.selector);
        router.execute(commands, inputs, block.timestamp + 100);
    }

    // function test_stableSwap_exactOutput0For1() public {
    //     bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_OUT)));

    //     // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
    //     address[] memory path = new address[](2);
    //     path[0] = token0;
    //     path[1] = token1;
    //     bytes[] memory inputs = new bytes[](1);
    //     inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, type(uint256).max, path, 1, true);

    //     router.execute(commands, inputs);
    //     assertLt(ERC20(token0).balanceOf(FROM), BALANCE);
    //     assertGe(ERC20(token1).balanceOf(FROM), BALANCE + AMOUNT);
    // }

    // function test_stableSwap_exactOutput1For0() public {
    //     bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_OUT)));

    //     // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
    //     address[] memory path = new address[](2);
    //     path[0] = token1;
    //     path[1] = token0;
    //     bytes[] memory inputs = new bytes[](1);
    //     inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, type(uint256).max, path, 1, true);

    //     router.execute(commands, inputs);
    //     assertLt(ERC20(token1).balanceOf(FROM), BALANCE);
    //     assertGe(ERC20(token0).balanceOf(FROM), BALANCE + AMOUNT);
    // }

    // function test_stableSwap_exactOutput0For1FromRouter() public {
    //     bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_OUT)));
    //     deal(token0, address(router), BALANCE);

    //     // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
    //     address[] memory path = new address[](2);
    //     path[0] = token0;
    //     path[1] = token1;
    //     bytes[] memory inputs = new bytes[](1);
    //     inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, type(uint256).max, path, 1, false);

    //     router.execute(commands, inputs);
    //     assertEq(ERC20(token0).balanceOf(FROM), BALANCE); // no token0 taken from user, taken from router
    //     assertGe(ERC20(token1).balanceOf(FROM), BALANCE + AMOUNT);
    // }

    // function test_stableSwap_exactOutput1For0FromRouter() public {
    //     bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.STABLE_SWAP_EXACT_OUT)));
    //     deal(token1, address(router), BALANCE);

    //     // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
    //     address[] memory path = new address[](2);
    //     path[0] = token1;
    //     path[1] = token0;
    //     bytes[] memory inputs = new bytes[](1);
    //     inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, type(uint256).max, path, 1, false);

    //     router.execute(commands, inputs);
    //     assertGe(ERC20(token0).balanceOf(FROM), BALANCE + AMOUNT);
    //     assertEq(ERC20(token1).balanceOf(FROM), BALANCE); // no token1 taken from user, taken from router
    // }
    // function flag() internal pure override returns (uint256[] memory pairFlag) {
    //     pairFlag = new uint256[](1);
    //     pairFlag[0] = 2; // 2 is the flag to indicate StableSwapTwoPool
    // }
}
