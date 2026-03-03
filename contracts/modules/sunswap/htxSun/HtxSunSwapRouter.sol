pragma solidity ^0.8.0;
import {IHtxSunSwap} from "./interfaces/IHtxSunSwap.sol";
import {IStableSwapFactory} from "../../../interfaces/IStableSwapFactory.sol";
import {RouterImmutables} from "../../../base/RouterImmutables.sol";
import {Permit2Payments} from "../../Permit2Payments.sol";
import {Constants} from "../../../libraries/Constants.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ActionConstants} from "v4-periphery/src/libraries/ActionConstants.sol";

abstract contract HtxSunSwapRouter is RouterImmutables, Permit2Payments {
    using SafeTransferLib for ERC20;

    error HtxSunInvalidPath();
    error HtxSunTooLittleReceived();
    error HtxSunTooMuchRequested();
    address public stableFactory;

    constructor(address _stableSwapFactory) {
        stableFactory = _stableSwapFactory;
    }

    /// @notice Performs a HTX-Sun exact input swap
    /// @param recipient The recipient of the output tokens
    /// @param amountIn The amount of input tokens for the trade
    /// @param amountOutMinimum The minimum desired amount of output tokens
    /// @param path The path of the trade as an array of token addresses
    function htxSunSwapExactInput(
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address[] calldata path,
        uint256[] calldata flag,
        address payer
    ) internal returns (uint256 amountOut) {
        if (path.length != 2) revert HtxSunInvalidPath();

        if ( amountIn != ActionConstants.CONTRACT_BALANCE && payer != address(this)) {
            payOrPermit2Transfer(path[0], payer, address(this), amountIn);
        }else if (amountIn == ActionConstants.CONTRACT_BALANCE) {
            address tokenIn = path[0];
            amountIn = ERC20(tokenIn).balanceOf(address(this));
        }
        (address input, address output) = (path[0], path[1]);
        ERC20 tokenOut = ERC20(path[1]);
        uint256 balanceBefore = tokenOut.balanceOf(address(this));
        (, , address swapContract,) = IStableSwapFactory(stableFactory).getStableInfo(input, output, flag[0]);
        ERC20(input).safeApprove(swapContract, amountIn);
        if(path[1] != address(IHtxSunSwap(swapContract).TokenA())) {
            IHtxSunSwap(swapContract).swap(amountIn, true);
        }else {
            IHtxSunSwap(swapContract).swap(amountIn, false);
        }
        
        amountOut = tokenOut.balanceOf(address(this)) - balanceBefore;

        if (amountOut < amountOutMinimum) revert HtxSunTooLittleReceived();
        if (recipient != address(this)) pay(address(tokenOut), recipient, amountOut);
    }

    function htxSunSwapExactOutput(
        address recipient,
        uint256 amountOut,
        uint256 amountInMaximum,
        address[] calldata path,
        uint256[] calldata flag,
        address payer
    ) internal {
        if (path.length != 2) revert HtxSunInvalidPath();

        (address input, address output) = (path[0], path[1]);
        (, , address swapContract,) = IStableSwapFactory(stableFactory).getStableInfo(input, output, flag[0]);
        uint256 amountIn = getAmountIn(amountOut, output, swapContract);
        if (amountIn > amountInMaximum) revert HtxSunTooMuchRequested();
        
        if (payer != address(this)) {
            payOrPermit2Transfer(path[0], payer, address(this), amountIn);
        }else {
            if (ERC20(path[0]).balanceOf(address(this)) < amountIn) {
                revert HtxSunTooMuchRequested();
            }
        }
        ERC20(input).safeApprove(swapContract, amountIn);
        if(path[1] != address(IHtxSunSwap(swapContract).TokenA())) {
            IHtxSunSwap(swapContract).swap(amountIn, true);
        }else {
            IHtxSunSwap(swapContract).swap(amountIn, false);
        }

        if (recipient != address(this)) pay(output, recipient, amountOut);
    }

    function getAmountIn(uint256 amountOut, address output, address swapContract) internal view returns (uint256 amountIn) {
        IHtxSunSwap htxSunSwap = IHtxSunSwap(swapContract);
        uint256 baseAmount = htxSunSwap.BASEAMOUNT();
        uint256 rate = htxSunSwap.exchangeRate();
        uint256 feeRate = htxSunSwap.feeRate();
        // a->b , amountOut = amountIn * (baseAmount - rate)/baseAmount * Rate
        // b->a , amountOut = amountIn * (baseAmount - rate)/baseAmount / Rate
        if(output == htxSunSwap.TokenA()) {
            // amountIn  = amountOut * Rate / (baseAmount - rate) * baseAmount
            amountIn =  amountOut * rate * baseAmount / (baseAmount - feeRate) / 1e18;
        }else {
            // amountIn  = amountOut / Rate / (baseAmount - rate) * baseAmount
           amountIn =  amountOut * baseAmount * 1e18 / rate / (baseAmount - feeRate);
        }
       
    }
}