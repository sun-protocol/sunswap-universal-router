// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";

import {UniversalRouter} from "src/UniversalRouter.sol";
import {RouterParameters} from "src/base/RouterImmutables.sol";
import {SafeVault} from "src/SafeVault.sol";
import {ReferralVault} from "src/ReferralVault.sol";
import {RouterConfigurator} from "src/RouterConfigurator.sol";
import {ReferralVaultProxy} from "src/ReferralVaultProxy.sol";
import {Commands} from "src/libraries/Commands.sol";
import {MockERC20} from "./mock/MockERC20.sol";

contract RouterConfiguratorTest is Test, DeployPermit2 {
    address admin = makeAddr("admin");
    address proxyAdmin = makeAddr("proxyAdmin");
    address stranger = makeAddr("stranger");
    address newAdmin = makeAddr("newAdmin");
    address vaultProxy;
    address operator = makeAddr("operator");
    address rebateRecipient = makeAddr("rebateRecipient");

    UniversalRouter router;
    ReferralVault vault;
    ReferralVaultProxy proxy;
    RouterConfigurator configurator;

    function setUp() public {
        router = _deployRouter();
        configurator = new RouterConfigurator(admin, operator);

        // Establish the original direct Router -> Vault binding before ownership handover.
        vault = new ReferralVault(operator, address(router));
        router.setReferralVault(address(vault));

        // Hand router ownership to the configurator (Ownable2Step)
        router.transferOwnership(address(configurator));
        vm.prank(admin);
        configurator.acceptRouterOwnership(address(router));

        // The configurator temporarily holds the vault operator role for linking.
        vm.startPrank(operator);
        vault.setMaxReferralBips(1000);
        vault.transferOperator(address(configurator));
        vm.stopPrank();

        // Proxy authorization is managed independently before the atomic binding
        proxy = new ReferralVaultProxy(proxyAdmin, address(vault));
        vm.prank(proxyAdmin);
        proxy.setRouterAllowed(address(router), true);
        vaultProxy = address(proxy);
    }

    /// @dev Bind the new router while the deployer owns it, then hand ownership to the configurator.
    function _deployManagedRouter() internal returns (UniversalRouter managed) {
        managed = _deployRouter();
        managed.setReferralVault(vaultProxy);
        managed.transferOwnership(address(configurator));
        vm.prank(admin);
        configurator.acceptRouterOwnership(address(managed));
        vm.prank(proxyAdmin);
        proxy.setRouterAllowed(address(managed), true);
    }

    function _payReferral(UniversalRouter r, MockERC20 token, uint256 bips) internal {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.PAY_REFERRAL)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(token), rebateRecipient, bips);
        r.execute(commands, inputs, block.timestamp);
    }

    function _deployRouter() internal returns (UniversalRouter) {
        RouterParameters memory params = RouterParameters({
            permit2: address(IAllowanceTransfer(deployPermit2())),
            weth9: address(new WETH()),
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
            safeVault: address(new SafeVault(admin))
        });
        return new UniversalRouter(params);
    }

    // ========================= setup =========================

    function test_constructor_setsOwnerAndOperator() public view {
        assertEq(configurator.owner(), admin);
        assertEq(configurator.operator(), operator);
    }

    function test_constructor_revertsZeroOperator() public {
        vm.expectRevert("Invalid operator");
        new RouterConfigurator(admin, address(0));
    }

    // ========================= operator management =========================

    function test_setOperator_ownerCanReplaceOperatorAndEmits() public {
        vm.expectEmit(true, true, false, false, address(configurator));
        emit RouterConfigurator.OperatorUpdated(operator, newAdmin);

        vm.prank(admin);
        configurator.setOperator(newAdmin);

        assertEq(configurator.operator(), newAdmin);
    }

    function test_setOperator_revokesCompromisedOperator() public {
        vm.prank(admin);
        configurator.setOperator(newAdmin);
        UniversalRouter pendingRouter = _deployRouter();
        pendingRouter.transferOwnership(address(configurator));
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, operator));
        configurator.acceptRouterOwnership(address(pendingRouter));
        vm.prank(newAdmin);
        configurator.acceptRouterOwnership(address(pendingRouter));
        assertEq(pendingRouter.owner(), address(configurator));
    }

    function test_setOperator_revertsWhenNotOwner() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, operator));
        configurator.setOperator(operator);
    }

    function test_setOperator_revertsZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("Invalid operator");
        configurator.setOperator(address(0));
    }

    function test_transferOperator_updatesOperatorAndEmits() public {
        vm.expectEmit(true, true, false, false, address(configurator));
        emit RouterConfigurator.OperatorUpdated(operator, newAdmin);

        vm.prank(operator);
        configurator.transferOperator(newAdmin);

        assertEq(configurator.operator(), newAdmin);
    }

    function test_transferOperator_revertsWhenCallerIsOwner() public {
        vm.prank(admin);
        vm.expectRevert("Not operator");
        configurator.transferOperator(newAdmin);
    }

    function test_transferOperator_revertsWhenNotOperator() public {
        vm.prank(stranger);
        vm.expectRevert("Not operator");
        configurator.transferOperator(stranger);
    }

    function test_transferOperator_revertsZeroAddress() public {
        vm.prank(operator);
        vm.expectRevert("Invalid operator");
        configurator.transferOperator(address(0));
    }

    function test_transferOperator_oldOperatorLosesAccess() public {
        vm.prank(operator);
        configurator.transferOperator(newAdmin);
        UniversalRouter pendingRouter = _deployRouter();
        pendingRouter.transferOwnership(address(configurator));
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, operator));
        configurator.acceptRouterOwnership(address(pendingRouter));
        vm.prank(newAdmin);
        configurator.acceptRouterOwnership(address(pendingRouter));
        assertEq(pendingRouter.owner(), address(configurator));
    }

    // ========================= link =========================

    function test_link_wiresRouterProxyAndVault() public {
        vm.prank(admin);
        configurator.link(address(router), vaultProxy, address(vault));

        assertTrue(proxy.isRouterAllowed(address(router)));
        assertEq(vault.router(), vaultProxy);
        assertEq(router.referralVault(), vaultProxy);
    }

    function test_link_emitsLinked() public {
        vm.expectEmit(true, true, true, false, address(configurator));
        emit RouterConfigurator.Linked(address(router), vaultProxy, address(vault));

        vm.prank(admin);
        configurator.link(address(router), vaultProxy, address(vault));
    }

    function test_link_revertsWhenNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        configurator.link(address(router), vaultProxy, address(vault));
    }

    function test_link_revertsWhenVaultProxyIsZero() public {
        vm.prank(admin);
        vm.expectRevert();
        configurator.link(address(router), address(0), address(vault));
    }

    function test_link_isAtomicWhenRouterNotOwnedByConfigurator() public {
        UniversalRouter foreignRouter = _deployRouter(); // owned by this test contract
        address routerBefore = vault.router();

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(configurator)));
        configurator.link(address(foreignRouter), vaultProxy, address(vault));

        // Vault binding must roll back; proxy authorization is unchanged.
        assertFalse(proxy.isRouterAllowed(address(foreignRouter)));
        assertEq(vault.router(), routerBefore);
    }

    function test_link_isAtomicWhenConfiguratorNotVaultOperator() public {
        ReferralVault foreignVault = new ReferralVault(stranger, makeAddr("oldRouter"));
        ReferralVaultProxy foreignVaultProxy = new ReferralVaultProxy(address(configurator), address(foreignVault));
        address vaultBefore = router.referralVault();

        vm.prank(admin);
        vm.expectRevert("Not operator");
        configurator.link(address(router), address(foreignVaultProxy), address(foreignVault));

        // Failed binding must leave the router unchanged.
        assertFalse(foreignVaultProxy.isRouterAllowed(address(router)));
        assertEq(router.referralVault(), vaultBefore);
    }

    function test_link_revertsWhenProxyForwardsToDifferentVault() public {
        ReferralVault otherVault = new ReferralVault(address(configurator), makeAddr("oldRouter"));
        address routerBefore = otherVault.router();

        vm.prank(admin);
        vm.expectRevert("Proxy vault mismatch");
        configurator.link(address(router), vaultProxy, address(otherVault));

        assertEq(otherVault.router(), routerBefore);
        assertTrue(proxy.isRouterAllowed(address(router)));
    }

    function test_link_keepsIndependentProxyOwnerAndAuthorization() public {
        vm.prank(admin);
        configurator.link(address(router), vaultProxy, address(vault));
        assertEq(proxy.owner(), proxyAdmin);
        assertTrue(proxy.isRouterAllowed(address(router)));
        assertEq(vault.router(), vaultProxy);
        assertEq(router.referralVault(), vaultProxy);
    }

    // ========================= router upgrade (end to end) =========================

    /// @dev Starts with a working direct Router -> Vault flow and an existing rebate ledger.
    function _accrueDirectReferral(MockERC20 token) internal {
        vm.startPrank(operator);
        configurator.transferVaultOperator(address(vault), operator);
        vm.stopPrank();

        vm.startPrank(operator);
        vault.setRouter(address(router));
        vault.setMaxReferralBips(1000);
        vm.stopPrank();

        token.mint(address(router), 10_000);
        _payReferral(router, token, 100);
        assertEq(vault.referralBalance(address(token), rebateRecipient), 80);
        assertEq(vault.getProtocolFunds(address(token)), 20);

        vm.prank(operator);
        vault.transferOperator(address(configurator));
    }

    function test_upgrade_directToProxyPreservesHistoricalReferralAndClaim() public {
        MockERC20 token = new MockERC20();
        _accrueDirectReferral(token);

        vm.prank(admin);
        configurator.link(address(router), vaultProxy, address(vault));

        assertEq(vault.referralBalance(address(token), rebateRecipient), 80);
        assertEq(vault.totalReferralBalance(address(token)), 80);
        assertEq(token.balanceOf(address(vault)), 100);
        assertEq(vault.getProtocolFunds(address(token)), 20);

        token.mint(address(router), 20_000 - token.balanceOf(address(router)));
        _payReferral(router, token, 100);
        assertEq(vault.referralBalance(address(token), rebateRecipient), 240);

        vm.prank(rebateRecipient);
        vault.claimReferral(address(token), rebateRecipient);

        assertEq(token.balanceOf(rebateRecipient), 240);
        assertEq(vault.referralBalance(address(token), rebateRecipient), 0);
        assertEq(vault.totalReferralBalance(address(token)), 0);
        assertEq(vault.getProtocolFunds(address(token)), 60);
        assertEq(token.balanceOf(address(vault)), 60);
        assertEq(token.balanceOf(address(proxy)), 0);
    }

    function test_upgrade_preboundNewRouterWorksAfterOldRouterLink() public {
        MockERC20 token = new MockERC20();
        _accrueDirectReferral(token);
        UniversalRouter newRouter = _deployManagedRouter();
        assertEq(newRouter.referralVault(), vaultProxy);
        assertTrue(proxy.isRouterAllowed(address(newRouter)));
        assertEq(router.referralVault(), address(vault));
        assertEq(vault.router(), address(router));

        // Preparation does not authorize the proxy at the vault yet.
        token.mint(address(newRouter), 20_000);
        vm.expectRevert("Not router");
        _payReferral(newRouter, token, 100);
        assertEq(token.balanceOf(address(newRouter)), 20_000);
        assertEq(token.balanceOf(address(proxy)), 0);
        assertEq(vault.referralBalance(address(token), rebateRecipient), 80);

        vm.prank(admin);
        configurator.link(address(router), vaultProxy, address(vault));

        // No further binding transaction is needed for the prepared router.
        _payReferral(newRouter, token, 100);
        token.mint(address(router), 10_000 - token.balanceOf(address(router)));
        _payReferral(router, token, 100);
        assertEq(vault.referralBalance(address(token), rebateRecipient), 320);
        assertEq(vault.totalReferralBalance(address(token)), 320);
        assertEq(vault.getProtocolFunds(address(token)), 80);
        assertEq(token.balanceOf(address(proxy)), 0);
    }

    function test_upgrade_addRouterPreservesHistoryAndOldRouterAccess() public {
        MockERC20 token = new MockERC20();
        _accrueDirectReferral(token);

        vm.prank(admin);
        configurator.link(address(router), vaultProxy, address(vault));
        token.mint(address(router), 20_000 - token.balanceOf(address(router)));
        _payReferral(router, token, 100);

        UniversalRouter newRouter = _deployManagedRouter();
        vm.prank(admin);
        configurator.link(address(newRouter), vaultProxy, address(vault));

        assertTrue(proxy.isRouterAllowed(address(router)));
        assertTrue(proxy.isRouterAllowed(address(newRouter)));
        assertEq(router.referralVault(), vaultProxy);
        assertEq(newRouter.referralVault(), vaultProxy);
        assertEq(vault.router(), vaultProxy);
        assertEq(vault.referralBalance(address(token), rebateRecipient), 240);

        token.mint(address(newRouter), 30_000);
        _payReferral(newRouter, token, 100);
        token.mint(address(router), 40_000 - token.balanceOf(address(router)));
        _payReferral(router, token, 100);

        assertEq(vault.referralBalance(address(token), rebateRecipient), 800);
        assertEq(vault.totalReferralBalance(address(token)), 800);
        assertEq(vault.getProtocolFunds(address(token)), 200);
        assertEq(token.balanceOf(address(vault)), 1000);
        assertEq(token.balanceOf(address(proxy)), 0);
    }

    function test_upgrade_oldAndNewRouterBothPayReferralThroughProxy() public {
        MockERC20 token = new MockERC20();

        UniversalRouter newRouter = _deployManagedRouter();
        vm.startPrank(admin);
        configurator.link(address(router), vaultProxy, address(vault));
        configurator.link(address(newRouter), vaultProxy, address(vault));
        vm.stopPrank();

        token.mint(address(router), 10_000);
        _payReferral(router, token, 100); // 1% -> 100 into vault
        token.mint(address(newRouter), 20_000);
        _payReferral(newRouter, token, 100); // 1% -> 200 into vault

        // defaultBips = 8000 -> 80% of 300 to rebate recipient
        assertEq(vault.referralBalance(address(token), rebateRecipient), 240);
        assertEq(vault.getProtocolFunds(address(token)), 60);
        assertEq(token.balanceOf(address(proxy)), 0);
    }

    function test_upgrade_disabledOldRouterCanNoLongerPayReferral() public {
        MockERC20 token = new MockERC20();

        UniversalRouter newRouter = _deployManagedRouter();
        vm.startPrank(admin);
        configurator.link(address(router), vaultProxy, address(vault));
        configurator.link(address(newRouter), vaultProxy, address(vault));
        vm.stopPrank();
        vm.prank(proxyAdmin);
        proxy.setRouterAllowed(address(router), false);

        token.mint(address(router), 10_000);
        vm.expectRevert("Not router"); // raised by the proxy, bubbles straight out of execute
        _payReferral(router, token, 100);

        token.mint(address(newRouter), 10_000);
        _payReferral(newRouter, token, 100);
        assertEq(vault.referralBalance(address(token), rebateRecipient), 80);
    }

    // ========================= operator permissions =========================

    function test_operator_cannotLink() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, operator));
        configurator.link(address(router), vaultProxy, address(vault));
    }

    function test_acceptRouterOwnership_operatorCanAcceptPendingHandover() public {
        UniversalRouter pendingRouter = _deployRouter();
        pendingRouter.transferOwnership(address(configurator));
        vm.prank(operator);
        configurator.acceptRouterOwnership(address(pendingRouter));
        assertEq(pendingRouter.owner(), address(configurator));
        assertEq(pendingRouter.pendingOwner(), address(0));
    }

    function test_acceptRouterOwnership_rejectsStranger() public {
        UniversalRouter pendingRouter = _deployRouter();
        pendingRouter.transferOwnership(address(configurator));
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        configurator.acceptRouterOwnership(address(pendingRouter));
        assertEq(pendingRouter.owner(), address(this));
        assertEq(pendingRouter.pendingOwner(), address(configurator));
    }

    function test_acceptRouterOwnership_requiresPendingHandoverToConfigurator() public {
        UniversalRouter pendingRouter = _deployRouter();
        pendingRouter.transferOwnership(newAdmin);
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(configurator)));
        configurator.acceptRouterOwnership(address(pendingRouter));
        assertEq(pendingRouter.owner(), address(this));
        assertEq(pendingRouter.pendingOwner(), newAdmin);
    }

    function test_link_doesNotAuthorizeRouter() public {
        vm.prank(proxyAdmin);
        proxy.setRouterAllowed(address(router), false);
        vm.prank(admin);
        configurator.link(address(router), vaultProxy, address(vault));

        assertFalse(proxy.isRouterAllowed(address(router)));
        assertEq(proxy.owner(), proxyAdmin);
        assertEq(vault.router(), vaultProxy);
        assertEq(router.referralVault(), vaultProxy);
        MockERC20 token = new MockERC20();
        token.mint(address(router), 10_000);
        vm.expectRevert("Not router");
        _payReferral(router, token, 100);
        assertEq(token.balanceOf(address(router)), 10_000);
        assertEq(token.balanceOf(address(vault)), 0);
    }

    function test_rollout_handBackPermissionsAndUpgradeWithoutConfigurator() public {
        MockERC20 token = new MockERC20();
        _accrueDirectReferral(token);
        UniversalRouter newRouter = _deployManagedRouter();

        vm.startPrank(admin);
        configurator.link(address(router), vaultProxy, address(vault));
        vm.stopPrank();
        vm.prank(operator);
        configurator.transferVaultOperator(address(vault), operator);
        vm.startPrank(admin);
        configurator.transferRouterOwnership(address(router), admin);
        configurator.transferRouterOwnership(address(newRouter), admin);
        router.acceptOwnership();
        newRouter.acceptOwnership();
        vm.stopPrank();

        assertEq(router.owner(), admin);
        assertEq(newRouter.owner(), admin);
        assertEq(vault.operator(), operator);
        assertEq(vault.owner(), address(this));
        assertEq(proxy.owner(), proxyAdmin);
        assertEq(vault.router(), vaultProxy);
        assertEq(vault.referralBalance(address(token), rebateRecipient), 80);

        // The original business operator manages the vault directly again.
        vm.startPrank(operator);
        vault.setDefaultBips(8000);
        vault.setMaxReferralBips(1000);
        vault.setRebateCheckEnabled(true);
        vault.setRebateEnabled(rebateRecipient, true);
        vm.stopPrank();

        // The configurator no longer has privileges on either managed contract.
        vm.prank(admin);
        vm.expectRevert("Not operator");
        configurator.link(address(router), vaultProxy, address(vault));
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(configurator)));
        configurator.transferRouterOwnership(address(router), stranger);
        vm.startPrank(admin);
        router.pause();
        router.unpause();
        vm.stopPrank();

        // A later router is deployed, authorized and configured without the configurator.
        UniversalRouter laterRouter = _deployRouter();
        laterRouter.transferOwnership(admin);
        vm.prank(admin);
        laterRouter.acceptOwnership();
        vm.prank(proxyAdmin);
        proxy.setRouterAllowed(address(laterRouter), true);
        vm.prank(admin);
        laterRouter.setReferralVault(vaultProxy);

        token.mint(address(router), 10_000 - token.balanceOf(address(router)));
        _payReferral(router, token, 100);
        token.mint(address(newRouter), 20_000);
        _payReferral(newRouter, token, 100);
        token.mint(address(laterRouter), 30_000);
        _payReferral(laterRouter, token, 100);
        assertEq(vault.referralBalance(address(token), rebateRecipient), 560);
        assertEq(vault.totalReferralBalance(address(token)), 560);
        assertEq(vault.getProtocolFunds(address(token)), 140);
        assertEq(token.balanceOf(address(proxy)), 0);

        vm.prank(rebateRecipient);
        vault.claimReferral(address(token), rebateRecipient);
        assertEq(token.balanceOf(rebateRecipient), 560);
        assertEq(vault.totalReferralBalance(address(token)), 0);
        assertEq(token.balanceOf(address(vault)), 140);
    }

    // ========================= vault business configuration =========================

    function _vaultConfigurationCalls(address targetVault) internal view returns (bytes[] memory calls) {
        calls = new bytes[](6);
        calls[0] = abi.encodeCall(RouterConfigurator.setVaultDefaultBips, (targetVault, 6000));
        calls[1] = abi.encodeCall(RouterConfigurator.setVaultCustomRebateBips, (targetVault, rebateRecipient, 8000));
        calls[2] = abi.encodeCall(RouterConfigurator.setVaultMaxReferralBips, (targetVault, 500));
        calls[3] = abi.encodeCall(RouterConfigurator.setVaultRebateCheckEnabled, (targetVault, true));
        calls[4] = abi.encodeCall(RouterConfigurator.setVaultRebateEnabled, (targetVault, rebateRecipient, true));
        calls[5] = abi.encodeCall(RouterConfigurator.setVaultRouter, (targetVault, vaultProxy));
    }

    function _assertVaultConfigurationRejected(address caller, address targetVault) internal {
        bytes[] memory calls = _vaultConfigurationCalls(targetVault);
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(caller);
            (bool success, bytes memory result) = address(configurator).call(calls[i]);
            assertFalse(success);
            assertEq(result, abi.encodeWithSignature("Error(string)", "Not operator"));
        }
    }

    function test_vaultConfiguration_worksWhileWaitingForOwnerLink() public {
        MockERC20 token = new MockERC20();
        vm.startPrank(operator);
        configurator.setVaultDefaultBips(address(vault), 6000);
        configurator.setVaultCustomRebateBips(address(vault), stranger, 0);
        configurator.setVaultMaxReferralBips(address(vault), 100);
        configurator.setVaultRebateCheckEnabled(address(vault), true);
        configurator.setVaultRebateEnabled(address(vault), rebateRecipient, true);
        vm.stopPrank();

        assertEq(vault.defaultBips(), 6000);
        assertTrue(vault.hasCustomRebateBips(stranger));
        assertEq(vault.customRebateBips(stranger), 0);
        assertEq(vault.maxReferralBips(), 100);
        assertTrue(vault.isRebateCheckEnabled());
        assertTrue(vault.isRebateEnabled(rebateRecipient));
        // Business maintenance does not switch the live direct Router -> Vault binding.
        assertEq(router.referralVault(), address(vault));
        assertEq(vault.router(), address(router));
        assertEq(vault.operator(), address(configurator));
        token.mint(address(router), 10_000);
        _payReferral(router, token, 100);
        assertEq(vault.referralBalance(address(token), rebateRecipient), 60);

        vm.prank(operator);
        configurator.setVaultRebateEnabled(address(vault), rebateRecipient, false);
        vm.expectRevert("Rebate recipient not enabled");
        _payReferral(router, token, 100);
        assertEq(token.balanceOf(address(router)), 9900);
        assertEq(vault.referralBalance(address(token), rebateRecipient), 60);

        vm.startPrank(operator);
        configurator.setVaultRebateCheckEnabled(address(vault), false);
        configurator.setVaultMaxReferralBips(address(vault), 50);
        vm.stopPrank();
        vm.expectRevert("Bips exceeds maxReferralBips");
        _payReferral(router, token, 100);

        // Owner can link later; the operator still maintains business parameters afterwards.
        vm.prank(admin);
        configurator.link(address(router), vaultProxy, address(vault));
        vm.startPrank(operator);
        configurator.setVaultMaxReferralBips(address(vault), 100);
        configurator.setVaultCustomRebateBips(address(vault), rebateRecipient, 8000);
        vm.stopPrank();
        _payReferral(router, token, 100);
        assertEq(vault.referralBalance(address(token), rebateRecipient), 139);
        assertEq(vault.getProtocolFunds(address(token)), 60);
    }

    function test_setVaultRouter_updatesOnlyVaultAndAllowsLaterAtomicLink() public {
        vm.prank(operator);
        configurator.setVaultRouter(address(vault), newAdmin);
        assertEq(vault.router(), newAdmin);
        assertEq(vault.operator(), address(configurator));
        assertEq(router.referralVault(), address(vault));
        assertTrue(proxy.isRouterAllowed(address(router)));

        vm.prank(admin);
        configurator.link(address(router), vaultProxy, address(vault));
        assertEq(vault.router(), vaultProxy);
        assertEq(router.referralVault(), vaultProxy);
    }

    function testFuzz_vaultConfiguration_rejectsNonOperator(address caller) public {
        vm.assume(caller != operator);
        _assertVaultConfigurationRejected(caller, address(vault));
        assertEq(vault.defaultBips(), 8000);
        assertFalse(vault.hasCustomRebateBips(rebateRecipient));
        assertEq(vault.maxReferralBips(), 1000);
        assertFalse(vault.isRebateCheckEnabled());
        assertFalse(vault.isRebateEnabled(rebateRecipient));
    }

    function test_vaultConfiguration_rejectsOwner() public {
        _assertVaultConfigurationRejected(admin, address(vault));
    }

    function test_vaultConfiguration_ownerCanReplaceOperator() public {
        vm.prank(admin);
        configurator.setOperator(newAdmin);
        _assertVaultConfigurationRejected(operator, address(vault));
        bytes[] memory calls = _vaultConfigurationCalls(address(vault));
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(newAdmin);
            (bool success,) = address(configurator).call(calls[i]);
            assertTrue(success);
        }
        assertEq(vault.defaultBips(), 6000);
        assertEq(vault.customRebateBips(rebateRecipient), 8000);
        assertEq(vault.maxReferralBips(), 500);
        assertTrue(vault.isRebateCheckEnabled());
        assertTrue(vault.isRebateEnabled(rebateRecipient));
        assertEq(vault.router(), vaultProxy);
        assertEq(vault.operator(), address(configurator));
    }

    function test_vaultConfiguration_rejectsAfterOperatorHandback() public {
        vm.prank(operator);
        configurator.transferVaultOperator(address(vault), operator);
        _assertVaultConfigurationRejected(operator, address(vault));
        vm.prank(operator);
        vault.setDefaultBips(7000);
        assertEq(vault.defaultBips(), 7000);
        assertEq(vault.operator(), operator);
    }

    function test_vaultConfiguration_doesNotControlUnrelatedVault() public {
        ReferralVault foreignVault = new ReferralVault(stranger, address(router));
        _assertVaultConfigurationRejected(operator, address(foreignVault));
        assertEq(foreignVault.operator(), stranger);
        assertEq(foreignVault.defaultBips(), 8000);
        assertFalse(foreignVault.hasCustomRebateBips(rebateRecipient));
        assertEq(foreignVault.maxReferralBips(), 0);
        assertFalse(foreignVault.isRebateCheckEnabled());
        assertFalse(foreignVault.isRebateEnabled(rebateRecipient));
    }

    function test_vaultConfiguration_propagatesVaultValidationErrors() public {
        vm.startPrank(operator);
        vm.expectRevert("Invalid router");
        configurator.setVaultRouter(address(vault), address(0));
        vm.expectRevert("Invalid defaultBips");
        configurator.setVaultDefaultBips(address(vault), 10001);
        vm.expectRevert("Invalid rebateRecipient");
        configurator.setVaultCustomRebateBips(address(vault), address(0), 1000);
        vm.expectRevert("Invalid bips");
        configurator.setVaultCustomRebateBips(address(vault), rebateRecipient, 10001);
        vm.expectRevert("Invalid maxReferralBips");
        configurator.setVaultMaxReferralBips(address(vault), 10001);
        vm.expectRevert("Invalid rebateRecipient");
        configurator.setVaultRebateEnabled(address(vault), address(0), true);
        vm.stopPrank();
    }

    // ========================= managed router lifecycle =========================

    function _routerConfigurationCalls(address targetRouter) internal view returns (bytes[] memory calls) {
        calls = new bytes[](4);
        calls[0] = abi.encodeCall(RouterConfigurator.setRouterSafeVault, (targetRouter, newAdmin));
        calls[1] = abi.encodeCall(RouterConfigurator.setRouterEnableRecipientCheck, (targetRouter, true));
        calls[2] = abi.encodeCall(RouterConfigurator.setRouterStableSwap, (targetRouter, stranger));
        calls[3] = abi.encodeCall(RouterConfigurator.setRouterReferralVault, (targetRouter, vaultProxy));
    }

    function _assertRouterConfigurationRejected(address caller, address targetRouter, address rejectedAccount) internal {
        bytes[] memory calls = _routerConfigurationCalls(targetRouter);
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(caller);
            (bool success, bytes memory result) = address(configurator).call(calls[i]);
            assertFalse(success);
            assertEq(result, abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, rejectedAccount));
        }
    }

    function test_routerConfiguration_worksAfterVaultOperatorHandbackAndWhilePaused() public {
        vm.prank(admin);
        configurator.link(address(router), vaultProxy, address(vault));
        vm.prank(operator);
        configurator.transferVaultOperator(address(vault), operator);

        vm.startPrank(admin);
        configurator.pauseRouter(address(router));
        configurator.setRouterSafeVault(address(router), newAdmin);
        configurator.setRouterEnableRecipientCheck(address(router), true);
        configurator.setRouterStableSwap(address(router), stranger);
        configurator.setRouterReferralVault(address(router), address(vault));
        configurator.unpauseRouter(address(router));
        vm.stopPrank();

        assertEq(router.safeVault(), newAdmin);
        assertTrue(router.enableRecipientCheck());
        assertEq(router.stableSwapFactory(), stranger);
        // These registries belong to different modules and have no setters on UniversalRouter.
        assertEq(router.psmSwapFactory(), address(0));
        assertEq(router.stableFactory(), address(0));
        assertEq(router.referralVault(), address(vault));
        assertEq(router.owner(), address(configurator));
        assertEq(vault.operator(), operator);
        assertEq(vault.router(), vaultProxy);
        assertEq(proxy.owner(), proxyAdmin);
        // Restore the valid referral route; the router-only setter never updates Vault.router.
        vm.prank(admin);
        configurator.setRouterReferralVault(address(router), vaultProxy);

        MockERC20 token = new MockERC20();
        token.mint(address(router), 10_000);
        _payReferral(router, token, 100);
        assertEq(token.balanceOf(address(router)), 9900);
        assertEq(vault.referralBalance(address(token), rebateRecipient), 80);
    }

    function test_routerConfiguration_recipientRestrictionAppliesAndCanBeDisabled() public {
        MockERC20 token = new MockERC20();
        token.mint(address(router), 100);
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(token), stranger, 100);
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.SWEEP)));

        vm.prank(admin);
        configurator.setRouterEnableRecipientCheck(address(router), true);
        vm.expectRevert(bytes4(keccak256("RecipientErr()")));
        router.execute(commands, inputs, block.timestamp);
        assertEq(token.balanceOf(stranger), 0);

        vm.prank(admin);
        configurator.setRouterEnableRecipientCheck(address(router), false);
        router.execute(commands, inputs, block.timestamp);
        assertEq(token.balanceOf(stranger), 100);
    }

    function testFuzz_routerConfiguration_rejectsNonOwner(address caller) public {
        vm.assume(caller != admin);
        _assertRouterConfigurationRejected(caller, address(router), caller);
    }

    function test_routerConfiguration_rejectsOperator() public {
        _assertRouterConfigurationRejected(operator, address(router), operator);
    }

    function test_routerConfiguration_rejectsUnmanagedRouter() public {
        UniversalRouter foreignRouter = _deployRouter();
        _assertRouterConfigurationRejected(admin, address(foreignRouter), address(configurator));
        assertEq(foreignRouter.owner(), address(this));
    }

    function test_routerConfiguration_propagatesTargetValidationErrors() public {
        vm.startPrank(admin);
        vm.expectRevert(UniversalRouter.InvalidSafeVault.selector);
        configurator.setRouterSafeVault(address(router), address(0));
        vm.expectRevert(UniversalRouter.InvalidReferralVault.selector);
        configurator.setRouterReferralVault(address(router), address(0));
        vm.expectRevert("Invalid factory address");
        configurator.setRouterStableSwap(address(router), address(0));
        vm.stopPrank();
    }

    function test_routerConfiguration_followsConfiguratorOwnershipHandover() public {
        vm.prank(admin);
        configurator.transferOwnership(newAdmin);
        vm.prank(newAdmin);
        configurator.acceptOwnership();
        _assertRouterConfigurationRejected(admin, address(router), admin);
        bytes[] memory calls = _routerConfigurationCalls(address(router));
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(newAdmin);
            (bool success,) = address(configurator).call(calls[i]);
            assertTrue(success);
        }
        assertEq(router.owner(), address(configurator));
    }

    function test_routerConfiguration_rejectsAfterRouterOwnershipHandover() public {
        vm.prank(admin);
        configurator.transferRouterOwnership(address(router), newAdmin);
        vm.prank(newAdmin);
        router.acceptOwnership();
        _assertRouterConfigurationRejected(admin, address(router), address(configurator));
    }

    function test_transferRouterOwnership_canCancelPendingHandover() public {
        vm.startPrank(admin);
        configurator.transferRouterOwnership(address(router), newAdmin);
        configurator.transferRouterOwnership(address(router), address(0));
        configurator.setRouterEnableRecipientCheck(address(router), true);
        vm.stopPrank();
        assertEq(router.pendingOwner(), address(0));
        assertEq(router.owner(), address(configurator));
        assertTrue(router.enableRecipientCheck());
        vm.prank(newAdmin);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, newAdmin));
        router.acceptOwnership();
    }

    function test_rollout_keepsRouterOwnershipAndRetiresOldRouter() public {
        MockERC20 token = new MockERC20();
        _accrueDirectReferral(token);
        vm.prank(admin);
        configurator.link(address(router), vaultProxy, address(vault));
        vm.prank(operator);
        configurator.transferVaultOperator(address(vault), operator);

        // Later routers are configured before handover, without linking the vault again.
        UniversalRouter newRouter = _deployManagedRouter();
        vm.prank(admin);
        configurator.pauseRouter(address(router));
        vm.prank(proxyAdmin);
        proxy.setRouterAllowed(address(router), false);

        assertEq(router.owner(), address(configurator));
        assertEq(newRouter.owner(), address(configurator));
        assertEq(vault.operator(), operator);
        assertEq(vault.router(), vaultProxy);
        assertTrue(router.paused());
        assertFalse(newRouter.paused());

        // Even commands without a referral can no longer execute on the old router.
        bytes[] memory emptyInputs = new bytes[](0);
        vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
        router.execute(hex"", emptyInputs, block.timestamp);

        token.mint(address(newRouter), 20_000);
        _payReferral(newRouter, token, 100);
        assertEq(vault.referralBalance(address(token), rebateRecipient), 240);
        vm.prank(rebateRecipient);
        vault.claimReferral(address(token), rebateRecipient);
        assertEq(token.balanceOf(rebateRecipient), 240);
        assertEq(vault.getProtocolFunds(address(token)), 60);

        // Restoring authorization and unpausing also keeps ownership in the configurator.
        vm.prank(proxyAdmin);
        proxy.setRouterAllowed(address(router), true);
        vm.prank(admin);
        configurator.unpauseRouter(address(router));
        _payReferral(router, token, 100);
        assertEq(vault.referralBalance(address(token), rebateRecipient), 79);
        assertEq(router.owner(), address(configurator));
    }

    function testFuzz_pauseRouter_rejectsNonOwner(address caller) public {
        vm.assume(caller != admin);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        configurator.pauseRouter(address(router));
        assertFalse(router.paused());
    }

    function testFuzz_unpauseRouter_rejectsNonOwner(address caller) public {
        vm.assume(caller != admin);
        vm.prank(admin);
        configurator.pauseRouter(address(router));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        configurator.unpauseRouter(address(router));
        assertTrue(router.paused());
    }

    function test_operator_cannotPauseOrUnpauseRouter() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, operator));
        configurator.pauseRouter(address(router));
        vm.prank(admin);
        configurator.pauseRouter(address(router));
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, operator));
        configurator.unpauseRouter(address(router));
    }

    function test_pauseAndUnpauseRouter_rejectsRouterNotOwnedByConfigurator() public {
        UniversalRouter foreignRouter = _deployRouter();
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(configurator)));
        configurator.pauseRouter(address(foreignRouter));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(configurator)));
        configurator.unpauseRouter(address(foreignRouter));
        vm.stopPrank();
    }

    // ========================= renounce disabled =========================

    function test_renounceOwnership_isDisabledOnConfigurator() public {
        vm.prank(admin);
        vm.expectRevert("Renounce disabled");
        configurator.renounceOwnership();

        assertEq(configurator.owner(), admin);
    }

    // ========================= hand back =========================

    function test_configuratorOwnershipHandover_changesAdminWithoutChangingManagedRoles() public {
        vm.prank(admin);
        configurator.transferOwnership(newAdmin);
        assertEq(configurator.owner(), admin);
        assertEq(configurator.pendingOwner(), newAdmin);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        configurator.acceptOwnership();

        vm.prank(newAdmin);
        configurator.acceptOwnership();
        assertEq(configurator.owner(), newAdmin);
        assertEq(configurator.pendingOwner(), address(0));
        assertEq(configurator.operator(), operator);
        assertEq(router.owner(), address(configurator));
        assertEq(proxy.owner(), proxyAdmin);
        assertEq(vault.operator(), address(configurator));

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, admin));
        configurator.link(address(router), vaultProxy, address(vault));
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, admin));
        configurator.setOperator(stranger);

        vm.prank(newAdmin);
        configurator.link(address(router), vaultProxy, address(vault));
        assertTrue(proxy.isRouterAllowed(address(router)));
    }

    function test_transferRouterOwnership_requiresNewOwnerToAccept() public {
        vm.prank(admin);
        configurator.transferRouterOwnership(address(router), newAdmin);

        assertEq(router.owner(), address(configurator));
        assertEq(router.pendingOwner(), newAdmin);

        vm.prank(newAdmin);
        router.acceptOwnership();
        assertEq(router.owner(), newAdmin);
    }

    function test_transferRouterOwnership_revertsWhenNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        configurator.transferRouterOwnership(address(router), newAdmin);
    }

    function test_transferVaultOperator_movesOperator() public {
        vm.prank(operator);
        configurator.transferVaultOperator(address(vault), newAdmin);

        assertEq(vault.operator(), newAdmin);
    }

    function test_transferVaultOperator_revertsWhenNotOperator() public {
        vm.prank(stranger);
        vm.expectRevert("Not operator");
        configurator.transferVaultOperator(address(vault), newAdmin);
    }

    function test_transferVaultOperator_rejectsOwner() public {
        vm.prank(admin);
        vm.expectRevert("Not operator");
        configurator.transferVaultOperator(address(vault), newAdmin);
    }
}
