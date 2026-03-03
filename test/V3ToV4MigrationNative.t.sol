// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test, console} from "forge-std/Test.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {IVault} from "v4-core/src/interfaces/IVault.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {ICLPoolManager} from "v4-core/src/interfaces/ICLPoolManager.sol";

import {FixedPoint96} from "v4-core/src/libraries/FixedPoint96.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {CLPoolParametersHelper} from "v4-core/src/libraries/CLPoolParametersHelper.sol";

import {ActionConstants} from "v4-periphery/src/libraries/ActionConstants.sol";
import {Plan, Planner} from "v4-periphery/src/libraries/Planner.sol";
import {CLPositionManager} from "v4-periphery/src/pool-cl/CLPositionManager.sol";
import {CLPositionDescriptorOffChain} from "v4-periphery/src/pool-cl/CLPositionDescriptorOffChain.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {IV3NonfungiblePositionManager} from "v4-periphery/src/interfaces/external/IV3NonfungiblePositionManager.sol";
import {IERC721Permit} from "v4-periphery/src/interfaces/IERC721Permit.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {OldVersionHelper} from "v4-periphery/test/helpers/OldVersionHelper.sol";
import {Constants} from "src/libraries/Constants.sol";

import {IUniversalRouter} from "src/interfaces/IUniversalRouter.sol";
import {Commands} from "src/libraries/Commands.sol";
import {RouterParameters} from "src/base/RouterImmutables.sol";
import {Dispatcher} from "src/base/Dispatcher.sol";
import {UniversalRouter} from "src/UniversalRouter.sol";
import {BaseSunSwapV4} from "./v4/BaseSunSwapV4.sol";
import {SafeVault} from "src/SafeVault.sol";

interface ISunSwapV3LikePairFactory {
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address pool);
}

/// @dev Test simplified, assume weth-token pair is already broken and token reside in universal router
contract V3ToV4MigrationNativeTest is BaseSunSwapV4, OldVersionHelper {
    using CLPoolParametersHelper for bytes32;
    using Planner for Plan;

    MockERC20 token0;
    MockERC20 token1;
    WETH weth = new WETH();
    address alice;
    uint256 alicePK;

    // v4 related
    IVault vault;
    PoolManager poolManager;
    CLPositionManager clPositionManager;
    IAllowanceTransfer permit2;
    UniversalRouter router;
    PoolKey clPoolKey;
    SafeVault safeVault;

    uint24 constant ACTIVE_ID_1_1 = 2**23; // where token0 and token1 price is the same
    uint160 constant SQRT_PRICE_1_1 = uint160(1 * FixedPoint96.Q96); // price 1
    address admin = makeAddr("admin");

    function setUp() public {
        (alice, alicePK) = makeAddrAndKey("ALICE");

        initializeTokens();
        vm.label(Currency.unwrap(currency1), "token1");
        token1 = MockERC20(Currency.unwrap(currency1));

        permit2 = IAllowanceTransfer(deployPermit2());
        safeVault = new SafeVault(admin);
        ///////////////////////////////////
        ///////// v4 setup //////////
        ///////////////////////////////////

        poolManager = new PoolManager();

        CLPositionDescriptorOffChain pd = new CLPositionDescriptorOffChain("https://sun.io/positions/");
        clPositionManager = new CLPositionManager(
            poolManager,
            poolManager,
            permit2,
            100_000,
            pd,
            IWETH9(address(weth))
        );
        _approvePermit2ForCurrency(address(this), currency1, address(clPositionManager), permit2);

        clPoolKey = PoolKey({
            currency0: CurrencyLibrary.NATIVE,
            currency1: currency1,
            hooks: IHooks(address(0)),
            fee: uint24(3000),
            parameters: bytes32(0).setTickSpacing(10)
        });
        poolManager.initialize(clPoolKey, SQRT_PRICE_1_1);

        ///////////////////////////////////
        //////////// Router setup /////////////
        ///////////////////////////////////
        RouterParameters memory params = RouterParameters({
            permit2: address(permit2),
            weth9: address(weth),
            v1Factory: address(0),
            v2Factory: address(0),
            v3Factory: address(0),
            v3Deployer: address(0),
            v2InitCodeHash: bytes32(0),
            v3InitCodeHash: bytes32(0),
            stableFactory: address(0),
            stableInfo: address(0),
            v4Vault: address(poolManager),
            v4ClPoolManager: address(poolManager),
            v3NFTPositionManager: address(0),
            v4ClPositionManager: address(clPositionManager),
            safeVault: address(safeVault)
        });
        router = new UniversalRouter(params);
        _approvePermit2ForCurrency(alice, currency1, address(router), permit2);
    }

    /// @dev Assume weth/token1 is aready in universal router from v3 removal liquidity
    ///         then add liquidity to v4 cl and sweep remaining token
    // function test_v4CLPositionmanager_Mint_Native() public {
    //     // assume weth/token1 is in universal router
    //     vm.deal(address(this), 10 ether);
    //     weth.deposit{value: 10 ether}();
    //     weth.transfer(address(router), 10 ether);
    //     token1.mint(address(router), 10 ether);

    //     // prep position manager action: mint/ settle/ settle
    //     Plan memory planner = Planner.init();
    //     planner.add(Actions.CL_MINT_POSITION, abi.encode(clPoolKey, -120, 120, 1 ether, 10 ether, 10 ether, alice, ""));
    //     planner.add(Actions.SETTLE, abi.encode(clPoolKey.currency0, ActionConstants.OPEN_DELTA, false)); // deduct from universal router
    //     planner.add(Actions.SETTLE, abi.encode(clPoolKey.currency1, ActionConstants.OPEN_DELTA, false)); // deduct from universal router
    //     planner.add(Actions.SWEEP, abi.encode(clPoolKey.currency0, alice));
    //     planner.add(Actions.SWEEP, abi.encode(clPoolKey.currency1, alice));

    //     // prep universal router actions
    //     bytes memory commands = abi.encodePacked(
    //         bytes1(uint8(Commands.UNWRAP_WETH)),
    //         bytes1(uint8(Commands.SWEEP)),
    //         bytes1(uint8(Commands.V4_CL_POSITION_CALL))
    //     );
    //     bytes[] memory inputs = new bytes[](3);
    //     inputs[0] = abi.encode(address(router), 10 ether); // get native eth to router
    //     inputs[1] = abi.encode(token1, address(clPositionManager), 0); // send token1 to clPositionmanager
    //     inputs[2] =
    //         abi.encodePacked(IPositionManager.modifyLiquidities.selector, abi.encode(planner.encode(), block.timestamp));

    //     vm.prank(alice);
    //     router.execute(commands, inputs);
    //     vm.snapshotGasLastCall("test_v4CLPositionmanager_Mint_Native");

    //     // verify remaining balance sent back to alice
    //     assertEq(alice.balance, 9994018262239490337);
    //     assertEq(token1.balanceOf(address(alice)), 9994018262239490337);
    //     assertEq(clPositionManager.ownerOf(1), alice);
    // }
}
