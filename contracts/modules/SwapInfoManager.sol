// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;
import {Ownable} from "v4-core/src/base/Ownable.sol";
import {SwapFlags} from "../libraries/SwapFlags.sol";

contract SwapInfoManager is Ownable {
    using SwapFlags for uint256;
    struct SwapPoolInfo {
        address swapContract;
        address[] tokens;
        address LPContract;
        uint256 extension;
    }

    mapping(uint256 => SwapPoolInfo) public swapPoolInfo;

    address public operator;

    modifier OnlyOperator() {
        require(msg.sender == operator || msg.sender == owner(), "Not Operator");
        _;
    }

    constructor() Ownable(msg.sender) {
        operator = msg.sender;
    }

    function setOperator(address _operator) external onlyOwner {
        require(_operator != address(0), "Invalid operator address");
        operator = _operator;
    }

    function transferOperator(address _operator) external OnlyOperator {
        require(_operator != address(0), "Invalid operator address");
        operator = _operator;
    }

    function getSwapPoolInfo(uint256 flag) external view returns (SwapPoolInfo memory) {
        return swapPoolInfo[flag];
    }

    function setSwapPoolInfo(
        uint256 flag,
        address swapContract,
        address[] calldata tokens,
        address LPContract,
        uint256 extension
    ) external OnlyOperator {
        require(swapContract != address(0), "Invalid swapContract address");
        swapPoolInfo[flag] = SwapPoolInfo(swapContract, tokens, LPContract, extension);
    }

    // get[0-15] 16bits for pool type:
    // eg:
    // 0x0001 : exactPool
    // 0x0010 : PSMPool
    // 0x0100 : stable base two pool
    // 0x0101 : stable base three pool
    // 0x0110 : stable base four pool
    // 0x1000 : stable mata two pool
    // 0x1001 : stable mata three pool
    // 0x1010 : stable mata four pool

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
        )
    {
        SwapPoolInfo memory info = swapPoolInfo[flag];
        require(info.swapContract != address(0), "SwapInfo not exist");
        address[] memory tokens = info.tokens;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == input) {
                k = i;
            }
            if (tokens[i] == output) {
                j = i;
            }
        }
        require(k != j, "Input equals output");
        require(tokens[k] == input && tokens[j] == output, "Input or output not in pool");
        swapContract = info.swapContract;
        extension = info.extension;
    }
}
