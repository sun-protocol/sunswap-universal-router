// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "./modules/SafeTransferLib.sol";

contract SafeVault {
    event PendingOwnerSet(address indexed oldPendingOwner, address indexed newPendingOwner);
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event TokenWithdraw(address indexed token, address indexed owner, uint256 amount);

    address public owner;
    address public pendingOwner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not Owner");
        _;
    }

    constructor(address _owner) {
        require(_owner != address(0), "Not Zero Address");
        owner = _owner;
    }

    function setPendingOwner(address newPendingOwner) external onlyOwner {
        emit PendingOwnerSet(pendingOwner, newPendingOwner);
        pendingOwner = newPendingOwner;
    }

    function acceptOwner() external {
        require(msg.sender == pendingOwner, "Not Pending Owner");
        emit OwnerChanged(owner, pendingOwner);
        owner = pendingOwner;
    }

    function recoverTrc20(address token) external onlyOwner {
        uint256 amount = ERC20(token).balanceOf(address(this));
        require(amount > 0, "Invalid Token");
        bool success = SafeTransferLib.safeTransfer(token, msg.sender, amount);
        require(success, "Transfer failed.");
        emit TokenWithdraw(token, msg.sender, amount);
    }

    function recoverTRX() external onlyOwner {
        uint256 wvalue = address(this).balance;
        require(wvalue > 0, "Invalid Token");
        (bool success, ) = msg.sender.call{value: wvalue}("");
        require(success, "Transfer failed.");
        emit TokenWithdraw(address(0), msg.sender, wvalue);
    }

    receive() external payable {}
}
