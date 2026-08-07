// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IReferralVault
/// @notice Interface for the referral commission management contract
interface IReferralVault {
    // --- Events ---
    event ReferralAllocated(
        address indexed token,
        address indexed rebateRecipient,
        uint256 rebateAmount,
        uint256 protocolAmount
    );
    event ReferralClaimed(
        address indexed token,
        address indexed rebateRecipient,
        address indexed recipient,
        uint256 amount
    );
    event ProtocolFundsClaimed(address indexed token, address indexed recipient, uint256 amount);
    event RebateEnabledUpdated(address indexed rebateRecipient, bool enabled);

    event RouterUpdated(address indexed previousRouter, address indexed newRouter);
    event OperatorUpdated(address indexed previousOperator, address indexed newOperator);
    event DefaultBipsUpdated(uint256 previousDefaultBips, uint256 newDefaultBips);
    event CustomRebateBipsUpdated(address indexed rebateRecipient, uint256 bips);
    event MaxReferralBipsUpdated(uint256 previousMaxReferralBips, uint256 newMaxReferralBips);
    event RebateCheckEnabledUpdated(bool enabled);

    // --- Write: Owner ---
    function setOperator(address operator) external;

    // --- Write: Operator ---
    function setRouter(address router) external;

    function transferOperator(address operator) external;

    function setDefaultBips(uint256 defaultBips) external;

    function setCustomRebateBips(address rebateRecipient, uint256 bips) external;

    function setMaxReferralBips(uint256 maxReferralBips) external;

    function setRebateCheckEnabled(bool enabled) external;

    function setRebateEnabled(address rebateRecipient, bool enabled) external;

    // --- Write: Router ---
    function updateLastTokenBalance(address token) external;

    function allocateReferral(address token, address rebateRecipient) external;

    // --- Write: Public ---
    function claimReferral(address token, address rebateRecipient) external;

    function emergencyClaimReferral(
        address token,
        address rebateRecipient,
        address recipient
    ) external;

    function claimProtocolFunds(address recipient, address token) external;

    // --- Read ---
    function referralBalance(address token, address rebateRecipient) external view returns (uint256);

    function totalReferralBalance(address token) external view returns (uint256);

    function lastTokenBalance(address token) external view returns (uint256);

    function customRebateBips(address rebateRecipient) external view returns (uint256);

    function isRebateEnabled(address rebateRecipient) external view returns (bool);

    function isRebateCheckEnabled() external view returns (bool);

    function maxReferralBips() external view returns (uint256);

    function defaultBips() external view returns (uint256);

    function BASE_BIPS() external pure returns (uint256);

    function operator() external view returns (address);

    function router() external view returns (address);
}
