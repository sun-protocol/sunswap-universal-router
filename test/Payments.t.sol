// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ActionConstants} from "v4-periphery/src/libraries/ActionConstants.sol";
import {BipsLibrary} from "v4-periphery/src/libraries/BipsLibrary.sol";

import {Payments} from "src/modules/Payments.sol";
import {Constants} from "src/libraries/Constants.sol";
import {RouterImmutables, RouterParameters} from "src/base/RouterImmutables.sol";
import {ReferralVault} from "src/ReferralVault.sol";

import {MockERC20} from "./mock/MockERC20.sol";

/*//////////////////////////////////////////////////////////////
                              Harness
//////////////////////////////////////////////////////////////*/

/// @dev Concrete Payments implementation that exposes the internal helpers as
///      external functions so Foundry can exercise them directly. Only WETH9
///      needs to be a real address; everything else in RouterParameters is
///      zeroed out since it's unused by the tested functions.
contract PaymentsHarness is Payments {
    constructor(RouterParameters memory params) RouterImmutables(params) {}

    function pay_(address token, address recipient, uint256 value) external {
        pay(token, recipient, value);
    }

    function payPortion_(address token, address recipient, uint256 bips) external {
        payPortion(token, recipient, bips);
    }

    function payReferral_(
        address token,
        address rebateRecipient,
        uint256 bips,
        address referralVault
    ) external {
        payReferral(token, rebateRecipient, bips, referralVault);
    }

    function sweep_(address token, address recipient, uint256 amountMinimum) external {
        sweep(token, recipient, amountMinimum);
    }

    function wrapETH_(address recipient, uint256 amount) external {
        wrapETH(recipient, amount);
    }

    function unwrapWETH9_(address recipient, uint256 amountMinimum) external {
        unwrapWETH9(recipient, amountMinimum);
    }

    receive() external payable {}
}

/*//////////////////////////////////////////////////////////////
                         Test-only helpers
//////////////////////////////////////////////////////////////*/

/// @dev Cannot receive ETH (no `receive()`, no `fallback()`). Used to
///      force `safeTransferETH` to return `false` so we can verify that
///      the new `require(success, "...")` pattern reverts rather than
///      silently swallowing the failure.
contract NonPayableRecipient {
    // intentionally empty
}

/// @dev Tracks ETH received to prove the happy path really delivered funds.
contract PayableRecipient {
    uint256 public received;

    receive() external payable {
        received += msg.value;
    }
}

/*//////////////////////////////////////////////////////////////
                               Tests
//////////////////////////////////////////////////////////////*/

