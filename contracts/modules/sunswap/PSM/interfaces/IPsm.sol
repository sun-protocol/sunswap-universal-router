pragma solidity ^0.8.0;

interface IPsm {
    function buyGem(address recipient, uint256 amount) external;
    function sellGem(address recipient, uint256 amount) external;
    function gemJoin() external view returns (address);
    function usdd() external view returns (address);
}