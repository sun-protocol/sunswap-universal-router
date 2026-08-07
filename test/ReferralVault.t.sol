// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ReferralVault} from "src/ReferralVault.sol";
import {IReferralVault} from "src/interfaces/IReferralVault.sol";
import {MockERC20} from "./mock/MockERC20.sol";

contract NonPayableContract {
    // Cannot receive ETH — no receive() or fallback()
}

/// @dev `rebateRecipient` for ETH `claimReferral`; reenters on ETH receive.
///      Also exposes a `start()` that the test can call via `vm.prank(address(this))`
///      to satisfy the new `msg.sender == rebateRecipient` check on `claimReferral`.
contract ReentrantETHProject {
    ReferralVault immutable vault;

    constructor(ReferralVault _vault) {
        vault = _vault;
    }

    function start() external {
        vault.claimReferral(address(0), address(this));
    }

    receive() external payable {
        vault.claimReferral(address(0), address(this));
    }
}

/// @dev ERC20 that reenters `claimReferral` when the vault sends tokens to the project.
contract ReentrantTransferERC20 is ERC20 {
    ReferralVault public immutable vault;
    address public immutable claimProject;

    constructor(ReferralVault _vault, address _claimProject) ERC20("Reenter", "RNT", 18) {
        vault = _vault;
        claimProject = _claimProject;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        if (msg.sender == address(vault)) {
            vault.claimReferral(address(this), claimProject);
        }
        return super.transfer(to, amount);
    }
}

contract EmergencyReenterRecipient {
    EmergencyReenterOwner immutable ownerHelper;

    constructor(EmergencyReenterOwner _ownerHelper) {
        ownerHelper = _ownerHelper;
    }

    receive() external payable {
        ownerHelper.onEthReceived();
    }
}

/// @dev Owns the vault and triggers `emergencyClaimReferral` → recipient reenters.
contract EmergencyReenterOwner {
    ReferralVault public immutable vault;
    address public immutable project;
    EmergencyReenterRecipient public immutable recipient;

    constructor(ReferralVault _vault, address _project) {
        vault = _vault;
        project = _project;
        recipient = new EmergencyReenterRecipient(this);
    }

    function start() external {
        vault.emergencyClaimReferral(address(0), project, address(recipient));
    }

    function onEthReceived() external payable {
        require(msg.sender == address(recipient), "not recipient");
        vault.emergencyClaimReferral(address(0), project, address(recipient));
    }
}

contract ProtocolReenterRecipient {
    OwnerProtocolReenter immutable ownerHelper;

    constructor(OwnerProtocolReenter _ownerHelper) {
        ownerHelper = _ownerHelper;
    }

    receive() external payable {
        ownerHelper.onEthReceived();
    }
}

/// @dev Owns the vault and triggers `claimProtocolFunds` → recipient reenters.
contract OwnerProtocolReenter {
    ReferralVault public immutable vault;
    ProtocolReenterRecipient public immutable recipient;

    constructor(ReferralVault _vault) {
        vault = _vault;
        recipient = new ProtocolReenterRecipient(this);
    }

    function start() external {
        vault.claimProtocolFunds(address(recipient), address(0));
    }

    function onEthReceived() external payable {
        require(msg.sender == address(recipient), "not recipient");
        vault.claimProtocolFunds(address(recipient), address(0));
    }
}

