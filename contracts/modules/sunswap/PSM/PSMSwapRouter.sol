pragma solidity ^0.8.0;
import {IPsm} from "./interfaces/IPsm.sol";
import {IStableSwapFactory} from "../../../interfaces/IStableSwapFactory.sol";
import {RouterImmutables} from "../../../base/RouterImmutables.sol";
import {Permit2Payments} from "../../Permit2Payments.sol";
import {Constants} from "../../../libraries/Constants.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ActionConstants} from "v4-periphery/src/libraries/ActionConstants.sol";

abstract contract PSMSwapRouter is RouterImmutables, Permit2Payments, Ownable2Step {
    using SafeTransferLib for ERC20;

    error PSMInvalidPath();
    error PSMInvalidExchange();
    error PSMTooLittleReceived();
    error PSMTooMuchRequested();
    address public psmSwapFactory;

    constructor(address _psmSwapFactory) {
        psmSwapFactory = _psmSwapFactory;
    }

    /// @notice Performs a PSM exact input swap
    /// @param recipient The recipient of the output tokens
    /// @param amountIn The amount of input tokens for the trade
    /// @param amountOutMinimum The minimum desired amount of output tokens
    /// @param path The path of the trade as an array of token addresses
    function psmSwapExactInput(
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address[] calldata path,
        uint256[] calldata flag,
        address payer
    ) internal returns (uint256 amountOut) {
        if (path.length < 2) revert PSMInvalidPath();
        if (amountIn != ActionConstants.CONTRACT_BALANCE && payer != address(this)) {
            payOrPermit2Transfer(path[0], payer, address(this), amountIn);
        } else if (amountIn == ActionConstants.CONTRACT_BALANCE) {
            address tokenIn = path[0];
            amountIn = ERC20(tokenIn).balanceOf(address(this));
        }
        // Perform the swap using the PSM contract
        ERC20 tokenOut = ERC20(path[path.length - 1]);
        uint256 balanceBefore = tokenOut.balanceOf(address(this));
        _psmSwap(amountIn, path, flag);

        amountOut = tokenOut.balanceOf(address(this)) - balanceBefore;

        if (amountOut < amountOutMinimum) revert PSMTooLittleReceived();
        if (recipient != address(this)) pay(address(tokenOut), recipient, amountOut);
    }

    /// @notice Performs a SunSwap v2 exact output swap
    /// @param recipient The recipient of the output tokens
    /// @param amountOut The amount of output tokens to receive for the trade
    /// @param amountInMaximum The maximum desired amount of input tokens
    /// @param path The path of the trade as an array of token addresses
    /// @param payer The address that will be paying the input

    function psmSwapExactOutput(
        address recipient,
        uint256 amountOut,
        uint256 amountInMaximum,
        address[] calldata path,
        uint256[] calldata flag,
        address payer
    ) internal {
        uint256 amountIn = getAmountIn(amountOut, psmSwapFactory, path, flag);
        if (amountIn > amountInMaximum) revert PSMTooMuchRequested();

        if (payer != address(this)) {
            payOrPermit2Transfer(path[0], payer, address(this), amountIn);
        } else {
            if (ERC20(path[0]).balanceOf(address(this)) < amountIn) {
                revert PSMTooMuchRequested();
            }
        }
        _psmSwap(amountIn, path, flag);
        ERC20 tokenOut = ERC20(path[path.length - 1]);
        uint256 received = tokenOut.balanceOf(address(this));
        if (recipient != address(this)) pay(address(tokenOut), recipient, received);
    }

    function getAmountIn(
        uint256 amountOut,
        address swapFactory,
        address[] calldata path,
        uint256[] calldata flag
    ) internal view returns (uint256 amountIn) {
        unchecked {
            (address input, address output) = (path[0], path[1]);
            (, , address swapContract, uint256 psmRelativeDecimals) = IStableSwapFactory(swapFactory).getStableInfo(
                input,
                output,
                flag[0]
            );
            if (swapContract == address(0)) revert PSMInvalidExchange();
            if (input == IPsm(swapContract).usdd()) {
                amountIn = amountOut * psmRelativeDecimals;
            } else {
                amountIn = amountOut / psmRelativeDecimals;
            }
        }
    }

    function _psmSwap(
        uint256 amountIn,
        address[] calldata path,
        uint256[] calldata flag
    ) private {
        unchecked {
            if (path.length - 1 != flag.length) revert PSMInvalidPath();

            for (uint256 i; i < flag.length; i++) {
                (address input, address output) = (path[i], path[i + 1]);
                (, , address swapContract, uint256 psmRelativeDecimals) = IStableSwapFactory(psmSwapFactory)
                    .getStableInfo(input, output, flag[i]);
                if (swapContract == address(0)) revert PSMInvalidExchange();
                // amountIn = ERC20(input).balanceOf(address(this));
                if (input == IPsm(swapContract).usdd()) {
                    ERC20(input).safeApprove(swapContract, amountIn);
                    IPsm(swapContract).buyGem(address(this), amountIn / psmRelativeDecimals);
                } else {
                    address gemJoin = IPsm(swapContract).gemJoin();
                    ERC20(input).safeApprove(gemJoin, amountIn);
                    IPsm(swapContract).sellGem(address(this), amountIn);
                }
            }
        }
    }
}
