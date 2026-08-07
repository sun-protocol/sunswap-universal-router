// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {Ownable} from "v4-core/src/base/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "./modules/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IReferralVault} from "./interfaces/IReferralVault.sol";

/// @title ReferralVault
/// @notice Manages referral commission allocation and claims between rebate recipients and the protocol.
///         Commissions are split at allocation time (during swaps) based on the current customRebateBips.
///         Protocol funds = contract balance - totalReferralBalance (includes any accidentally sent funds).
contract ReferralVault is IReferralVault, Ownable, ReentrancyGuard {
    mapping(address => mapping(address => uint256)) public referralBalance; // per-token, per-rebate-recipient accrued balance
    mapping(address => uint256) public totalReferralBalance; // per-token sum of all rebate balances
    mapping(address => uint256) public customRebateBips; // per-rebate-recipient bips override
    mapping(address => bool) public hasCustomRebateBips; // sentinel: distinguishes "custom bips of 0" from "no custom bips set"
    mapping(address => bool) public isRebateEnabled; // whitelist consulted when isRebateCheckEnabled
    mapping(address => uint256) public lastTokenBalance; // vault's `token` balance after the last mutating call
    uint256 public constant BASE_BIPS = 10000;
    uint256 public defaultBips; // fallback bips when no custom rebate bips is set
    uint256 public maxReferralBips; // upper bound on bips that the Router may pass to payReferral
    bool public isRebateCheckEnabled; // when true, allocateReferral requires isRebateEnabled[recipient]
    address public operator;
    address public router;

    constructor(address _operator, address _router) Ownable(msg.sender) {
        require(_operator != address(0), "Invalid operator");
        require(_router != address(0), "Invalid router");
        operator = _operator;
        router = _router;
        defaultBips = 8000; // 80% to rebate recipient
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "Not operator");
        _;
    }

    modifier onlyRouter() {
        require(msg.sender == router, "Not router");
        _;
    }

    receive() external payable {}

    // ========================= Owner =========================

    function setOperator(address _operator) external onlyOwner {
        require(_operator != address(0), "Invalid operator");
        address previous = operator;
        operator = _operator;
        emit OperatorUpdated(previous, _operator);
    }

    // ========================= Operator =========================

    function setRouter(address _router) external onlyOperator {
        require(_router != address(0), "Invalid router");
        address previous = router;
        router = _router;
        emit RouterUpdated(previous, _router);
    }

    function transferOperator(address _operator) external onlyOperator {
        require(_operator != address(0), "Invalid operator");
        address previous = operator;
        operator = _operator;
        emit OperatorUpdated(previous, _operator);
    }

    function setDefaultBips(uint256 _defaultBips) external onlyOperator {
        require(_defaultBips <= BASE_BIPS, "Invalid defaultBips");
        uint256 previous = defaultBips;
        defaultBips = _defaultBips;
        emit DefaultBipsUpdated(previous, _defaultBips);
    }

    function setCustomRebateBips(address _rebateRecipient, uint256 _bips) external onlyOperator {
        require(_rebateRecipient != address(0), "Invalid rebateRecipient");
        require(_bips <= BASE_BIPS, "Invalid bips");
        customRebateBips[_rebateRecipient] = _bips;
        hasCustomRebateBips[_rebateRecipient] = true;
        emit CustomRebateBipsUpdated(_rebateRecipient, _bips);
    }

    function setMaxReferralBips(uint256 _maxReferralBips) external onlyOperator {
        require(_maxReferralBips <= BASE_BIPS, "Invalid maxReferralBips");
        uint256 previous = maxReferralBips;
        maxReferralBips = _maxReferralBips;
        emit MaxReferralBipsUpdated(previous, _maxReferralBips);
    }

    function setRebateCheckEnabled(bool _enabled) external onlyOperator {
        isRebateCheckEnabled = _enabled;
        emit RebateCheckEnabledUpdated(_enabled);
    }

    function setRebateEnabled(address _rebateRecipient, bool _enabled) external onlyOperator {
        require(_rebateRecipient != address(0), "Invalid rebateRecipient");
        isRebateEnabled[_rebateRecipient] = _enabled;
        emit RebateEnabledUpdated(_rebateRecipient, _enabled);
    }

    // ========================= Router =========================

    /// @notice External counterpart of `_updateLastTokenBalance`. Called by Router
    ///         immediately before pushing this round's payPortion into the vault, so
    ///         that the subsequent `allocateReferral` delta only counts the new inflow
    ///         and not any prior donations / residual balance.
    /// @dev    Restricted to the Router because a malicious ERC20's transfer callback
    ///         could otherwise call this mid-payPortion and shift the snapshot, causing
    ///         the next allocateReferral to under-credit the rebate recipient.
    function updateLastTokenBalance(address token) external onlyRouter {
        _updateLastTokenBalance(token);
    }

    /// @notice Called by Router during swap to allocate referral commission.
    ///         Splits amount into the rebate-recipient share and protocol share at the current bps rate.
    /// @dev    INVARIANT: this MUST be preceded in the same tx by `updateLastTokenBalance(token)`
    ///         and a transfer-in (e.g. via `Payments.payPortion(token, vault, bips)`). Without
    ///         that prior snapshot, any pre-existing vault balance (donations / residuals) is
    ///         folded into the rebate delta and leaks bips% to the rebate recipient at the
    ///         protocol's expense. The canonical 3-step call sequence is implemented in
    ///         `Payments.payReferral`; do not call `allocateReferral` directly outside that flow.
    /// @param rebateRecipient The address that will be credited with the rebate.
    function allocateReferral(address token, address rebateRecipient) external onlyRouter {
        require(rebateRecipient != address(0), "Invalid rebateRecipient");
        uint256 previousBalance = lastTokenBalance[token];
        _updateLastTokenBalance(token);
        uint256 amount = lastTokenBalance[token] - previousBalance;
        if (isRebateCheckEnabled) {
            require(isRebateEnabled[rebateRecipient], "Rebate recipient not enabled");
        }
        uint256 bips = hasCustomRebateBips[rebateRecipient] ? customRebateBips[rebateRecipient] : defaultBips;
        uint256 rebateAmount = (amount * bips) / BASE_BIPS;
        referralBalance[token][rebateRecipient] += rebateAmount;
        totalReferralBalance[token] += rebateAmount;

        emit ReferralAllocated(token, rebateRecipient, rebateAmount, amount - rebateAmount);
    }

    // ========================= Public =========================
    /// @notice Claim referral funds for a rebate recipient.
    /// @dev Only the rebate recipient itself (msg.sender == rebateRecipient) may pull its accrued balance.
    function claimReferral(address token, address rebateRecipient) external nonReentrant {
        require(msg.sender == rebateRecipient, "Not rebate recipient");
        uint256 amount = referralBalance[token][rebateRecipient];
        require(amount > 0, "No balance");
        referralBalance[token][rebateRecipient] = 0;
        totalReferralBalance[token] -= amount;
        if (token == address(0)) {
            require(SafeTransferLib.safeTransferETH(rebateRecipient, amount), "TransferHelper: ETH_TRANSFER_FAILED");
        } else {
            require(SafeTransferLib.safeTransfer(token, rebateRecipient, amount), "TransferHelper: TRANSFER_FAILED");
        }
        _updateLastTokenBalance(token);
        emit ReferralClaimed(token, rebateRecipient, rebateRecipient, amount);
    }

    /// @notice Emergency claim referral funds on behalf of a rebate recipient.
    /// @dev Owner-only escape hatch — redirects the rebate recipient's balance to an arbitrary recipient address.
    function emergencyClaimReferral(
        address token,
        address rebateRecipient,
        address recipient
    ) external onlyOwner nonReentrant {
        require(recipient != address(0), "Invalid recipient");
        uint256 amount = referralBalance[token][rebateRecipient];
        require(amount > 0, "No balance");
        referralBalance[token][rebateRecipient] = 0;
        totalReferralBalance[token] -= amount;
        if (token == address(0)) {
            require(SafeTransferLib.safeTransferETH(recipient, amount), "TransferHelper: ETH_TRANSFER_FAILED");
        } else {
            require(SafeTransferLib.safeTransfer(token, recipient, amount), "TransferHelper: TRANSFER_FAILED");
        }
        _updateLastTokenBalance(token);
        emit ReferralClaimed(token, rebateRecipient, recipient, amount);
    }

    /// @notice Protocol funds = contract token balance - totalReferralBalance.
    ///         This includes both protocol commission share and any accidentally sent funds.
    function claimProtocolFunds(address recipient, address token) external onlyOwner nonReentrant {
        require(recipient != address(0), "Invalid recipient");
        uint256 amount = getProtocolFunds(token);
        require(amount > 0, "No balance");
        if (token == address(0)) {
            require(SafeTransferLib.safeTransferETH(recipient, amount), "TransferHelper: ETH_TRANSFER_FAILED");
        } else {
            require(SafeTransferLib.safeTransfer(token, recipient, amount), "TransferHelper: TRANSFER_FAILED");
        }
        _updateLastTokenBalance(token);
        emit ProtocolFundsClaimed(token, recipient, amount);
    }

    // ========================= Read =========================

    function getProtocolFunds(address token) public view returns (uint256) {
        if (token == address(0)) {
            return address(this).balance - totalReferralBalance[token];
        } else {
            return ERC20(token).balanceOf(address(this)) - totalReferralBalance[token];
        }
    }

    // ========================= Internal =========================

    /// @notice Updates `lastTokenBalance[token]` to the vault's current balance of `token`.
    /// @dev Invoked at every site that mutates this contract's reserves of `token`:
    ///      `allocateReferral`, `claimReferral`, `emergencyClaimReferral`, `claimProtocolFunds`.
    ///      `token == address(0)` represents native currency (ETH/TRX); otherwise it's a TRC20/ERC20.
    /// @param token The token whose post-mutation balance should be recorded.
    function _updateLastTokenBalance(address token) private {
        if (token == address(0)) {
            lastTokenBalance[token] = address(this).balance;
        } else {
            lastTokenBalance[token] = ERC20(token).balanceOf(address(this));
        }
    }
}
