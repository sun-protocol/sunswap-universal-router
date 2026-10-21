pragma solidity ^0.8.0;
import {IPsm} from "./interfaces/IPsm.sol";
import {IStableSwapFactory} from "../../../interfaces/IStableSwapFactory.sol";
import {RouterImmutables} from "../../../base/RouterImmutables.sol";
import {Permit2Payments} from "../../Permit2Payments.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ActionConstants} from "v4-periphery/src/libraries/ActionConstants.sol";

/// @title Router for PSM swaps
abstract contract PSMSwapRouter is RouterImmutables, Permit2Payments, Ownable2Step {
    using SafeTransferLib for ERC20;

    error PSMInvalidPath();
    error PSMInvalidExchange();
    error PSMTooLittleReceived();
    error PSMTooMuchRequested();
    address public immutable psmSwapFactory;

    constructor(address _psmSwapFactory) {
        psmSwapFactory = _psmSwapFactory;
    }

    /// @notice Performs a PSM exact input swap
    /// @param recipient The recipient of the output tokens
    /// @param amountIn The input amount, or CONTRACT_BALANCE to use the Router's entire input token balance
    /// @param amountOutMinimum The minimum acceptable output amount
    /// @param path The token addresses in swap order; the first and last tokens must differ
    /// @param flag The factory pool identifier for each hop
    /// @param payer The address supplying input tokens; ignored when amountIn is CONTRACT_BALANCE
    /// @return amountOut The output amount received by the Router from the swaps
    function psmSwapExactInput(
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address[] calldata path,
        uint256[] calldata flag,
        address payer
    ) internal returns (uint256 amountOut) {
        // Reject identical input/output tokens: the Router's balance delta would be
        // output minus spent input, rather than the actual output amount.
        if (
            path.length < 2 || flag.length != path.length - 1 || path[0] == path[path.length - 1]
        ) revert PSMInvalidPath();

        if (amountIn == ActionConstants.CONTRACT_BALANCE) {
            address tokenIn = path[0];
            amountIn = ERC20(tokenIn).balanceOf(address(this));
        } else if (payer != address(this)) {
            payOrPermit2Transfer(path[0], payer, address(this), amountIn);
        }
        // Measure the output received across all hops, excluding the Router's existing balance.
        ERC20 tokenOut = ERC20(path[path.length - 1]);
        uint256 balanceBefore = tokenOut.balanceOf(address(this));
        _psmSwap(amountIn, path, flag);

        amountOut = tokenOut.balanceOf(address(this)) - balanceBefore;

        if (amountOut < amountOutMinimum) revert PSMTooLittleReceived();
        if (recipient != address(this)) pay(address(tokenOut), recipient, amountOut);
    }

    /// @notice Performs a PSM exact output swap
    /// @dev Checks and transfers the actual output balance increase, including any excess caused by input rounding.
    /// @param recipient The recipient of the output tokens
    /// @param amountOut The requested output amount
    /// @param amountInMaximum The maximum acceptable input amount
    /// @param path The token addresses in swap order; the first and last tokens must differ
    /// @param flag The factory pool identifier for each hop
    /// @param payer The address supplying input tokens
    function psmSwapExactOutput(
        address recipient,
        uint256 amountOut,
        uint256 amountInMaximum,
        address[] calldata path,
        uint256[] calldata flag,
        address payer
    ) internal {
        if (
            path.length < 2 || flag.length != path.length - 1 || path[0] == path[path.length - 1]
        ) revert PSMInvalidPath();

        uint256 amountIn = _getAmountIn(amountOut, path, flag);
        if (amountIn > amountInMaximum) revert PSMTooMuchRequested();

        if (payer == address(this)) {
            if (ERC20(path[0]).balanceOf(address(this)) < amountIn) {
                revert PSMTooMuchRequested();
            }
        } else {
            payOrPermit2Transfer(path[0], payer, address(this), amountIn);
        }
        ERC20 tokenOut = ERC20(path[path.length - 1]);
        uint256 balanceBefore = tokenOut.balanceOf(address(this));
        _psmSwap(amountIn, path, flag);

        uint256 actualAmountOut = tokenOut.balanceOf(address(this)) - balanceBefore;

        if (actualAmountOut < amountOut) revert PSMTooLittleReceived();
        if (recipient != address(this)) pay(address(tokenOut), recipient, actualAmountOut);
    }

    /// @dev Quotes the path backwards. The caller must validate the path and flag lengths.
    function _getAmountIn(
        uint256 amountOut,
        address[] calldata path,
        uint256[] calldata flag
    ) private view returns (uint256 amountIn) {
        amountIn = amountOut;
        for (uint256 i = flag.length; i > 0;) {
            --i;
            amountIn = _getAmountInSingle(amountIn, path[i], path[i + 1], flag[i]);
        }
    }

    /// @dev Quotes one hop, rounding up when converting the output amount to input token units.
    function _getAmountInSingle(
        uint256 amountOut,
        address input,
        address output,
        uint256 flag
    ) private view returns (uint256 amountIn) {
        if (input == output) revert PSMInvalidPath();
        (, , address swapContract, uint256 psmRelativeDecimals) = IStableSwapFactory(psmSwapFactory).getStableInfo(
            input, output, flag
        );
        if (swapContract == address(0)) revert PSMInvalidExchange();
        if (input == IPsm(swapContract).usdd()) {
            amountIn = amountOut * psmRelativeDecimals;
        } else {
            amountIn = amountOut / psmRelativeDecimals;
            if (amountOut % psmRelativeDecimals != 0) amountIn += 1;
        }
    }

    /// @dev Executes hops in order, using each hop's output as the next hop's input.
    /// The caller must validate the path and flag lengths.
    /// @return amountOut The final hop's output calculated using the configured pool ratios
    function _psmSwap(
        uint256 amountIn,
        address[] calldata path,
        uint256[] calldata flag
    ) private returns (uint256 amountOut) {
        amountOut = amountIn;
        for (uint256 i; i < flag.length; i++) {
            amountOut = _psmSwapSingle(amountOut, path[i], path[i + 1], flag[i]);
        }
    }

    /// @dev Executes one hop with the Router as both payer and recipient.
    /// @return amountOut The output amount calculated using the pool's decimal conversion ratio
    function _psmSwapSingle(
        uint256 amountIn,
        address input,
        address output,
        uint256 flag
    ) private returns (uint256 amountOut) {
        if (input == output) revert PSMInvalidPath();
        (, , address swapContract, uint256 psmRelativeDecimals) = IStableSwapFactory(psmSwapFactory)
            .getStableInfo(input, output, flag);
        if (swapContract == address(0)) revert PSMInvalidExchange();

        if (input == IPsm(swapContract).usdd()) {
            ERC20(input).safeApprove(swapContract, amountIn);
            amountOut = amountIn / psmRelativeDecimals;
            IPsm(swapContract).buyGem(address(this), amountOut);
        } else {
            address gemJoin = IPsm(swapContract).gemJoin();
            ERC20(input).safeApprove(gemJoin, amountIn);
            IPsm(swapContract).sellGem(address(this), amountIn);
            amountOut = amountIn * psmRelativeDecimals;
        }
    }
}