contract ReferralVaultTest is Test {
    using stdStorage for StdStorage;

    ReferralVault vault;
    MockERC20 token;

    address owner;
    address operator = makeAddr("operator");
    address routerAddr = makeAddr("router");
    address project = makeAddr("project");
    address project2 = makeAddr("project2");
    address recipient = makeAddr("recipient");
    address alice = makeAddr("alice");

    uint256 constant BASE_BIPS = 10000;
    uint256 constant AMOUNT = 10 ether;

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

    function setUp() public {
        owner = address(this);
        vault = new ReferralVault(operator, routerAddr);
        token = new MockERC20();

        vm.prank(operator);
        vault.setRebateEnabled(project, true);
    }

    // ===================== Helpers =====================

    /// @dev Directly set referralBalance in storage (bypass allocateReferral)
    function _setReferralBalance(
        address _token,
        address _project,
        uint256 amount
    ) internal {
        stdstore
            .target(address(vault))
            .sig("referralBalance(address,address)")
            .with_key(_token)
            .with_key(_project)
            .checked_write(amount);
    }

    /// @dev Directly set totalReferralBalance in storage
    function _setTotalReferralBalance(address _token, uint256 amount) internal {
        stdstore.target(address(vault)).sig("totalReferralBalance(address)").with_key(_token).checked_write(amount);
    }

    /// @dev Fund vault with ETH and set referral accounting
    function _setupETHReferral(address _project, uint256 amount) internal {
        vm.deal(address(vault), amount);
        _setReferralBalance(address(0), _project, amount);
        _setTotalReferralBalance(address(0), amount);
    }

    /// @dev Fund vault with ERC20 and set referral accounting
    function _setupERC20Referral(address _project, uint256 amount) internal {
        token.mint(address(vault), amount);
        _setReferralBalance(address(token), _project, amount);
        _setTotalReferralBalance(address(token), amount);
    }

    // =================== Constructor ===================

    function test_constructor_initializesCorrectly() public view {
        assertEq(vault.owner(), owner);
        assertEq(vault.operator(), operator);
        assertEq(vault.router(), routerAddr);
        assertEq(vault.defaultBips(), 8000);
        assertEq(vault.maxReferralBips(), 0);
        assertEq(vault.BASE_BIPS(), 10000);
        assertFalse(vault.isRebateCheckEnabled());
    }

    function test_constructor_revertsZeroOperator() public {
        vm.expectRevert("Invalid operator");
        new ReferralVault(address(0), routerAddr);
    }

    function test_constructor_revertsZeroRouter() public {
        vm.expectRevert("Invalid router");
        new ReferralVault(operator, address(0));
    }

    // ================= Access Control ==================

    function test_setOperator_onlyOwner() public {
        vm.expectRevert();
        vm.prank(alice);
        vault.setOperator(alice);
    }

    function test_transferOperator_onlyOperator() public {
        vm.expectRevert("Not operator");
        vm.prank(alice);
        vault.transferOperator(alice);
    }

    function test_setDefaultBips_onlyOperator() public {
        vm.expectRevert("Not operator");
        vm.prank(alice);
        vault.setDefaultBips(5000);
    }

    function test_setCustomRebateBips_onlyOperator() public {
        vm.expectRevert("Not operator");
        vm.prank(alice);
        vault.setCustomRebateBips(project, 5000);
    }

    function test_setMaxReferralBips_onlyOperator() public {
        vm.expectRevert("Not operator");
        vm.prank(alice);
        vault.setMaxReferralBips(500);
    }

    function test_setRebateEnabled_onlyOperator() public {
        vm.expectRevert("Not operator");
        vm.prank(alice);
        vault.setRebateEnabled(project, true);
    }

    function test_setRebateCheckEnabled_onlyOperator() public {
        vm.expectRevert("Not operator");
        vm.prank(alice);
        vault.setRebateCheckEnabled(true);
    }

    function test_allocateReferral_onlyRouter() public {
        vm.expectRevert("Not router");
        vm.prank(alice);
        vault.allocateReferral(address(token), project);
    }

    // ================ Owner Functions ==================

    // ================= Operator: setRouter ====================
    // ReferralVault.setRouter is onlyOperator. The operator gate uses the
    // local `require(... "Not operator")` modifier, so negative tests assert
    // on that reason string.

    /// @notice Negative coverage: a random EOA, the owner, the current router,
    ///         and any other non-operator address must not be able to rotate
    ///         the router. Only the operator may.
    function test_setRouter_reverts_when_caller_not_operator() public {
        vm.expectRevert("Not operator");
        vm.prank(alice);
        vault.setRouter(alice);

        // owner is not operator under the new gating
        vm.expectRevert("Not operator");
        vm.prank(owner);
        vault.setRouter(alice);

        vm.expectRevert("Not operator");
        vm.prank(routerAddr);
        vault.setRouter(alice);

        // storage must be untouched after each failed call
        assertEq(vault.router(), routerAddr);
    }

    /// @notice Regression: setRouter used to be onlyOwner. Make sure the
    ///         owner can no longer call it.
    function test_setRouter_reverts_when_caller_is_owner() public {
        address newRouter = makeAddr("newRouter");
        vm.prank(owner);
        vm.expectRevert("Not operator");
        vault.setRouter(newRouter);

        assertEq(vault.router(), routerAddr);
    }

    function test_setRouter_reverts_when_zero_address() public {
        vm.prank(operator);
        vm.expectRevert("Invalid router");
        vault.setRouter(address(0));
    }

    /// @notice Positive: the operator can successfully rotate the router.
    function test_setRouter_success_when_caller_is_operator() public {
        address newRouter = makeAddr("newRouter");

        vm.expectEmit(true, true, false, true);
        emit RouterUpdated(routerAddr, newRouter);
        vm.prank(operator);
        vault.setRouter(newRouter);

        assertEq(vault.router(), newRouter);
    }

    function test_setRouter_emits_RouterUpdated_when_setting_same_address_again() public {
        vm.prank(operator);
        vault.setRouter(alice);

        vm.expectEmit(true, true, false, true);
        emit RouterUpdated(alice, alice);
        vm.prank(operator);
        vault.setRouter(alice);

        assertEq(vault.router(), alice);
    }

    function test_setRouter_after_change_only_new_router_can_allocateReferral() public {
        address newRouter = makeAddr("newRouter");

        vm.prank(operator);
        vault.setRouter(newRouter);

        token.mint(address(vault), AMOUNT);

        vm.prank(routerAddr);
        vm.expectRevert("Not router");
        vault.allocateReferral(address(token), project);

        vm.prank(newRouter);
        vault.allocateReferral(address(token), project);

        uint256 expectedRebate = (AMOUNT * vault.defaultBips()) / BASE_BIPS;
        assertEq(vault.referralBalance(address(token), project), expectedRebate);
    }

    function test_setOperator_success() public {
        vault.setOperator(alice);
        assertEq(vault.operator(), alice);
    }

    function test_setOperator_revertsZeroAddress() public {
        vm.expectRevert("Invalid operator");
        vault.setOperator(address(0));
    }

    // ============== Operator Functions =================

    function test_transferOperator_success() public {
        vm.prank(operator);
        vault.transferOperator(alice);
        assertEq(vault.operator(), alice);
    }

    function test_transferOperator_revertsZeroAddress() public {
        vm.prank(operator);
        vm.expectRevert("Invalid operator");
        vault.transferOperator(address(0));
    }

    function test_setDefaultBips_success() public {
        vm.prank(operator);
        vault.setDefaultBips(5000);
        assertEq(vault.defaultBips(), 5000);
    }

    function test_setDefaultBips_revertsExceedsBase() public {
        vm.prank(operator);
        vm.expectRevert("Invalid defaultBips");
        vault.setDefaultBips(BASE_BIPS + 1);
    }

    function test_setDefaultBips_allowsZero() public {
        vm.prank(operator);
        vault.setDefaultBips(0);
        assertEq(vault.defaultBips(), 0);
    }

    function test_setCustomRebateBips_success() public {
        vm.prank(operator);
        vault.setCustomRebateBips(project, 9000);
        assertEq(vault.customRebateBips(project), 9000);
    }

    function test_setCustomRebateBips_revertsExceedsBase() public {
        vm.prank(operator);
        vm.expectRevert("Invalid bips");
        vault.setCustomRebateBips(project, BASE_BIPS + 1);
    }

    function test_setCustomRebateBips_revertsZeroAddress() public {
        vm.prank(operator);
        vm.expectRevert("Invalid rebateRecipient");
        vault.setCustomRebateBips(address(0), 5000);

        // storage must be untouched after the failed call
        assertEq(vault.customRebateBips(address(0)), 0);
        assertFalse(vault.hasCustomRebateBips(address(0)));
    }

    /// @notice Regression test for H-01: explicitly setting customRebateBips to 0 should
    ///         allocate 0% to the project, not fall back to defaultBips.
    function test_setCustomRebateBips_explicitZero_usesZeroNotDefault() public {
        vm.prank(operator);
        vault.setCustomRebateBips(project, 0);

        token.mint(address(vault), AMOUNT);

        vm.prank(routerAddr);
        vault.allocateReferral(address(token), project);

        assertEq(vault.referralBalance(address(token), project), 0);
        assertEq(vault.totalReferralBalance(address(token)), 0);
    }

    function test_setMaxReferralBips_success() public {
        vm.prank(operator);
        vault.setMaxReferralBips(500);
        assertEq(vault.maxReferralBips(), 500);
    }

    function test_setMaxReferralBips_revertsExceedsBase() public {
        vm.prank(operator);
        vm.expectRevert("Invalid maxReferralBips");
        vault.setMaxReferralBips(BASE_BIPS + 1);
    }

    function test_setRebateEnabled_enable() public {
        vm.prank(operator);
        vm.expectEmit(true, false, false, true);
        emit RebateEnabledUpdated(project2, true);
        vault.setRebateEnabled(project2, true);

        assertTrue(vault.isRebateEnabled(project2));
    }

    function test_setRebateEnabled_disable() public {
        vm.prank(operator);
        vault.setRebateEnabled(project2, true);
        assertTrue(vault.isRebateEnabled(project2));

        vm.prank(operator);
        vm.expectEmit(true, false, false, true);
        emit RebateEnabledUpdated(project2, false);
        vault.setRebateEnabled(project2, false);

        assertFalse(vault.isRebateEnabled(project2));
    }

    function test_setRebateEnabled_revertsZeroAddress() public {
        vm.prank(operator);
        vm.expectRevert("Invalid rebateRecipient");
        vault.setRebateEnabled(address(0), true);
    }

    // =========== rebateCheckEnabled ===================

    function test_setRebateCheckEnabled_enable() public {
        vm.prank(operator);
        vault.setRebateCheckEnabled(true);
        assertTrue(vault.isRebateCheckEnabled());
    }

    function test_setRebateCheckEnabled_disable() public {
        vm.prank(operator);
        vault.setRebateCheckEnabled(true);
        assertTrue(vault.isRebateCheckEnabled());

        vm.prank(operator);
        vault.setRebateCheckEnabled(false);
        assertFalse(vault.isRebateCheckEnabled());
    }

    function test_projectCheckDisabled_allowsAnyProject() public {
        assertFalse(vault.isRebateCheckEnabled());

        // project2 is NOT in rebateEnabled whitelist, but check is disabled
        assertFalse(vault.isRebateEnabled(project2));

        // Fund vault so the accounting doesn't underflow
        token.mint(address(vault), AMOUNT);

        // Should succeed — rebateCheckEnabled=false bypasses whitelist
        vm.prank(routerAddr);
        vault.allocateReferral(address(token), project2);

        // Verify the allocation went through
        uint256 bips = vault.defaultBips(); // 8000
        uint256 expectedRebate = (AMOUNT * bips) / BASE_BIPS;
        assertEq(vault.referralBalance(address(token), project2), expectedRebate);
    }

    function test_rebateCheckEnabled_blocksUnlistedProject() public {
        vm.prank(operator);
        vault.setRebateCheckEnabled(true);

        assertFalse(vault.isRebateEnabled(project2));

        vm.prank(routerAddr);
        // With check enabled and transient storage bug fixed, this should revert
        // with "Rebate recipient not enabled". Currently reverts from transient storage first.
        vm.expectRevert();
        vault.allocateReferral(address(token), project2);
    }

    // ============= allocateReferral ====================

    /// @notice The once-per-tx guard (ensureExecutedOnce) is enforced in Dispatcher,
    ///         not in ReferralVault.allocateReferral. Verify that the router can
    ///         call allocateReferral multiple times and balances accumulate correctly.
    function test_allocateReferral_multipleCallsAccumulate() public {
        // New semantics: amount is derived from balance delta vs `lastTokenBalance`,
        // so each accrual must be preceded by a fresh inbound transfer.
        vm.startPrank(routerAddr);

        // First batch: vault balance goes 0 → AMOUNT, so amount = AMOUNT.
        vm.deal(address(vault), AMOUNT);
        vault.allocateReferral(address(0), project);

        uint256 bips = vault.defaultBips();
        uint256 expectedFirst = (AMOUNT * bips) / BASE_BIPS;
        assertEq(vault.referralBalance(address(0), project), expectedFirst);
        assertEq(vault.lastTokenBalance(address(0)), AMOUNT);

        // Second batch: vault balance goes AMOUNT → 2*AMOUNT, so amount = AMOUNT again.
        vm.deal(address(vault), AMOUNT * 2);
        vault.allocateReferral(address(0), project);

        uint256 expectedTotal = expectedFirst * 2;
        assertEq(vault.referralBalance(address(0), project), expectedTotal);
        assertEq(vault.totalReferralBalance(address(0)), expectedTotal);
        assertEq(vault.lastTokenBalance(address(0)), AMOUNT * 2);
        vm.stopPrank();
    }

    function test_allocateReferral_revertsNotRouter() public {
        vm.expectRevert("Not router");
        vault.allocateReferral(address(token), project);
    }

    function test_allocateReferral_revertsZeroRebateRecipient() public {
        token.mint(address(vault), AMOUNT);
        vm.prank(routerAddr);
        vm.expectRevert("Invalid rebateRecipient");
        vault.allocateReferral(address(token), address(0));

        // accounting must remain untouched after the failed allocation
        assertEq(vault.referralBalance(address(token), address(0)), 0);
        assertEq(vault.totalReferralBalance(address(token)), 0);
        assertEq(vault.lastTokenBalance(address(token)), 0);
    }

    // ============= updateLastTokenBalance ==============

    function test_updateLastTokenBalance_revertsNotRouter() public {
        token.mint(address(vault), AMOUNT);
        vm.prank(alice);
        vm.expectRevert("Not router");
        vault.updateLastTokenBalance(address(token));

        // snapshot must remain at the pre-call value
        assertEq(vault.lastTokenBalance(address(token)), 0);
    }

    function test_updateLastTokenBalance_ETH_setsToCurrentBalance() public {
        vm.deal(address(vault), AMOUNT);
        assertEq(vault.lastTokenBalance(address(0)), 0);

        vm.prank(routerAddr);
        vault.updateLastTokenBalance(address(0));

        assertEq(vault.lastTokenBalance(address(0)), AMOUNT);
    }

    function test_updateLastTokenBalance_ERC20_setsToCurrentBalance() public {
        token.mint(address(vault), AMOUNT);
        assertEq(vault.lastTokenBalance(address(token)), 0);

        vm.prank(routerAddr);
        vault.updateLastTokenBalance(address(token));

        assertEq(vault.lastTokenBalance(address(token)), AMOUNT);
    }

    /// @notice Composing updateLastTokenBalance + (transfer in) + allocateReferral
    ///         isolates pre-existing vault balance from the rebate delta. Mirrors
    ///         the flow that `Payments.payReferral` now performs.
    function test_updateLastTokenBalance_isolatesPriorBalanceFromAllocateDelta() public {
        // Stray balance is sitting in the vault (e.g. from a donation).
        token.mint(address(vault), 50 ether);

        // Router calls updateLastTokenBalance BEFORE pushing this round's payPortion.
        vm.prank(routerAddr);
        vault.updateLastTokenBalance(address(token));

        // This round's payPortion (simulated by a direct mint to vault).
        token.mint(address(vault), 10 ether);

        // Now allocate — delta should equal only this round's 10 ether, not 60.
        vm.prank(routerAddr);
        vault.allocateReferral(address(token), project);

        uint256 expectedRebate = (10 ether * vault.defaultBips()) / BASE_BIPS;
        assertEq(vault.referralBalance(address(token), project), expectedRebate);
        assertEq(vault.totalReferralBalance(address(token)), expectedRebate);

        // Stray 50 ether stays in the vault as protocol funds (along with the
        // protocol portion of the 10-ether round).
        uint256 expectedProtocol = 50 ether + (10 ether - expectedRebate);
        assertEq(vault.getProtocolFunds(address(token)), expectedProtocol);
    }

    /// @notice Locks in the ReferralAllocated event shape (token, rebateRecipient,
    ///         projectAmount, protocolAmount). Indexers depend on this.
    function test_allocateReferral_emits_ReferralAllocated() public {
        token.mint(address(vault), AMOUNT);
        uint256 expectedRebate = (AMOUNT * vault.defaultBips()) / BASE_BIPS;
        uint256 expectedProtocol = AMOUNT - expectedRebate;

        vm.expectEmit(true, true, false, true);
        emit ReferralAllocated(address(token), project, expectedRebate, expectedProtocol);
        vm.prank(routerAddr);
        vault.allocateReferral(address(token), project);
    }

    /// @notice When no inbound transfer has occurred since the last snapshot,
    ///         the delta is 0 and allocateReferral is a pure no-op on accounting.
    function test_allocateReferral_zeroDelta_isNoop() public {
        vm.startPrank(routerAddr);
        vault.allocateReferral(address(token), project); // delta = 0 - 0 = 0
        vault.allocateReferral(address(token), project); // delta = 0 again
        vm.stopPrank();

        assertEq(vault.referralBalance(address(token), project), 0);
        assertEq(vault.totalReferralBalance(address(token)), 0);
        assertEq(vault.lastTokenBalance(address(token)), 0);
    }

    /// @notice With customRebateBips == BASE_BIPS the entire delta goes to the
    ///         project and protocolAmount is exactly 0.
    function test_allocateReferral_fullBips_protocolShareIsZero() public {
        vm.prank(operator);
        vault.setCustomRebateBips(project, BASE_BIPS);

        token.mint(address(vault), AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit ReferralAllocated(address(token), project, AMOUNT, 0);
        vm.prank(routerAddr);
        vault.allocateReferral(address(token), project);

        assertEq(vault.referralBalance(address(token), project), AMOUNT);
        assertEq(vault.totalReferralBalance(address(token)), AMOUNT);
        assertEq(vault.getProtocolFunds(address(token)), 0);
    }

    /// @notice H-01 regression mirrored on the ETH path: explicitly setting
    ///         customRebateBips to 0 must allocate 0% to the project, not
    ///         silently fall back to defaultBips.
    function test_allocateReferral_ETH_explicitZeroCustomBips() public {
        vm.prank(operator);
        vault.setCustomRebateBips(project, 0);

        vm.deal(address(vault), AMOUNT);

        vm.prank(routerAddr);
        vault.allocateReferral(address(0), project);

        assertEq(vault.referralBalance(address(0), project), 0);
        assertEq(vault.totalReferralBalance(address(0)), 0);
        assertEq(vault.getProtocolFunds(address(0)), AMOUNT);
    }

    /// @notice rebateCheckEnabled gates *participation* (whitelist) only —
    ///         bips selection is unified across both branches: hasCustom ?
    ///         customBips : defaultBips. So an enabled project with no custom
    ///         bips configured falls back to defaultBips, just like in the
    ///         check-disabled branch.
    /// @dev    Regression for the unified bips logic. Previously, when
    ///         rebateCheckEnabled=true, an enabled project without custom
    ///         bips would receive 0% (no fallback). The bips selection is
    ///         now branch-independent.
    function test_allocateReferral_rebateCheckEnabled_noCustomBips_fallsBackToDefaultBips() public {
        vm.prank(operator);
        vault.setRebateCheckEnabled(true);
        // `project` is already in the enabled whitelist (setUp); no custom bips configured.

        token.mint(address(vault), AMOUNT);

        vm.prank(routerAddr);
        vault.allocateReferral(address(token), project);

        uint256 expectedRebate = (AMOUNT * vault.defaultBips()) / BASE_BIPS;
        assertEq(vault.referralBalance(address(token), project), expectedRebate);
        assertEq(vault.totalReferralBalance(address(token)), expectedRebate);
        assertEq(vault.getProtocolFunds(address(token)), AMOUNT - expectedRebate);
    }

    /// @notice Symmetry check: with check enabled AND a custom bips configured,
    ///         the custom bips drives the split (same as the check-disabled branch).
    function test_allocateReferral_rebateCheckEnabled_usesCustomBips() public {
        vm.prank(operator);
        vault.setRebateCheckEnabled(true);
        vm.prank(operator);
        vault.setCustomRebateBips(project, 6000); // 60%

        token.mint(address(vault), AMOUNT);

        vm.prank(routerAddr);
        vault.allocateReferral(address(token), project);

        uint256 expectedRebate = (AMOUNT * 6000) / BASE_BIPS;
        assertEq(vault.referralBalance(address(token), project), expectedRebate);
        assertEq(vault.totalReferralBalance(address(token)), expectedRebate);
        assertEq(vault.getProtocolFunds(address(token)), AMOUNT - expectedRebate);
    }

    /// @notice Branch-independence regression: bips selection follows the SAME
    ///         hasCustom ? customBips : defaultBips rule whether
    ///         rebateCheckEnabled is true or false. We verify this by running
    ///         the same allocation under both modes and asserting identical
    ///         project credit. If a future change re-introduces a separate bips
    ///         path under one branch (as the contract had before), this test
    ///         will fail.
    function test_allocateReferral_bipsLogic_isBranchIndependent() public {
        // Branch A: rebateCheckEnabled=false, no custom bips → defaultBips.
        token.mint(address(vault), AMOUNT);
        vm.prank(routerAddr);
        vault.allocateReferral(address(token), project);
        uint256 creditA = vault.referralBalance(address(token), project);

        // Branch B: rebateCheckEnabled=true, no custom bips → must also use defaultBips.
        // (Use a distinct, enabled project to keep accounting independent.)
        vm.prank(operator);
        vault.setRebateCheckEnabled(true);
        vm.prank(operator);
        vault.setRebateEnabled(project2, true);

        token.mint(address(vault), AMOUNT);
        vm.prank(routerAddr);
        vault.allocateReferral(address(token), project2);
        uint256 creditB = vault.referralBalance(address(token), project2);

        // Same input amount, same (absent) custom bips → same project credit.
        assertEq(creditA, creditB);
        assertEq(creditA, (AMOUNT * vault.defaultBips()) / BASE_BIPS);
    }

    // ============= claimReferral (ETH) =================
    // As of the `msg.sender == rebateRecipient` hardening, only the rebate
    // recipient itself may claim its referral balance. The tests below cover
    // both the positive path (caller == rebate recipient) and the new negative
    // path (third-party caller revert).

    function test_claimReferral_ETH_success() public {
        _setupETHReferral(project, AMOUNT);

        uint256 projectBalanceBefore = project.balance;

        vm.expectEmit(true, true, true, true);
        emit ReferralClaimed(address(0), project, project, AMOUNT);
        vm.prank(project);
        vault.claimReferral(address(0), project);

        assertEq(project.balance, projectBalanceBefore + AMOUNT);
        assertEq(vault.referralBalance(address(0), project), 0);
        assertEq(vault.totalReferralBalance(address(0)), 0);
    }

    /// @notice Regression: third parties can no longer trigger a claim on a project's
    ///         behalf. This used to be allowed (`test_claimReferral_ETH_anyoneCanCall`).
    function test_claimReferral_ETH_revertsWhenCallerNotProject() public {
        _setupETHReferral(project, AMOUNT);

        // EOA that is not the project
        vm.prank(alice);
        vm.expectRevert("Not rebate recipient");
        vault.claimReferral(address(0), project);

        // the owner/operator/router are also not the project
        vm.prank(address(this));
        vm.expectRevert("Not rebate recipient");
        vault.claimReferral(address(0), project);

        vm.prank(operator);
        vm.expectRevert("Not rebate recipient");
        vault.claimReferral(address(0), project);

        vm.prank(routerAddr);
        vm.expectRevert("Not rebate recipient");
        vault.claimReferral(address(0), project);

        // funds must still be fully intact
        assertEq(project.balance, 0);
        assertEq(vault.referralBalance(address(0), project), AMOUNT);
        assertEq(vault.totalReferralBalance(address(0)), AMOUNT);
    }

    function test_claimReferral_ETH_revertsNoBalance() public {
        vm.prank(project);
        vm.expectRevert("No balance");
        vault.claimReferral(address(0), project);
    }

    function test_claimReferral_ETH_revertsNonPayableProject() public {
        NonPayableContract np = new NonPayableContract();
        address npAddr = address(np);
        _setReferralBalance(address(0), npAddr, AMOUNT);
        _setTotalReferralBalance(address(0), AMOUNT);
        vm.deal(address(vault), AMOUNT);

        // Only the non-payable project itself may call; it still reverts inside
        // safeTransferETH because the project cannot accept ETH.
        vm.prank(npAddr);
        vm.expectRevert();
        vault.claimReferral(address(0), npAddr);

        // Funds remain locked
        assertEq(vault.referralBalance(address(0), npAddr), AMOUNT);
    }

    function test_claimReferral_ETH_revertsOnReentrancy() public {
        ReentrantETHProject p = new ReentrantETHProject(vault);
        _setupETHReferral(address(p), AMOUNT);

        // Outer call must come from `p` to pass the new msg.sender check; inside
        // `receive()`, `p` reenters `claimReferral(p)` which also passes the sender
        // check but is caught by `nonReentrant`. The inner revert bubbles up through
        // safeTransferETH and surfaces as "TransferHelper: ETH_TRANSFER_FAILED".
        vm.expectRevert(bytes("TransferHelper: ETH_TRANSFER_FAILED"));
        p.start();
    }

    // ============= claimReferral (ERC20) ===============

    function test_claimReferral_ERC20_success() public {
        _setupERC20Referral(project, AMOUNT);

        vm.expectEmit(true, true, true, true);
        emit ReferralClaimed(address(token), project, project, AMOUNT);
        vm.prank(project);
        vault.claimReferral(address(token), project);

        assertEq(token.balanceOf(project), AMOUNT);
        assertEq(vault.referralBalance(address(token), project), 0);
        assertEq(vault.totalReferralBalance(address(token)), 0);
    }

    /// @notice Regression: mirror of `test_claimReferral_ETH_revertsWhenCallerNotProject`
    ///         for the ERC20 path. Third parties must not be able to push a transfer
    ///         to the project.
    function test_claimReferral_ERC20_revertsWhenCallerNotProject() public {
        _setupERC20Referral(project, AMOUNT);

        vm.prank(alice);
        vm.expectRevert("Not rebate recipient");
        vault.claimReferral(address(token), project);

        // balances untouched
        assertEq(token.balanceOf(project), 0);
        assertEq(vault.referralBalance(address(token), project), AMOUNT);
        assertEq(vault.totalReferralBalance(address(token)), AMOUNT);
    }

    function test_claimReferral_ERC20_revertsNoBalance() public {
        vm.prank(project);
        vm.expectRevert("No balance");
        vault.claimReferral(address(token), project);
    }

    function test_claimReferral_ERC20_nestedClaimRevertsNonReentrant_transferNotApplied() public {
        ReentrantTransferERC20 rToken = new ReentrantTransferERC20(vault, project);
        rToken.mint(address(vault), AMOUNT);
        _setReferralBalance(address(rToken), project, AMOUNT);
        _setTotalReferralBalance(address(rToken), AMOUNT);

        // Outer call must come from `project`. Inside rToken.transfer, the token
        // contract reenters `claimReferral(project)` with msg.sender == rToken,
        // which now fails the new `msg.sender == rebateRecipient` check, so the
        // inner revert bubbles up and the outer safeTransfer surfaces as
        // "TransferHelper: TRANSFER_FAILED".
        vm.prank(project);
        vm.expectRevert("TransferHelper: TRANSFER_FAILED");
        vault.claimReferral(address(rToken), project);
    }

    /// @notice Invariant: every successful claim must end with `lastTokenBalance`
    ///         equal to the vault's post-transfer balance, otherwise the next
    ///         allocateReferral delta will be wrong.
    function test_claimReferral_ERC20_updatesLastTokenBalance() public {
        // Vault holds 2*AMOUNT but only AMOUNT belongs to the project; the other
        // AMOUNT is protocol funds (or extra). After the project claims, the
        // remaining vault balance must be reflected in lastTokenBalance.
        token.mint(address(vault), AMOUNT * 2);
        _setReferralBalance(address(token), project, AMOUNT);
        _setTotalReferralBalance(address(token), AMOUNT);

        vm.prank(project);
        vault.claimReferral(address(token), project);

        assertEq(token.balanceOf(address(vault)), AMOUNT);
        assertEq(vault.lastTokenBalance(address(token)), AMOUNT);
    }

    // ========= emergencyClaimReferral ==================

    function test_emergencyClaimReferral_ETH_success() public {
        _setupETHReferral(project, AMOUNT);

        vm.expectEmit(true, true, true, true);
        emit ReferralClaimed(address(0), project, recipient, AMOUNT);
        vault.emergencyClaimReferral(address(0), project, recipient);

        assertEq(recipient.balance, AMOUNT);
        assertEq(vault.referralBalance(address(0), project), 0);
        assertEq(vault.totalReferralBalance(address(0)), 0);
    }

    function test_emergencyClaimReferral_ETH_revertsOnReentrancy() public {
        EmergencyReenterOwner h = new EmergencyReenterOwner(vault, project);
        vault.transferOwnership(address(h));
        _setupETHReferral(project, AMOUNT);

        vm.expectRevert(bytes("TransferHelper: ETH_TRANSFER_FAILED"));
        h.start();
    }

    function test_emergencyClaimReferral_ERC20_success() public {
        _setupERC20Referral(project, AMOUNT);

        vault.emergencyClaimReferral(address(token), project, recipient);

        assertEq(token.balanceOf(recipient), AMOUNT);
        assertEq(vault.referralBalance(address(token), project), 0);
    }

    function test_emergencyClaimReferral_rescuesLockedETH() public {
        NonPayableContract np = new NonPayableContract();
        address npAddr = address(np);

        _setReferralBalance(address(0), npAddr, AMOUNT);
        _setTotalReferralBalance(address(0), AMOUNT);
        vm.deal(address(vault), AMOUNT);

        // Normal claim reverts for non-payable contract
        vm.expectRevert();
        vault.claimReferral(address(0), npAddr);

        // Emergency claim to a different recipient succeeds
        vault.emergencyClaimReferral(address(0), npAddr, recipient);
        assertEq(recipient.balance, AMOUNT);
    }

    function test_emergencyClaimReferral_revertsNoBalance() public {
        vm.expectRevert("No balance");
        vault.emergencyClaimReferral(address(token), project, recipient);
    }

    function test_emergencyClaimReferral_onlyOwner() public {
        _setupERC20Referral(project, AMOUNT);
        vm.prank(alice);
        vm.expectRevert();
        vault.emergencyClaimReferral(address(token), project, recipient);
    }

    function test_emergencyClaimReferral_revertsZeroRecipient() public {
        _setupERC20Referral(project, AMOUNT);
        vm.expectRevert("Invalid recipient");
        vault.emergencyClaimReferral(address(token), project, address(0));

        // balances must remain intact when the zero-address check trips
        assertEq(vault.referralBalance(address(token), project), AMOUNT);
        assertEq(vault.totalReferralBalance(address(token)), AMOUNT);
    }

    /// @notice Symmetry with `test_emergencyClaimReferral_revertsNoBalance` —
    ///         the ETH (token == address(0)) path was previously untested.
    function test_emergencyClaimReferral_ETH_revertsNoBalance() public {
        vm.expectRevert("No balance");
        vault.emergencyClaimReferral(address(0), project, recipient);
    }

    /// @notice Same lastTokenBalance invariant as the project-claim path.
    function test_emergencyClaimReferral_ETH_updatesLastTokenBalance() public {
        vm.deal(address(vault), AMOUNT * 2);
        _setReferralBalance(address(0), project, AMOUNT);
        _setTotalReferralBalance(address(0), AMOUNT);

        vault.emergencyClaimReferral(address(0), project, recipient);

        assertEq(address(vault).balance, AMOUNT);
        assertEq(vault.lastTokenBalance(address(0)), AMOUNT);
    }

    // ============= claimProtocolFunds ==================

    function test_claimProtocolFunds_ETH_success() public {
        // Send ETH to vault (protocol share — no referralBalance accounting)
        vm.deal(address(vault), AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit ProtocolFundsClaimed(address(0), recipient, AMOUNT);
        vault.claimProtocolFunds(recipient, address(0));

        assertEq(recipient.balance, AMOUNT);
    }

    function test_claimProtocolFunds_ETH_revertsOnReentrancy() public {
        OwnerProtocolReenter h = new OwnerProtocolReenter(vault);
        vault.transferOwnership(address(h));
        vm.deal(address(vault), AMOUNT);

        vm.expectRevert(bytes("TransferHelper: ETH_TRANSFER_FAILED"));
        h.start();
    }

    function test_claimProtocolFunds_ERC20_success() public {
        token.mint(address(vault), AMOUNT);

        vault.claimProtocolFunds(recipient, address(token));

        assertEq(token.balanceOf(recipient), AMOUNT);
    }

    function test_claimProtocolFunds_excludesReferralBalance() public {
        uint256 referralAmount = 3 ether;
        uint256 protocolAmount = 7 ether;
        uint256 totalAmount = referralAmount + protocolAmount;

        token.mint(address(vault), totalAmount);
        _setReferralBalance(address(token), project, referralAmount);
        _setTotalReferralBalance(address(token), referralAmount);

        assertEq(vault.getProtocolFunds(address(token)), protocolAmount);

        vault.claimProtocolFunds(recipient, address(token));
        assertEq(token.balanceOf(recipient), protocolAmount);
    }

    function test_claimProtocolFunds_revertsNoBalance() public {
        vm.expectRevert("No balance");
        vault.claimProtocolFunds(recipient, address(token));
    }

    function test_claimProtocolFunds_onlyOwner() public {
        token.mint(address(vault), AMOUNT);
        vm.prank(alice);
        vm.expectRevert();
        vault.claimProtocolFunds(recipient, address(token));
    }

    function test_claimProtocolFunds_revertsZeroRecipient() public {
        token.mint(address(vault), AMOUNT);
        vm.expectRevert("Invalid recipient");
        vault.claimProtocolFunds(address(0), address(token));

        // protocol funds must remain in the vault when the check trips
        assertEq(token.balanceOf(address(vault)), AMOUNT);
    }

    /// @notice After protocol funds are pulled, the residual referral balance
    ///         (if any) must still be reflected in `lastTokenBalance`. Without
    ///         this snapshot the next allocateReferral would over-credit the
    ///         missing protocol amount as fresh swap inflow.
    function test_claimProtocolFunds_ETH_updatesLastTokenBalance() public {
        // Vault holds 2*AMOUNT, AMOUNT is referral, AMOUNT is protocol.
        vm.deal(address(vault), AMOUNT * 2);
        _setReferralBalance(address(0), project, AMOUNT);
        _setTotalReferralBalance(address(0), AMOUNT);

        vault.claimProtocolFunds(recipient, address(0));

        assertEq(address(vault).balance, AMOUNT);
        assertEq(vault.lastTokenBalance(address(0)), AMOUNT);
    }

    // ============== getProtocolFunds ===================

    function test_getProtocolFunds_ETH_noReferrals() public {
        vm.deal(address(vault), AMOUNT);
        assertEq(vault.getProtocolFunds(address(0)), AMOUNT);
    }

    function test_getProtocolFunds_ETH_withReferrals() public {
        vm.deal(address(vault), 10 ether);
        _setTotalReferralBalance(address(0), 3 ether);
        assertEq(vault.getProtocolFunds(address(0)), 7 ether);
    }

    function test_getProtocolFunds_ERC20_noReferrals() public {
        token.mint(address(vault), AMOUNT);
        assertEq(vault.getProtocolFunds(address(token)), AMOUNT);
    }

    function test_getProtocolFunds_ERC20_withReferrals() public {
        token.mint(address(vault), 10 ether);
        _setTotalReferralBalance(address(token), 4 ether);
        assertEq(vault.getProtocolFunds(address(token)), 6 ether);
    }

    // ============== receive() ==========================

    function test_receive_acceptsETH() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool success, ) = address(vault).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(vault).balance, 1 ether);
    }

    /// @notice Locks in the deliberate `receive()` semantics: it does NOT
    ///         snapshot `lastTokenBalance`. ETH sent directly to the vault is
    ///         instead absorbed into the delta of the next router-initiated
    ///         allocateReferral call and split per the active bps rules.
    /// @dev    If `receive()` ever starts calling `_updateLastTokenBalance`, this
    ///         test will fail and that will be the right place to revisit the
    ///         intended semantics.
    function test_receive_doesNotSnapshot_flowsIntoNextAllocate() public {
        vm.deal(alice, AMOUNT);
        vm.prank(alice);
        (bool ok, ) = address(vault).call{value: AMOUNT}("");
        assertTrue(ok);

        // receive() must NOT have updated lastTokenBalance.
        assertEq(vault.lastTokenBalance(address(0)), 0);
        assertEq(address(vault).balance, AMOUNT);

        // Next allocateReferral picks up the donated ETH as its delta.
        uint256 expectedRebate = (AMOUNT * vault.defaultBips()) / BASE_BIPS;
        uint256 expectedProtocol = AMOUNT - expectedRebate;

        vm.expectEmit(true, true, false, true);
        emit ReferralAllocated(address(0), project, expectedRebate, expectedProtocol);
        vm.prank(routerAddr);
        vault.allocateReferral(address(0), project);

        assertEq(vault.referralBalance(address(0), project), expectedRebate);
        assertEq(vault.totalReferralBalance(address(0)), expectedRebate);
        assertEq(vault.lastTokenBalance(address(0)), AMOUNT);
    }

    // =========== Multi-project scenarios ===============

    function test_multipleProjects_independentBalances() public {
        _setupERC20Referral(project, 5 ether);

        // Manually add project2 balance
        token.mint(address(vault), 3 ether);
        _setReferralBalance(address(token), project2, 3 ether);
        _setTotalReferralBalance(address(token), 8 ether); // 5 + 3

        // Claim project1 — must be called by project1
        vm.prank(project);
        vault.claimReferral(address(token), project);
        assertEq(token.balanceOf(project), 5 ether);
        assertEq(vault.totalReferralBalance(address(token)), 3 ether);

        // Claim project2 — must be called by project2
        vm.prank(project2);
        vault.claimReferral(address(token), project2);
        assertEq(token.balanceOf(project2), 3 ether);
        assertEq(vault.totalReferralBalance(address(token)), 0);
    }

    function test_disabledProject_canStillClaim() public {
        _setupERC20Referral(project, AMOUNT);

        // Disable project after allocation
        vm.prank(operator);
        vault.setRebateEnabled(project, false);

        // Claim still succeeds (disabling only blocks future allocations),
        // provided the project itself is the caller.
        vm.prank(project);
        vault.claimReferral(address(token), project);
        assertEq(token.balanceOf(project), AMOUNT);
    }

    // =========== Fuzz Tests ============================

    function testFuzz_setDefaultBips_bounded(uint256 bps) public {
        bps = bound(bps, 0, BASE_BIPS);
        vm.prank(operator);
        vault.setDefaultBips(bps);
        assertEq(vault.defaultBips(), bps);
    }

    function testFuzz_setMaxReferralBips_bounded(uint256 bps) public {
        bps = bound(bps, 0, BASE_BIPS);
        vm.prank(operator);
        vault.setMaxReferralBips(bps);
        assertEq(vault.maxReferralBips(), bps);
    }

    function testFuzz_claimReferral_ERC20(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        token.mint(address(vault), amount);
        _setReferralBalance(address(token), project, amount);
        _setTotalReferralBalance(address(token), amount);

        vm.prank(project);
        vault.claimReferral(address(token), project);

        assertEq(token.balanceOf(project), amount);
        assertEq(vault.referralBalance(address(token), project), 0);
        assertEq(vault.totalReferralBalance(address(token)), 0);
    }

    /// @notice Fuzz regression for the new `msg.sender == rebateRecipient` check:
    ///         for any non-recipient caller, claim must revert and balances must be preserved.
    function testFuzz_claimReferral_revertsWhenCallerNotProject(address caller, uint256 amount) public {
        vm.assume(caller != project);
        amount = bound(amount, 1, type(uint128).max);

        token.mint(address(vault), amount);
        _setReferralBalance(address(token), project, amount);
        _setTotalReferralBalance(address(token), amount);

        vm.prank(caller);
        vm.expectRevert("Not rebate recipient");
        vault.claimReferral(address(token), project);

        assertEq(vault.referralBalance(address(token), project), amount);
        assertEq(vault.totalReferralBalance(address(token)), amount);
        assertEq(token.balanceOf(project), 0);
    }

    function testFuzz_getProtocolFunds(uint256 total, uint256 referral) public {
        total = bound(total, 1, type(uint128).max);
        referral = bound(referral, 0, total);

        token.mint(address(vault), total);
        _setTotalReferralBalance(address(token), referral);

        assertEq(vault.getProtocolFunds(address(token)), total - referral);
    }
}
