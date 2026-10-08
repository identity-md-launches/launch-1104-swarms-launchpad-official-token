// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SPAD} from "src/SPAD.sol";

/// @dev Complements the deployment suite with allowance transitions and atomic failure properties.
/// forge-config: default.fuzz.runs = 1000
contract SPADEdgeCasesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    SPAD private token;
    address private holder;
    address private recipient;
    address private spender;

    function setUp() public {
        token = new SPAD();
        holder = makeAddr("edge holder");
        recipient = makeAddr("edge recipient");
        spender = makeAddr("edge spender");
    }

    function test_OneWeiCanMakeARoundTrip() public {
        assertTrue(token.transfer(holder, 1));
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(holder);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaxUintCannotBeTransferredEvenWithInfiniteApproval() public {
        uint256 amount = type(uint256).max;
        bytes memory insufficientBalance =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount);
        vm.expectRevert(insufficientBalance);
        token.transfer(recipient, amount);

        assertTrue(token.approve(spender, amount));
        vm.expectRevert(insufficientBalance);
        vm.prank(spender);
        token.transferFrom(address(this), recipient, amount);

        assertEq(token.allowance(address(this), spender), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaxMinusOneAllowanceIsFinite() public {
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_InfiniteApprovalCanBeRevokedAfterSpending() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 0));
        assertTrue(token.transferFrom(address(this), recipient, 1));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_LoweringInfiniteApprovalImmediatelyLimitsSpender() public {
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 1, 2));
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 2);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 1));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_ReplenishingBalanceDoesNotRestoreSpentAllowance() public {
        assertTrue(token.transfer(holder, 10));
        vm.prank(holder);
        assertTrue(token.approve(spender, 10));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 10));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.allowance(holder, spender), 0);

        assertTrue(token.transfer(holder, 10));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.balanceOf(holder), 10);
        assertEq(token.balanceOf(recipient), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY - 20);
        assertEq(token.allowance(holder, spender), 0);
    }

    function test_SpenderAsRecipientStillDebitsTheOwner() public {
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), spender, 1));
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(spender), 1);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ZeroApprovalForZeroSpenderReverts() public {
        assertTrue(token.approve(spender, 7));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.allowance(address(this), spender), 7);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_RoundTripRestoresBothFundedHolders(uint256 startingBalance, uint256 amount) public {
        startingBalance = bound(startingBalance, 0, SUPPLY);
        amount = bound(amount, 0, startingBalance);
        assertTrue(token.transfer(holder, startingBalance));
        assertTrue(token.transfer(recipient, SUPPLY - startingBalance));

        vm.prank(holder);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(holder), startingBalance - amount);
        assertEq(token.balanceOf(recipient), SUPPLY - startingBalance + amount);
        vm.prank(recipient);
        assertTrue(token.transfer(holder, amount));

        assertEq(token.balanceOf(holder), startingBalance);
        assertEq(token.balanceOf(recipient), SUPPLY - startingBalance);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferFromOverAllowanceIsAtomic(uint256 balance, uint256 approved, uint256 amount) public {
        balance = bound(balance, 1, SUPPLY);
        approved = bound(approved, 0, balance - 1);
        amount = bound(amount, approved + 1, balance);
        assertTrue(token.transfer(holder, balance));
        vm.prank(holder);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, amount);

        _assertFailedSpendState(balance, approved);
    }

    function testFuzz_TransferFromOverBalanceIsAtomic(uint256 balance, uint256 amount, bool infinite) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, balance + 1, type(uint256).max - 1);
        uint256 approved = infinite ? type(uint256).max : amount;
        assertTrue(token.transfer(holder, balance));
        vm.prank(holder);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, amount));
        vm.prank(spender);
        token.transferFrom(holder, recipient, amount);

        _assertFailedSpendState(balance, approved);
    }

    function testFuzz_ZeroRecipientFailureLeavesApprovalUsable(uint256 balance, uint256 amount, bool infinite) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, 0, balance);
        uint256 approved = infinite ? type(uint256).max : amount;
        assertTrue(token.transfer(holder, balance));
        vm.prank(holder);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), amount);
        _assertFailedSpendState(balance, approved);

        // A failed destination must not consume the authorization for a later valid transfer.
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, amount));
        assertEq(token.balanceOf(holder), balance - amount);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.allowance(holder, spender), infinite ? approved : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalReplacementIsExactAndIsolated(uint256 previous, uint256 replacement) public {
        assertTrue(token.approve(recipient, 17));
        vm.prank(holder);
        assertTrue(token.approve(spender, 23));

        assertTrue(token.approve(spender, previous));
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertEq(token.allowance(address(this), recipient), 17);
        assertEq(token.allowance(holder, spender), 23);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ZeroDelegatedTransferPreservesArbitraryApproval(uint256 approved, bool selfTransfer) public {
        assertTrue(token.transfer(holder, 1));
        vm.prank(holder);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, selfTransfer ? holder : recipient, 0));
        assertEq(token.allowance(holder, spender), approved);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _assertFailedSpendState(uint256 balance, uint256 approved) private view {
        assertEq(token.allowance(holder, spender), approved, "failed spend consumed approval");
        assertEq(token.balanceOf(holder), balance, "failed spend debited owner");
        assertEq(token.balanceOf(recipient), 0, "failed spend credited recipient");
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
