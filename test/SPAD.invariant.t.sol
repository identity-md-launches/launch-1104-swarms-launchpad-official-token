// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {SPAD} from "../src/SPAD.sol";

/// @dev Exercises sequences of real transfers and allowances over a closed set of holders.
contract SPADHandler is Test {
    SPAD public immutable token;
    address[4] public actors;

    constructor() {
        token = new SPAD();
        actors = [address(this), makeAddr("holder one"), makeAddr("holder two"), makeAddr("holder three")];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowance = token.allowance(from, spender);
        uint256 balance = token.balanceOf(from);
        amount = bound(amount, 0, allowance < balance ? allowance : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        assertEq(token.allowance(from, spender), allowance == type(uint256).max ? allowance : allowance - amount);
    }
}

contract SPADInvariantTest is StdInvariant, Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    SPADHandler private handler;
    SPAD private token;

    function setUp() public {
        handler = new SPADHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = SPADHandler.transfer.selector;
        selectors[1] = SPADHandler.approve.selector;
        selectors[2] = SPADHandler.transferFrom.selector;
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
}
