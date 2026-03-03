// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface poolStable {
  function exchange(uint128 tokenIdIn,
                    uint128 tokenIdOut,
                    uint256 amountIn,
                    uint256 amountOutMin) external;

  function coins(uint256 tokenId) external view returns (address);
}

interface usdcPoolF {
  function exchange_underlying(int128 tokenIdIn,
                               int128 tokenIdOut,
                               uint256 amountIn,
                               uint256 amountOutMin) external;
}

