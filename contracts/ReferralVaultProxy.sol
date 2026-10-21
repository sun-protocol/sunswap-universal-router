// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2025 SunSwap
pragma solidity ^0.8.24;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "./modules/SafeTransferLib.sol";
import {IReferralVault} from "./interfaces/IReferralVault.sol";

/// @title ReferralVaultProxy
/// @notice Sits between one or more UniversalRouters and a single ReferralVault so that several router
///         versions can pay referrals into the same vault at once (vault.router == this proxy).
/// @dev    Routers set `referralVault = address(this)`, so `Payments.payReferral` pushes funds into the
///         proxy rather than the vault. Each forwarded step therefore flushes the proxy's balance to the
///         vault first, preserving the vault's snapshot -> inflow -> allocate accounting:
///           1. updateLastTokenBalance: flush residuals (they become protocol funds), then snapshot
///           2. router transfers this round's portion into the proxy
///           3. allocateReferral: flush this round's portion, then the vault books the delta
contract ReferralVaultProxy is Ownable2Step {
    address public immutable vault;
    mapping(address => bool) public isRouterAllowed;

    event RouterAuthorizationUpdated(address indexed router, bool allowed);

    constructor(address initialOwner, address _vault) Ownable(initialOwner) {
        require(_vault != address(0) && _vault.code.length > 0, "Invalid vault");
        vault = _vault;
    }

    modifier onlyRouter() {
        require(isRouterAllowed[msg.sender], "Not router");
        _;
    }

    receive() external payable {}

    // ========================= Owner =========================

    /// @notice Ownership can only be handed over, never dropped: losing it would freeze the router whitelist
    function renounceOwnership() public pure override {
        revert("Renounce disabled");
    }

    function setRouterAllowed(address router, bool allowed) external onlyOwner {
        require(router != address(0), "Invalid router");
        if (allowed) require(router.code.length > 0, "Invalid router");
        isRouterAllowed[router] = allowed;
        emit RouterAuthorizationUpdated(router, allowed);
    }

    // ========================= Router =========================

    function maxReferralBips() external view returns (uint256) {
        return IReferralVault(vault).maxReferralBips();
    }

    function updateLastTokenBalance(address token) external onlyRouter {
        _flush(token);
        IReferralVault(vault).updateLastTokenBalance(token);
    }

    function allocateReferral(address token, address rebateRecipient) external onlyRouter {
        _flush(token);
        IReferralVault(vault).allocateReferral(token, rebateRecipient);
    }

    // ========================= Internal =========================

    /// @dev Moves the proxy's entire `token` balance (address(0) = native) into the vault
    function _flush(address token) private {
        if (token == address(0)) {
            uint256 amount = address(this).balance;
            if (amount > 0) {
                require(SafeTransferLib.safeTransferETH(vault, amount), "SafeTransferLib: ETH_TRANSFER_FAILED");
            }
        } else {
            uint256 amount = ERC20(token).balanceOf(address(this));
            if (amount > 0) {
                require(SafeTransferLib.safeTransfer(token, vault, amount), "SafeTransferLib: TRANSFER_FAILED");
            }
        }
    }
}
