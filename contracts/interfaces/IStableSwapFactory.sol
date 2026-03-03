// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStableSwapFactory {
    function getStableInfo(
        address input,
        address output,
        uint256 flag
    )
        external
        view
        returns (
            uint256 k,
            uint256 j,
            address swapContract,
            uint256 extension
        );

    function setSwapPoolInfo(
        uint256 flag,
        address swapContract,
        address[] calldata tokens,
        address LPContract,
        uint256 extension
    ) external;
}
