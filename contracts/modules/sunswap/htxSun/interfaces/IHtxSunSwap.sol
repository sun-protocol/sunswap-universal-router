pragma solidity ^0.8.0;

interface IHtxSunSwap {
    function swap(uint256 amount ,bool _forward)  external;
    function getAmountOut(uint256 amount ,bool _forward) external view returns(uint256 amountOut,uint256 fee);
    function TokenA() external view returns(address);
    function BASEAMOUNT() external view returns(uint256);
    function exchangeRate() external view returns(uint256);
    function feeRate() external view returns(uint256);
}