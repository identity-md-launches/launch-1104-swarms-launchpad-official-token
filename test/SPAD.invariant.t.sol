// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SPAD} from "../src/SPAD.sol";

/// @dev Exercises sequences of real transfers and allowances over a closed set of holders.
contract SPADHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    SPAD public immutable token;
    address[4] public actors;
    // Expected state comes from authorized actions, never from the token's reported balances.
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        token = new SPAD();
        actors = [address(this), makeAddr("holder one"), makeAddr("holder two"), makeAddr("holder three")];
        expectedBalance[address(this)] = SUPPLY;
        // Every actor starts funded so positive transfers are reachable immediately.
        for (uint256 i = 1; i < actors.length; ++i) {
            assertTrue(token.transfer(actors[i], SUPPLY / 4));
            _recordTransfer(address(this), actors[i], SUPPLY / 4);
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordTransfer(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, amount);
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowance = expectedAllowance[from][spender];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, 0, allowance < balance ? allowance : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        _recordTransfer(from, to, amount);
        if (allowance != type(uint256).max) expectedAllowance[from][spender] -= amount;
        assertEq(token.allowance(from, spender), allowance == type(uint256).max ? allowance : allowance - amount);
    }

    /// @dev Deliberately revisit revocation, one wei, and the finite/infinite allowance boundary.
    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 mode) external {
        uint256[4] memory amounts = [uint256(0), uint256(1), type(uint256).max - 1, type(uint256).max];
        _approve(actors[ownerSeed % actors.length], actors[spenderSeed % actors.length], amounts[mode % 4]);
    }

    function rejectTransfer(uint256 fromSeed, uint256 toSeed, uint256 amount, bool zeroRecipient) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        if (zeroRecipient) {
            to = address(0);
            amount = bound(amount, 0, expectedBalance[from]);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, to));
        } else {
            uint256 balance = expectedBalance[from];
            amount = bound(amount, balance + 1, type(uint256).max);
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
            );
        }
        vm.prank(from);
        token.transfer(to, amount);
        // No ghost update: the invariants also check that every rejected call is atomic.
    }

    function rejectTransferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount, uint256 mode)
        external
    {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        if (mode % 3 == 0) {
            // The requested amount fits the balance but exceeds a newly set finite allowance.
            // Select a funded actor; conservation guarantees at least one exists.
            for (uint256 i; expectedBalance[from] == 0 && i < actors.length; ++i) {
                from = actors[i];
            }
            amount = bound(amount, 1, expectedBalance[from]);
            _approve(from, spender, amount - 1);
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, amount - 1, amount)
            );
        } else if (mode % 3 == 1) {
            uint256 balance = expectedBalance[from];
            amount = bound(amount, balance + 1, type(uint256).max);
            _approve(from, spender, amount);
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
            );
        } else {
            uint256 allowance = expectedAllowance[from][spender];
            uint256 balance = expectedBalance[from];
            amount = bound(amount, 0, allowance < balance ? allowance : balance);
            to = address(0);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, to));
        }
        vm.prank(spender);
        token.transferFrom(from, to, amount);
    }

    function rejectApproval(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount);
    }

    function _recordTransfer(address from, address to, uint256 amount) private {
        if (from != to) {
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        }
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract SPADInvariantTest is StdInvariant, Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    SPADHandler private handler;
    SPAD private token;

    function setUp() public {
        handler = new SPADHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = SPADHandler.transfer.selector;
        selectors[1] = SPADHandler.approve.selector;
        selectors[2] = SPADHandler.transferFrom.selector;
        selectors[3] = SPADHandler.approveBoundary.selector;
        selectors[4] = SPADHandler.rejectTransfer.selector;
        selectors[5] = SPADHandler.rejectTransferFrom.selector;
        selectors[6] = SPADHandler.rejectApproval.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyAndAllBalancesAreConserved() public view {
        uint256 balances;
        for (uint256 i; i < 4; ++i) {
            balances += token.balanceOf(handler.actors(i));
        }
        assertEq(balances, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.decimals(), 18);
    }

    /// @dev Conservation alone would miss theft between holders or corruption of unrelated approvals.
    function invariant_BalancesAndAllowancesMatchAuthorizedActions() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.balanceOf(owner), handler.expectedBalance(owner), "holder balance drifted");
            assertEq(token.allowance(owner, address(0)), 0, "zero spender received approval");
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.expectedAllowance(owner, spender),
                    "authorization changed unexpectedly"
                );
            }
        }
    }
}
