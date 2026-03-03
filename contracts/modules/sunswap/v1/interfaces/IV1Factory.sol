// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
interface IV1Factory {
    function getExchange(address token) external view returns (address payable);
}