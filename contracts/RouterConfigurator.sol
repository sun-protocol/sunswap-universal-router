// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2025 SunSwap
pragma solidity ^0.8.24;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

interface IConfigurableRouter {
    function pause() external;
    function unpause() external;
    function setSafeVault(address _safeVault) external;
    function setEnableRecipientCheck(bool isEnable) external;
    function setStableSwap(address _factory) external;
    function setReferralVault(address _referralVault) external;
    function acceptOwnership() external;
    function transferOwnership(address newOwner) external;
}

interface IConfigurableReferralVaultProxy {
    function vault() external view returns (address);
}

interface IConfigurableReferralVault {
    function setRouter(address _router) external;
    function setDefaultBips(uint256 _defaultBips) external;
    function setCustomRebateBips(address _rebateRecipient, uint256 _bips) external;
    function setMaxReferralBips(uint256 _maxReferralBips) external;
    function setRebateCheckEnabled(bool _enabled) external;
    function setRebateEnabled(address _rebateRecipient, bool _enabled) external;
    function transferOperator(address _operator) external;
}

/// @notice Holds UniversalRouter ownership and temporarily holds ReferralVault operator rights for atomic binding.
///         The independent proxy owner authorizes routers before linking. Owner performs binding and manages
///         router settings and pausing; owner or operator may accept pending router ownership. New routers are configured
///         before ownership handover. Operator maintains vault business parameters while this contract
///         holds vault operator rights, then hands those rights back after rollout.
contract RouterConfigurator is Ownable2Step {
    address public operator;

    event Linked(address indexed router, address indexed vaultProxy, address indexed vault);
    event OperatorUpdated(address indexed previousOperator, address indexed newOperator);

    constructor(address _owner, address _operator) Ownable(_owner) {
        require(_operator != address(0), "Invalid operator");
        operator = _operator;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "Not operator");
        _;
    }

    modifier onlyOwnerOrOperator() {
        if (msg.sender != operator) _checkOwner();
        _;
    }

    // ========================= Role Management =========================

    /// @notice Ownership can only be handed over, never dropped: losing it would freeze router administration
    function renounceOwnership() public pure override {
        revert("Renounce disabled");
    }

    /// @notice Replace the operator, e.g. revoke a lost or compromised operator key
    function setOperator(address _operator) external onlyOwner {
        _setOperator(_operator);
    }

    /// @notice Hand this configurator's operator role to the next operator
    function transferOperator(address _operator) external onlyOperator {
        _setOperator(_operator);
    }

    // ========================= Initial Binding =========================

    /// @notice Point the router's referralVault and the vault's router at the proxy in one transaction.
    /// @dev The proxy owner must authorize the router beforehand; this method does not change proxy permissions.
    function link(address router, address vaultProxy, address vault) external onlyOwner {
        require(IConfigurableReferralVaultProxy(vaultProxy).vault() == vault, "Proxy vault mismatch");
        IConfigurableReferralVault(vault).setRouter(vaultProxy);
        IConfigurableRouter(router).setReferralVault(vaultProxy);
        emit Linked(router, vaultProxy, vault);
    }

    // ========================= Router Management =========================

    /// @notice Complete the Ownable2Step handover after the router owner called transferOwnership(this)
    function acceptRouterOwnership(address router) external onlyOwnerOrOperator {
        IConfigurableRouter(router).acceptOwnership();
    }

    /// @notice Pause a managed router, e.g. when retiring an old version
    function pauseRouter(address router) external onlyOwner {
        IConfigurableRouter(router).pause();
    }

    /// @notice Resume a paused managed router
    function unpauseRouter(address router) external onlyOwner {
        IConfigurableRouter(router).unpause();
    }

    /// @notice Change the router's residual-funds recipient
    function setRouterSafeVault(address router, address safeVault) external onlyOwner {
        IConfigurableRouter(router).setSafeVault(safeVault);
    }

    /// @notice Enable or disable the router's recipient restriction
    function setRouterEnableRecipientCheck(address router, bool enabled) external onlyOwner {
        IConfigurableRouter(router).setEnableRecipientCheck(enabled);
    }

    /// @notice Change the StableSwap registry; the router's PSM and HTX-SUN registries are unchanged
    function setRouterStableSwap(address router, address factory) external onlyOwner {
        IConfigurableRouter(router).setStableSwap(factory);
    }

    /// @notice Change referral routing without requiring this contract to hold the vault operator role
    function setRouterReferralVault(address router, address referralVault) external onlyOwner {
        IConfigurableRouter(router).setReferralVault(referralVault);
    }

    /// @notice Transfer router ownership if needed; `newOwner` must still accept ownership on the router
    function transferRouterOwnership(address router, address newOwner) external onlyOwner {
        IConfigurableRouter(router).transferOwnership(newOwner);
    }

    // ========================= Vault Management =========================

    /// @notice Change the vault's authorized router while this contract holds its operator role
    /// @dev Updates only the vault; use link for atomic Router -> Proxy -> Vault binding.
    function setVaultRouter(address vault, address router) external onlyOperator {
        IConfigurableReferralVault(vault).setRouter(router);
    }

    /// @notice Set the vault's default rebate share while this contract holds its operator role
    function setVaultDefaultBips(address vault, uint256 defaultBips) external onlyOperator {
        IConfigurableReferralVault(vault).setDefaultBips(defaultBips);
    }

    /// @notice Set a recipient's custom rebate share, including an explicit zero share
    function setVaultCustomRebateBips(address vault, address rebateRecipient, uint256 bips) external onlyOperator {
        IConfigurableReferralVault(vault).setCustomRebateBips(rebateRecipient, bips);
    }

    /// @notice Set the vault's upper bound on router referral fees
    function setVaultMaxReferralBips(address vault, uint256 maxReferralBips) external onlyOperator {
        IConfigurableReferralVault(vault).setMaxReferralBips(maxReferralBips);
    }

    /// @notice Enable or disable the vault's rebate-recipient whitelist check
    function setVaultRebateCheckEnabled(address vault, bool enabled) external onlyOperator {
        IConfigurableReferralVault(vault).setRebateCheckEnabled(enabled);
    }

    /// @notice Update a recipient's vault whitelist entry
    function setVaultRebateEnabled(address vault, address rebateRecipient, bool enabled) external onlyOperator {
        IConfigurableReferralVault(vault).setRebateEnabled(rebateRecipient, enabled);
    }

    /// @notice Hand the vault operator role back after rollout
    function transferVaultOperator(address vault, address newOperator) external onlyOperator {
        IConfigurableReferralVault(vault).transferOperator(newOperator);
    }

    // ========================= Internal =========================

    function _setOperator(address _operator) private {
        require(_operator != address(0), "Invalid operator");
        address previous = operator;
        operator = _operator;
        emit OperatorUpdated(previous, _operator);
    }
}
