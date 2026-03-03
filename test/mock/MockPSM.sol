// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {MockERC20} from "./MockERC20.sol";

contract MockPSM {
    MockERC20 public TokenA;
    MockERC20 public TokenB;
    address public gemJoin;
    address public usdd;
    constructor(address _tokenA, address _tokenB) {
        TokenA = MockERC20(_tokenA);
        TokenB = MockERC20(_tokenB);
        usdd = _tokenA;
    }
    function sellGem(address usr, uint256 gemAmt) external {
        TokenB.transferFrom(usr, address(this), gemAmt);
        TokenA.transfer(usr, gemAmt);
    }

    function buyGem(address usr, uint256 gemAmt) external {
        TokenA.transferFrom(usr, address(this), gemAmt);
        TokenB.transfer(usr, gemAmt);
    }
    function setGemJoin(address _gemJoin) external {
        gemJoin = _gemJoin;
    }
}   