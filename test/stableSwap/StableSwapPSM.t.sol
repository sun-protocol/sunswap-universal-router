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
import {PSMSwapRouter} from "src/modules/sunswap/PSM/PSMSwapRouter.sol";
import {Permit2SignatureHelpers} from "v4-periphery/test/shared/Permit2SignatureHelpers.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";
import {StructBuilder} from "permit2/test/utils/StructBuilder.sol";
import {MockPSM} from "../mock/MockPSM.sol";
import {SafeVault} from "src/SafeVault.sol";

contract StableSwapPSMTest is Test, DeployPermit2 {
    address constant RECIPIENT = address(10);
    uint256 constant AMOUNT = 1 ether;
    uint256 constant BALANCE = 100000 ether;
    ERC20 WETH9;
    IAllowanceTransfer permit2;
    address constant FROM = address(1234);
    MockPSM public psmpool;

    address stablepool;
    address stableInfo;
    address token0;
    address token1;
    uint256[] flag;

    UniversalRouter public router;
    address admin = makeAddr("admin");
    SafeVault safeVault;

    function setUp() public {
        token0 = address(new MockERC20());
        token1 = address(new MockERC20());
        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        flag = new uint256[](1);
        flag[0] = 0x10010;
        // tokenOut is the amount of token1 received when swapping AMOUNT of token0,
        // then the amount of token0 received when swapping AMOUNT of token1, and so on.

        psmpool = new MockPSM(token0, token1);
        stablepool = address(psmpool);
        psmpool.setGemJoin(stablepool);

        stableInfo = address(new SwapInfoManager());
        // struct StableSwapPairInfo {
        //     address swapContract;
        //     address token0;
        //     address token1;
        //     address LPContract;
        // }
        IStableSwapFactory(stableInfo).setPSMSwapPairInfo(stablepool, token0, token1, address(0), 1);

        permit2 = IAllowanceTransfer(deployPermit2());
        WETH9 = new MockERC20();
        safeVault = new SafeVault(admin);
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
            stableInfo: address(0),
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
        deal(token0, stablepool, BALANCE);
        deal(token1, stablepool, BALANCE);
        deal(token0, address(router), BALANCE);
        deal(token1, address(router), BALANCE);
        ERC20(token0).approve(address(permit2), type(uint256).max);
        ERC20(token1).approve(address(permit2), type(uint256).max);
        permit2.approve(token0, address(router), type(uint160).max, type(uint48).max);
        permit2.approve(token1, address(router), type(uint160).max, type(uint48).max);
    }

    function test_SetStableSwap_OnlyOwner() public {
        address bob = makeAddr("bob");
        address newStableSwapFactory = makeAddr("newStableSwapFactory");
        address newStableSwapInfo = makeAddr("newStableSwapInfo");

        // random user cannot set
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        vm.startPrank(bob);
        router.setStableSwap(newStableSwapFactory, newStableSwapInfo);
        vm.stopPrank();

        // owner can set - before
        assertEq(router.stableSwapFactory(), stableInfo);
        assertEq(router.stableSwapInfo(), address(0));

        // owner can set
        vm.prank(router.owner());
        vm.expectEmit();
        emit StableSwapRouter.SetStableSwap(newStableSwapFactory, newStableSwapInfo);
        router.setStableSwap(newStableSwapFactory, newStableSwapInfo);

        // owner can set - after
        assertEq(router.stableSwapFactory(), newStableSwapFactory);
        assertEq(router.stableSwapInfo(), newStableSwapInfo);
    }

    function test_SetStableSwap_EmptyAddress() public {
        address newStableSwapFactory = makeAddr("newStableSwapFactory");
        address newStableSwapInfo = makeAddr("newStableSwapInfo");
        vm.startPrank(router.owner());

        // set empty address for factory
        vm.expectRevert();
        router.setStableSwap(address(0), newStableSwapInfo);

        // set empty address for info
        vm.expectRevert();
        router.setStableSwap(newStableSwapFactory, address(0));

        vm.stopPrank();
    }

    function test_stableSwap_ExactInput0For1() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.PSM_SWAP_EXACT_IN)));

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
        assertEq(ERC20(token0).balanceOf(address(safeVault)), BALANCE);
        assertEq(ERC20(token1).balanceOf(address(safeVault)), BALANCE);
        
    } 


    function test_stableSwap_ExactInput1For0() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.PSM_SWAP_EXACT_IN)));

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
        assertEq(ERC20(token0).balanceOf(address(safeVault)), BALANCE);
        assertEq(ERC20(token1).balanceOf(address(safeVault)), BALANCE);
    }

    function test_stableSwap_exactInput0For1FromRouter() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.PSM_SWAP_EXACT_IN)));
        // deal(token0, address(router), AMOUNT);
        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token0;
        path[1] = token1;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, false);

        router.execute(commands, inputs, block.timestamp + 100);
        assertEq(ERC20(token0).balanceOf(FROM), BALANCE); // no token0 taken from user, taken from router
        assertGt(ERC20(token1).balanceOf(FROM), BALANCE); // token1 received
        assertEq(ERC20(token0).balanceOf(address(safeVault)), BALANCE - AMOUNT);
        assertEq(ERC20(token1).balanceOf(address(safeVault)), BALANCE);
    }

    function test_stableSwap_exactInput1For0FromRouter() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.PSM_SWAP_EXACT_IN)));
        // deal(token1, address(router), AMOUNT);
        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token1;
        path[1] = token0;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, 0, path, flag, false);

        router.execute(commands, inputs, block.timestamp + 100);
        assertGt(ERC20(token0).balanceOf(FROM), BALANCE); // token0 received
        assertEq(ERC20(token1).balanceOf(FROM), BALANCE); // no token1 taken from user, taken from router
        assertEq(ERC20(token0).balanceOf(address(safeVault)), BALANCE);
        assertEq(ERC20(token1).balanceOf(address(safeVault)), BALANCE - AMOUNT);
    }

    function test_stableSwap_exactInput0For1_StableTooLittleReceived() public {
        // have some AMOUNT * 2 token1 in router, assumed from previous commands
        deal(token1, address(router), AMOUNT * 2);

        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.PSM_SWAP_EXACT_IN)));
        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token0;
        path[1] = token1;
        bytes[] memory inputs = new bytes[](1);
        // set minOut as amount * 2 which is not achievable
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, AMOUNT * 2, path, flag, true);

        vm.expectRevert(PSMSwapRouter.PSMTooLittleReceived.selector);
        router.execute(commands, inputs, block.timestamp + 100);
    }

    function test_stableSwap_ExactOutput0For1() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.PSM_SWAP_EXACT_OUT)));

        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token0;
        path[1] = token1;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, AMOUNT, path, flag, true);

        router.execute(commands, inputs, block.timestamp + 100);
        vm.snapshotGasLastCall("test_stableSwap_ExactInput0For1");
        assertEq(ERC20(token0).balanceOf(FROM), BALANCE - AMOUNT);
        assertGt(ERC20(token1).balanceOf(FROM), BALANCE);
    }

    function test_stableSwap_ExactOutput1For0() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.PSM_SWAP_EXACT_OUT)));

        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token1;
        path[1] = token0;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, AMOUNT, path, flag, true);

        router.execute(commands, inputs, block.timestamp + 100);
        vm.snapshotGasLastCall("test_stableSwap_ExactInput1For0");
        assertEq(ERC20(token1).balanceOf(FROM), BALANCE - AMOUNT);
        assertGt(ERC20(token0).balanceOf(FROM), BALANCE);
    }

    function test_stableSwap_exactOutput0For1FromRouter() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.PSM_SWAP_EXACT_OUT)));
        deal(token0, address(router), AMOUNT);
        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token0;
        path[1] = token1;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, AMOUNT, path, flag, false);

        router.execute(commands, inputs, block.timestamp + 100);
        assertEq(ERC20(token0).balanceOf(FROM), BALANCE); // no token0 taken from user, taken from router
        assertGt(ERC20(token1).balanceOf(FROM), BALANCE); // token1 received
    }

    function test_stableSwap_exactOutput1For0FromRouter() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.PSM_SWAP_EXACT_OUT)));
        deal(token1, address(router), AMOUNT);
        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token1;
        path[1] = token0;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, AMOUNT, path, flag, false);

        router.execute(commands, inputs, block.timestamp + 100);
        assertGt(ERC20(token0).balanceOf(FROM), BALANCE); // token0 received
        assertEq(ERC20(token1).balanceOf(FROM), BALANCE); // no token1 taken from user, taken from router
    }

    function test_stableSwap_exactOutput0For1_StableTooLittleReceived() public {
        // have some AMOUNT * 2 token1 in router, assumed from previous commands
        deal(token1, address(router), AMOUNT * 2);

        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.PSM_SWAP_EXACT_OUT)));
        // equivalent: abi.decode(inputs, (address, uint256, uint256, address[], uint256[], bool)
        address[] memory path = new address[](2);
        path[0] = token0;
        path[1] = token1;
        bytes[] memory inputs = new bytes[](1);
        // set minOut as amount * 2 which is not achievable
        inputs[0] = abi.encode(ActionConstants.MSG_SENDER, AMOUNT, AMOUNT - 1, path, flag, true);

        vm.expectRevert(PSMSwapRouter.PSMTooMuchRequested.selector);
        router.execute(commands, inputs, block.timestamp + 100);
    }
}
