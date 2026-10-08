# Local security review

## Scope

This review covers `src/SPAD.sol`, its vendored ERC20 implementation and transitive imports, and the delivered tests. The supplied security reference was used as a checklist. The token adds only a supply constant and a constructor mint to ERC20.

## Findings and design checks

- **Supply and authority:** `_mint` is called once in construction. Internal mint and burn helpers have no externally reachable entrypoint after construction. There is no owner role, proxy, initializer, or privileged balance control.
- **Transfer accounting:** The unmodified ERC20 moves exactly the requested amount. Self-transfers read the balance after subtraction before adding it back. Balance checks precede unchecked subtraction; the fixed total supply bounds balance additions. Supply and balance conservation are tested across randomized sequences.
- **Allowances:** Spending requires the caller's allowance. Reverting transfers roll back any allowance deduction. Infinite allowance semantics follow OpenZeppelin. Tests cover allowance exhaustion, unrelated spenders, invalid recipients, and insufficient balances.
- **External interactions:** Token operations make no external calls and invoke no recipient hooks. They expose no reentrancy path, oracle, signature authorization, randomness, swap, or delegated execution mechanism. No reentrancy guard or administrative pause is needed for these operations.
- **Input and output behavior:** Invalid addresses and insufficient funds/allowances revert; valid operations return `true`. Zero amounts follow ERC-20 semantics. Constructor minting, transfers, and explicit approvals emit their standard events.
- **Deployment:** The constructor uses `msg.sender`, including under CREATE2. The deployed runtime is checked for DELEGATECALL, CALLCODE, and SELFDESTRUCT, skipping PUSH data. The compiler is pinned and the bytecode metadata hash is disabled.

## Validation limits

Local verification uses `forge build`, `forge test` (unit, fuzz, and stateful invariant tests), and `forge fmt --check`. No Slither, Mythril, live-chain tests, or actual Uniswap pool integration were run. The launch-transfer fixture checks exact ERC-20 movement and does not represent a live market or prescribe economics.

These checks and this local review are not an independent security audit. An independent contributor must review the final code and deployment artifacts before release. The launch operator must run the supplied protected integration harness with the real launch configuration, verify source on the target chain, and confirm all distribution transactions. This project neither holds keys nor broadcasts transactions.