contract PaymentsTest is Test {
    PaymentsHarness harness;
    WETH weth9;
    MockERC20 token;
    ReferralVault vault;

    address alice = makeAddr("alice");
    address project = makeAddr("project");
    address operator = makeAddr("operator");

    uint256 constant AMOUNT = 10 ether;
    uint256 constant BASE_BIPS = 10_000;

    function setUp() public {
        weth9 = new WETH();
        token = new MockERC20();

        RouterParameters memory params = RouterParameters({
            permit2: address(0),
            weth9: address(weth9),
            v1Factory: address(0),
            v2Factory: address(0),
            v3Factory: address(0),
            v3Deployer: address(0),
            v2InitCodeHash: bytes32(0),
            v3InitCodeHash: bytes32(0),
            stableFactory: address(0),
            v4Vault: address(0),
            v4ClPoolManager: address(0),
            v3NFTPositionManager: address(0),
            v4ClPositionManager: address(0),
            safeVault: address(0)
        });
        harness = new PaymentsHarness(params);

        // payReferral integration: spin up a real ReferralVault routed through
        // the harness (so the harness plays the Router role).
        vault = new ReferralVault(operator, address(harness));

        vm.prank(operator);
        vault.setRebateEnabled(project, true);

        vm.prank(operator);
        vault.setMaxReferralBips(BASE_BIPS);
    }

    /*//////////////////////////////////////////////////////////////
                         Section A — pay (ETH)
       These tests exercise `safeTransferETH` directly through
       `pay`. The positive case proves the new bool return value
       still lets funds flow; the negative case proves that a
       failing transfer now reverts instead of being swallowed.
    //////////////////////////////////////////////////////////////*/

    function test_pay_ETH_sendsToEOA() public {
        vm.deal(address(harness), AMOUNT);
        uint256 before = alice.balance;

        harness.pay_(Constants.ETH, alice, AMOUNT);

        assertEq(alice.balance - before, AMOUNT);
        assertEq(address(harness).balance, 0);
    }

    function test_pay_ETH_sendsToPayableContract() public {
        PayableRecipient r = new PayableRecipient();
        vm.deal(address(harness), AMOUNT);

        harness.pay_(Constants.ETH, address(r), AMOUNT);

        assertEq(r.received(), AMOUNT);
        assertEq(address(r).balance, AMOUNT);
    }

    /// @notice Regression for the safeTransferETH change. Before the refactor,
    ///         `safeTransferETH` returned `void` and a failing transfer would
    ///         be silently swallowed. Now it returns `bool` and `pay` wraps it
    ///         in `require(...)`, so a non-payable recipient must cause the
    ///         entire tx to revert and funds must stay at the harness.
    function test_pay_ETH_revertsOnNonPayableRecipient() public {
        NonPayableRecipient np = new NonPayableRecipient();
        vm.deal(address(harness), AMOUNT);

        vm.expectRevert("TransferHelper: ETH_TRANSFER_FAILED");
        harness.pay_(Constants.ETH, address(np), AMOUNT);

        assertEq(address(np).balance, 0);
        assertEq(address(harness).balance, AMOUNT);
    }

    function test_pay_ETH_revertsWhenInsufficientETH() public {
        // harness has 0 ETH; require inside the low-level .call reverts because
        // the EVM prevents spending more value than the contract owns.
        vm.expectRevert();
        harness.pay_(Constants.ETH, alice, AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                         Section B — pay (ERC20)
    //////////////////////////////////////////////////////////////*/

    function test_pay_ERC20_success() public {
        token.mint(address(harness), AMOUNT);

        harness.pay_(address(token), alice, AMOUNT);

        assertEq(token.balanceOf(alice), AMOUNT);
        assertEq(token.balanceOf(address(harness)), 0);
    }

    function test_pay_ERC20_contractBalanceSentinel() public {
        token.mint(address(harness), AMOUNT);

        harness.pay_(address(token), alice, ActionConstants.CONTRACT_BALANCE);

        assertEq(token.balanceOf(alice), AMOUNT);
        assertEq(token.balanceOf(address(harness)), 0);
    }

    function test_pay_ERC20_revertsOnInsufficientBalance() public {
        // solmate ERC20 transfer will underflow; the outer require surfaces as
        // "TransferHelper: TRANSFER_FAILED".
        vm.expectRevert();
        harness.pay_(address(token), alice, AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                       Section C — payPortion (ETH)
    //////////////////////////////////////////////////////////////*/

    function test_payPortion_ETH_half() public {
        vm.deal(address(harness), AMOUNT);

        harness.payPortion_(Constants.ETH, alice, 5_000); // 50%

        assertEq(alice.balance, AMOUNT / 2);
        assertEq(address(harness).balance, AMOUNT / 2);
    }

    function test_payPortion_ETH_full() public {
        vm.deal(address(harness), AMOUNT);

        harness.payPortion_(Constants.ETH, alice, BASE_BIPS);

        assertEq(alice.balance, AMOUNT);
        assertEq(address(harness).balance, 0);
    }

    function test_payPortion_ETH_zeroBipsToEOA_noop() public {
        vm.deal(address(harness), AMOUNT);

        // 0% → amount = 0 → safeTransferETH(alice, 0) still returns true for an
        // EOA, so the require passes and the call is effectively a no-op.
        harness.payPortion_(Constants.ETH, alice, 0);

        assertEq(alice.balance, 0);
        assertEq(address(harness).balance, AMOUNT);
    }

    /// @notice Edge case: even with amount = 0, `safeTransferETH` performs a
    ///         0-value empty-calldata call. Against a contract with no
    ///         `receive`/`fallback`, this returns success=false and the new
    ///         `require` correctly reverts. This documents that zero-amount
    ///         ETH transfers are NOT silently no-ops against non-payable
    ///         contracts.
    function test_payPortion_ETH_zeroBipsToNonPayable_reverts() public {
        NonPayableRecipient np = new NonPayableRecipient();
        vm.deal(address(harness), AMOUNT);

        vm.expectRevert("TransferHelper: ETH_TRANSFER_FAILED");
        harness.payPortion_(Constants.ETH, address(np), 0);

        assertEq(address(harness).balance, AMOUNT);
    }

    function test_payPortion_ETH_revertsOnNonPayable() public {
        NonPayableRecipient np = new NonPayableRecipient();
        vm.deal(address(harness), AMOUNT);

        vm.expectRevert("TransferHelper: ETH_TRANSFER_FAILED");
        harness.payPortion_(Constants.ETH, address(np), 5_000);

        assertEq(address(harness).balance, AMOUNT);
    }

    function test_payPortion_ETH_revertsWhenBipsTooLarge() public {
        vm.deal(address(harness), AMOUNT);
        vm.expectRevert(BipsLibrary.InvalidBips.selector);
        harness.payPortion_(Constants.ETH, alice, BASE_BIPS + 1);
    }

    /*//////////////////////////////////////////////////////////////
                      Section D — payPortion (ERC20)
    //////////////////////////////////////////////////////////////*/

    function test_payPortion_ERC20_half() public {
        token.mint(address(harness), AMOUNT);

        harness.payPortion_(address(token), alice, 5_000);

        assertEq(token.balanceOf(alice), AMOUNT / 2);
        assertEq(token.balanceOf(address(harness)), AMOUNT / 2);
    }

    function test_payPortion_ERC20_zeroBips_noop() public {
        token.mint(address(harness), AMOUNT);

        harness.payPortion_(address(token), alice, 0);

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(harness)), AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                         Section E — sweep (ETH)
       Verifies the `if (balance > 0)` guard and that non-zero
       sweeps propagate the safeTransferETH return through the
       outer require.
    //////////////////////////////////////////////////////////////*/

    function test_sweep_ETH_success() public {
        vm.deal(address(harness), AMOUNT);

        harness.sweep_(Constants.ETH, alice, AMOUNT);

        assertEq(alice.balance, AMOUNT);
        assertEq(address(harness).balance, 0);
    }

    function test_sweep_ETH_revertsWhenBelowMin() public {
        vm.deal(address(harness), AMOUNT - 1);
        vm.expectRevert(Payments.InsufficientETH.selector);
        harness.sweep_(Constants.ETH, alice, AMOUNT);
    }

    /// @notice Regression: `sweep` short-circuits when balance is 0 so it can
    ///         safely be called against a non-payable recipient without
    ///         reverting. This must hold after the safeTransferETH refactor
    ///         since UniversalRouter.executeCommands runs a `sweep` in its
    ///         finalizer after every tx.
    function test_sweep_ETH_noopWhenZeroBalance() public {
        NonPayableRecipient np = new NonPayableRecipient();

        // no revert, no transfer attempt, no state change
        harness.sweep_(Constants.ETH, address(np), 0);

        assertEq(address(np).balance, 0);
        assertEq(address(harness).balance, 0);
    }

    function test_sweep_ETH_revertsOnNonPayableWhenBalanceExists() public {
        NonPayableRecipient np = new NonPayableRecipient();
        vm.deal(address(harness), AMOUNT);

        vm.expectRevert("TransferHelper: ETH_TRANSFER_FAILED");
        harness.sweep_(Constants.ETH, address(np), 0);

        assertEq(address(harness).balance, AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                        Section F — sweep (ERC20)
    //////////////////////////////////////////////////////////////*/

    function test_sweep_ERC20_success() public {
        token.mint(address(harness), AMOUNT);

        harness.sweep_(address(token), alice, AMOUNT);

        assertEq(token.balanceOf(alice), AMOUNT);
        assertEq(token.balanceOf(address(harness)), 0);
    }

    function test_sweep_ERC20_revertsBelowMin() public {
        token.mint(address(harness), AMOUNT - 1);
        vm.expectRevert(Payments.InsufficientToken.selector);
        harness.sweep_(address(token), alice, AMOUNT);
    }

    function test_sweep_ERC20_noopWhenZeroBalance() public {
        harness.sweep_(address(token), alice, 0);
        assertEq(token.balanceOf(alice), 0);
    }

    /*//////////////////////////////////////////////////////////////
                           Section G — wrapETH
    //////////////////////////////////////////////////////////////*/

    function test_wrapETH_amount_recipientIsOther() public {
        vm.deal(address(harness), AMOUNT);

        harness.wrapETH_(alice, AMOUNT);

        assertEq(weth9.balanceOf(alice), AMOUNT);
        assertEq(weth9.balanceOf(address(harness)), 0);
        assertEq(address(harness).balance, 0);
    }

    function test_wrapETH_amount_recipientIsSelf_keepsWETH() public {
        vm.deal(address(harness), AMOUNT);

        harness.wrapETH_(address(harness), AMOUNT);

        assertEq(weth9.balanceOf(address(harness)), AMOUNT);
        assertEq(weth9.balanceOf(alice), 0);
    }

    function test_wrapETH_contractBalanceSentinel_usesFullBalance() public {
        vm.deal(address(harness), AMOUNT);

        harness.wrapETH_(alice, ActionConstants.CONTRACT_BALANCE);

        assertEq(weth9.balanceOf(alice), AMOUNT);
        assertEq(address(harness).balance, 0);
    }

    function test_wrapETH_revertsWhenAmountExceedsBalance() public {
        vm.deal(address(harness), AMOUNT - 1);
        vm.expectRevert(Payments.InsufficientETH.selector);
        harness.wrapETH_(alice, AMOUNT);
    }

    function test_wrapETH_zeroAmount_noop() public {
        harness.wrapETH_(alice, 0);
        assertEq(weth9.balanceOf(alice), 0);
        assertEq(address(harness).balance, 0);
    }

    /*//////////////////////////////////////////////////////////////
                          Section H — unwrapWETH9
       unwrapWETH9 is the 4th call site for safeTransferETH and
       behaves analogously to `pay`: the new bool return must flip
       a require-style revert.
    //////////////////////////////////////////////////////////////*/

    function test_unwrapWETH9_recipientIsSelf_keepsETH() public {
        // fund harness with WETH first
        vm.deal(address(harness), AMOUNT);
        harness.wrapETH_(address(harness), AMOUNT);

        harness.unwrapWETH9_(address(harness), AMOUNT);

        assertEq(weth9.balanceOf(address(harness)), 0);
        assertEq(address(harness).balance, AMOUNT);
    }

    function test_unwrapWETH9_recipientIsOther_sendsETH() public {
        vm.deal(address(harness), AMOUNT);
        harness.wrapETH_(address(harness), AMOUNT);

        harness.unwrapWETH9_(alice, AMOUNT);

        assertEq(weth9.balanceOf(address(harness)), 0);
        assertEq(alice.balance, AMOUNT);
        assertEq(address(harness).balance, 0);
    }

    function test_unwrapWETH9_revertsWhenBelowMin() public {
        vm.expectRevert(Payments.InsufficientETH.selector);
        harness.unwrapWETH9_(alice, AMOUNT);
    }

    function test_unwrapWETH9_zeroBalance_noop() public {
        harness.unwrapWETH9_(alice, 0);
        assertEq(alice.balance, 0);
    }

    /// @notice Regression for the safeTransferETH change applied to
    ///         `unwrapWETH9`. The contract holds WETH, but the destination
    ///         cannot accept the unwrapped ETH. The outer `require` must
    ///         revert and the WETH must NOT be withdrawn to a stuck state
    ///         outside the vault.
    function test_unwrapWETH9_revertsOnNonPayableRecipient() public {
        NonPayableRecipient np = new NonPayableRecipient();
        vm.deal(address(harness), AMOUNT);
        harness.wrapETH_(address(harness), AMOUNT);

        vm.expectRevert("TransferHelper: ETH_TRANSFER_FAILED");
        harness.unwrapWETH9_(address(np), AMOUNT);

        // full tx revert: WETH must be restored on the harness, not dangling.
        assertEq(weth9.balanceOf(address(harness)), AMOUNT);
        assertEq(address(harness).balance, 0);
        assertEq(address(np).balance, 0);
    }

    /*//////////////////////////////////////////////////////////////
                         Section I — payReferral
       End-to-end integration with a real ReferralVault so we can
       confirm the `payPortion → allocateReferral` pipeline still
       delivers the correct split after the safeTransferETH change.
    //////////////////////////////////////////////////////////////*/

    function test_payReferral_ETH_allocatesDefaultSplit() public {
        vm.deal(address(harness), AMOUNT);
        uint256 bips = 1_000; // 10% to the referral vault

        harness.payReferral_(Constants.ETH, project, bips, address(vault));

        uint256 vaultCut = (AMOUNT * bips) / BASE_BIPS;
        assertEq(address(vault).balance, vaultCut);
        assertEq(address(harness).balance, AMOUNT - vaultCut);

        uint256 projectShare = (vaultCut * vault.defaultBips()) / BASE_BIPS;
        assertEq(vault.referralBalance(address(0), project), projectShare);
        assertEq(vault.totalReferralBalance(address(0)), projectShare);
    }

    function test_payReferral_ERC20_allocatesDefaultSplit() public {
        token.mint(address(harness), AMOUNT);
        uint256 bips = 2_500; // 25% to the referral vault

        harness.payReferral_(address(token), project, bips, address(vault));

        uint256 vaultCut = (AMOUNT * bips) / BASE_BIPS;
        assertEq(token.balanceOf(address(vault)), vaultCut);
        assertEq(token.balanceOf(address(harness)), AMOUNT - vaultCut);

        uint256 projectShare = (vaultCut * vault.defaultBips()) / BASE_BIPS;
        assertEq(vault.referralBalance(address(token), project), projectShare);
        assertEq(vault.totalReferralBalance(address(token)), projectShare);
    }

    function test_payReferral_revertsWhenBipsExceedsMax() public {
        vm.prank(operator);
        vault.setMaxReferralBips(500);

        vm.deal(address(harness), AMOUNT);
        vm.expectRevert("Bips exceeds maxReferralBips");
        harness.payReferral_(Constants.ETH, project, 501, address(vault));
    }

    /// @notice Business-decision regression: under the current
    ///         "balance-delta" allocation semantics, `allocateReferral` derives
    ///         `amount = currentBalance - lastTokenBalance`. Any stray funds
    ///         sitting on the vault before the next allocation are
    ///         intentionally **absorbed into the project / protocol split**
    ///         rather than treated as protocol funds.
    /// @dev    This test pins down that decision; reverting to "ignore
    ///         pre-existing balance" semantics in the future will require
    ///         updating this test as well.
    /// @notice After the introduction of `updateLastTokenBalance` before `payPortion`
    ///         in `payReferral`, any pre-existing vault balance (donation / stray
    ///         transfer) is **isolated** rather than absorbed: the snapshot is taken
    ///         right before payPortion, so allocateReferral's delta only counts the
    ///         current round's inflow. The stray balance becomes protocol funds.
    function test_payReferral_isolatesPreExistingVaultBalance() public {
        uint256 strayETH = 100 ether;
        vm.deal(address(vault), strayETH); // stray ETH already at vault (lastTokenBalance == 0)
        vm.deal(address(harness), AMOUNT);

        uint256 bips = 1_000; // 10% to vault
        harness.payReferral_(Constants.ETH, project, bips, address(vault));

        uint256 vaultCut = (AMOUNT * bips) / BASE_BIPS; // amount paid in by harness for this round
        // Only this round's inflow is split per defaultBips.
        uint256 projectShare = (vaultCut * vault.defaultBips()) / BASE_BIPS;

        assertEq(vault.referralBalance(address(0), project), projectShare);
        assertEq(vault.totalReferralBalance(address(0)), projectShare);
        // Snapshot reflects the post-payPortion vault balance (stray + new payPortion).
        assertEq(vault.lastTokenBalance(address(0)), strayETH + vaultCut);

        // Stray ETH is now protocol funds: vault.balance - totalReferralBalance.
        assertEq(vault.getProtocolFunds(address(0)), strayETH + vaultCut - projectShare);
    }

    /*//////////////////////////////////////////////////////////////
                  Section J — Global invariant: fuzz
       Fuzz over (amount, bips) and recipient shape to prove the
       require(bool) wrapping of safeTransferETH correctly mirrors
       the recipient's ability to receive ETH.
    //////////////////////////////////////////////////////////////*/

    function testFuzz_pay_ETH_successForPayableRecipient(uint96 amount) public {
        amount = uint96(bound(uint256(amount), 1, 1_000_000 ether));
        PayableRecipient r = new PayableRecipient();
        vm.deal(address(harness), amount);

        harness.pay_(Constants.ETH, address(r), amount);

        assertEq(r.received(), amount);
        assertEq(address(harness).balance, 0);
    }

    function testFuzz_pay_ETH_revertsForNonPayableRecipient(uint96 amount) public {
        amount = uint96(bound(uint256(amount), 1, 1_000_000 ether));
        NonPayableRecipient np = new NonPayableRecipient();
        vm.deal(address(harness), amount);

        vm.expectRevert("TransferHelper: ETH_TRANSFER_FAILED");
        harness.pay_(Constants.ETH, address(np), amount);

        assertEq(address(np).balance, 0);
        assertEq(address(harness).balance, amount);
    }

    function testFuzz_payPortion_ETH_bipsBounded(uint96 balance, uint16 bips) public {
        balance = uint96(bound(uint256(balance), 0, 1_000_000 ether));
        bips = uint16(bound(uint256(bips), 1, BASE_BIPS));
        vm.deal(address(harness), balance);

        harness.payPortion_(Constants.ETH, alice, bips);

        uint256 expected = (uint256(balance) * bips) / BASE_BIPS;
        assertEq(alice.balance, expected);
        assertEq(address(harness).balance, balance - expected);
    }
}
