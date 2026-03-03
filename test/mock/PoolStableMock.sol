// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import {MockERC20} from "./MockERC20.sol";
import "./interfaces/IPoolStable.sol";

contract PoolStableMock {
  address[] tokens;

  constructor(address[] memory _tokens) {
    tokens = _tokens;
  }

  function exchange(uint128 tokenIdIn,
                    uint128 tokenIdOut,
                    uint256 amountIn,
                    uint256 amountOutMin) external  {
    uint256 amountOut = amountIn;
    require(amountOut >= amountOutMin, "amountMin not satisfied");
    require(tokens[uint256(tokenIdIn)] != address(0), "INVALID_ARGS_tokenIdIn");
    require(tokens[uint256(tokenIdOut)] != address(0), "INVALID_ARGS_tokenIdOut");
    address tokenIn = tokens[uint256(tokenIdIn)];
    address tokenOut = tokens[uint256(tokenIdOut)];
    require(MockERC20(tokenIn).allowance(msg.sender,address(this)) >= amountIn, "Insufficient Allowance");
    MockERC20(tokenIn).transferFrom(msg.sender,address(this),amountIn);
    require(MockERC20(tokenOut).balanceOf(address(this)) >= amountOut, "Insufficient Balance");
    MockERC20(tokenOut).transfer(msg.sender, amountOut);
    // next = (next + 1) % tokenOut.length;
  }

  function exchange_underlying(int128 tokenIdIn,
                               int128 tokenIdOut,
                               uint256 amountIn,
                               uint256 amountOutMin)
      external  {
    require(tokenIdIn != tokenIdOut
            && uint256(int256(tokenIdIn)) < tokens.length
            && uint256(int256(tokenIdOut)) < tokens.length, "INVALID_ARGS");
    uint256 amountOut = amountIn;
    require(amountOut >= amountOutMin, "amountMin not satisfied");
    MockERC20(tokens[uint256(int256(tokenIdIn))]).transferFrom(msg.sender,
                                                       address(this),
                                                       amountIn);
    MockERC20(tokens[uint256(int256(tokenIdOut))]).transfer(msg.sender, amountOut);
    // next = (next + 1) % tokenOut.length;
  }

  function coins(uint256 tokenId) external  view returns (address) {
    require(tokenId < tokens.length, "INVALID_ARGS");
    return tokens[tokenId];
  }
  
}
