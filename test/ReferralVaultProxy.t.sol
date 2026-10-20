// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ReferralVault} from "src/ReferralVault.sol";
import {ReferralVaultProxy} from "src/ReferralVaultProxy.sol";
import {MockERC20} from "./mock/MockERC20.sol";

contract MockReferralRouter {}

/// @dev Unit tests: a minimal contract address plays the router and replays the 3-step
///      `Payments.payReferral` sequence.
contract ReferralVaultProxyTest is Test {
    address admin = makeAddr("admin");
    address vaultOperator = makeAddr("vaultOperator");
    address router;
    address stranger = makeAddr("stranger");
    address rebateRecipient = makeAddr("rebateRecipient");

    ReferralVault vault;
    ReferralVaultProxy proxy;
    MockERC20 token;

    function setUp() public {
        router = address(new MockReferralRouter());
        vault = new ReferralVault(vaultOperator, makeAddr("oldRouter"));
        proxy = new ReferralVaultProxy(admin, address(vault));

        vm.prank(vaultOperator);
        vault.setRouter(address(proxy));
        vm.prank(vaultOperator);
        vault.setMaxReferralBips(1000);

        vm.prank(admin);
        proxy.setRouterAllowed(router, true);

        token = new MockERC20();
    }

    /// @dev Mirrors Payments.payReferral: snapshot -> transfer into proxy -> allocate
    function _payReferralERC20(address caller, uint256 amount) internal {
        token.mint(caller, amount);
        vm.startPrank(caller);
        proxy.updateLastTokenBalance(address(token));
        token.transfer(address(proxy), amount);
        proxy.allocateReferral(address(token), rebateRecipient);
        vm.stopPrank();
    }

    // ========================= constructor =========================

    function test_constructor_setsOwnerAndVault() public view {
        assertEq(proxy.owner(), admin);
        assertEq(proxy.vault(), address(vault));
    }

    function test_constructor_revertsZeroVault() public {
        vm.expectRevert("Invalid vault");
        new ReferralVaultProxy(admin, address(0));
    }

    function test_constructor_revertsZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new ReferralVaultProxy(address(0), address(vault));
    }

    function test_constructor_revertsVaultWithoutCode() public {
        vm.expectRevert("Invalid vault");
        new ReferralVaultProxy(admin, makeAddr("vaultWithoutCode"));
    }

    // ========================= router whitelist =========================

    function test_setRouterAllowed_updatesAuthorizationAndEmits() public {
        address newRouter = address(new MockReferralRouter());

        vm.expectEmit(true, false, false, true, address(proxy));
        emit ReferralVaultProxy.RouterAuthorizationUpdated(newRouter, true);

        vm.prank(admin);
        proxy.setRouterAllowed(newRouter, true);

        assertTrue(proxy.isRouterAllowed(newRouter));
        assertTrue(proxy.isRouterAllowed(router));
    }

    function test_setRouterAllowed_revertsWhenNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        proxy.setRouterAllowed(stranger, true);
    }

    function test_setRouterAllowed_revertsZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("Invalid router");
        proxy.setRouterAllowed(address(0), true);
    }

    function test_setRouterAllowed_revertsRouterWithoutCodeWhenAllowing() public {
        address routerWithoutCode = makeAddr("routerWithoutCode");

        vm.prank(admin);
        vm.expectRevert("Invalid router");
        proxy.setRouterAllowed(routerWithoutCode, true);
    }

    function test_setRouterAllowed_canClearAddressWithoutCode() public {
        address routerWithoutCode = makeAddr("routerWithoutCode");

        vm.prank(admin);
        proxy.setRouterAllowed(routerWithoutCode, false);

        assertFalse(proxy.isRouterAllowed(routerWithoutCode));
    }

    function test_setRouterAllowed_canRevokeRouterAfterCodeRemoved() public {
        assertTrue(proxy.isRouterAllowed(router));
        vm.etch(router, hex"");

        vm.prank(admin);
        proxy.setRouterAllowed(router, false);

        assertFalse(proxy.isRouterAllowed(router));
        vm.prank(router);
        vm.expectRevert("Not router");
        proxy.updateLastTokenBalance(address(token));
    }

    function test_updateLastTokenBalance_revertsWhenNotRouter() public {
        vm.prank(stranger);
        vm.expectRevert("Not router");
        proxy.updateLastTokenBalance(address(token));
    }

    function test_allocateReferral_revertsWhenNotRouter() public {
        vm.prank(stranger);
        vm.expectRevert("Not router");
        proxy.allocateReferral(address(token), rebateRecipient);
    }

    function test_disabledRouter_isRejected() public {
        vm.prank(admin);
        proxy.setRouterAllowed(router, false);

        vm.prank(router);
        vm.expectRevert("Not router");
        proxy.updateLastTokenBalance(address(token));
    }

    function test_renounceOwnership_isDisabled() public {
        vm.prank(admin);
        vm.expectRevert("Renounce disabled");
        proxy.renounceOwnership();

        assertEq(proxy.owner(), admin);
    }

    // ========================= forwarding =========================

    function test_maxReferralBips_readsFromVault() public view {
        assertEq(proxy.maxReferralBips(), 1000);
    }

    function test_payReferral_erc20_creditsVaultAndLeavesProxyEmpty() public {
        _payReferralERC20(router, 1000);

        // defaultBips = 8000 -> 800 to rebate recipient, 200 to protocol
        assertEq(vault.referralBalance(address(token), rebateRecipient), 800);
        assertEq(vault.getProtocolFunds(address(token)), 200);
        assertEq(token.balanceOf(address(vault)), 1000);
        assertEq(token.balanceOf(address(proxy)), 0);
    }

    function test_payReferral_eth_creditsVaultAndLeavesProxyEmpty() public {
        vm.deal(router, 1 ether);
        vm.startPrank(router);
        proxy.updateLastTokenBalance(address(0));
        (bool ok,) = address(proxy).call{value: 1 ether}("");
        assertTrue(ok);
        proxy.allocateReferral(address(0), rebateRecipient);
        vm.stopPrank();

        assertEq(vault.referralBalance(address(0), rebateRecipient), 0.8 ether);
        assertEq(address(vault).balance, 1 ether);
        assertEq(address(proxy).balance, 0);
    }

    function test_residualInProxy_isNotCreditedToRebateRecipient() public {
        token.mint(address(proxy), 500); // stray donation sitting in the proxy

        _payReferralERC20(router, 1000);

        // only this round's 1000 is split; the 500 donation becomes protocol funds
        assertEq(vault.referralBalance(address(token), rebateRecipient), 800);
        assertEq(vault.getProtocolFunds(address(token)), 700);
        assertEq(token.balanceOf(address(proxy)), 0);
    }

    function test_twoRouters_canBothPayReferral() public {
        address newRouter = address(new MockReferralRouter());
        vm.prank(admin);
        proxy.setRouterAllowed(newRouter, true);

        _payReferralERC20(router, 1000);
        _payReferralERC20(newRouter, 2000);

        assertEq(vault.referralBalance(address(token), rebateRecipient), 2400);
        assertEq(vault.getProtocolFunds(address(token)), 600);
    }
}
