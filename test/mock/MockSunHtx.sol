// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {MockERC20} from "./MockERC20.sol";

contract MockSunHtx {

    MockERC20 public TokenA;
    MockERC20 public TokenB;

    // address public operator;
    // address public treasury;
    
    uint256 public exchangeRate; // div 1e18
    uint256 public feeRate; //base 10000
    uint256 public TokenADecimal;
    uint256 public TokenBDecimal;
    uint256 constant public BASEAMOUNT = 10000;

    constructor(
        address _tokenA,  // tokenA = HTX
        address _tokenB,  // tokenB = SUN
        uint256 _exchangeRate,
        uint256 _feeRate
    ) {
        TokenA = MockERC20(_tokenA);
        TokenB = MockERC20(_tokenB);
        exchangeRate = _exchangeRate;
        feeRate = _feeRate;
        TokenADecimal = TokenA.decimals();
        TokenBDecimal = TokenB.decimals();
    }

    function swap(uint256 amount,bool _forward) external  {
        require(amount > 0,"amount must gt 0");
        (uint256 amountOut,) = getAmountOut(amount,_forward);
      if(_forward){
        require(TokenB.balanceOf(address(this)) >= amountOut, "Insufficient Token B balance");
        TokenA.transferFrom(msg.sender, address(this), amount);
        TokenB.transfer(msg.sender, amountOut);
      }else{
        require(TokenA.balanceOf(address(this)) >= amountOut, "Insufficient Token A balance");
        TokenB.transferFrom(msg.sender, address(this), amount);
        TokenA.transfer(msg.sender, amountOut);
      }
    }
    function getAmountOut(uint256 amount,bool _forward) public view returns (uint256 amountOut,uint256 fee){
        fee = amount * feeRate / BASEAMOUNT;
        if(_forward){
            amountOut = (amount - fee) * exchangeRate *  TokenBDecimal / TokenADecimal / 1e18;
        }else{
            amountOut = (amount - fee) * TokenADecimal * 1e18 / exchangeRate / TokenBDecimal;
        }
    }
    
}