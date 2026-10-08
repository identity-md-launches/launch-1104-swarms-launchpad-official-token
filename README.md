# Swarms Launchpad Official token (SPAD)

SPAD is a fixed-supply ERC-20. Its constructor mints all tokens once to the immediate deployer (`msg.sender`).

| Parameter | Value |
| --- | --- |
| Contract | `src/SPAD.sol:SPAD` |
| Name | `Swarms Launchpad Official token` |
| Symbol | `SPAD` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Deployment transaction value | `0` |
| Solidity | `0.8.26` |
| EVM target | `cancun` |

## Behavior and assumptions

The brief specifies ordinary ERC-20 behavior. Transfers deliver the exact requested amount; there are no taxes, fees, rebases, vesting, transfer limits, or exemptions. Zero-value transfers between nonzero addresses succeed and emit `Transfer`. Transfers to the zero address revert. Self-transfers preserve balances but still require sufficient funds.

There is no owner, administrator, public mint or burn, pause, blacklist, seizure, upgrade mechanism, or initializer. Supply stays constant after construction. The deployer has the same transfer and approval rights as any other holder. Constructor minting emits `Transfer(address(0), deployer, totalSupply)`.

`approve` replaces an allowance and emits `Approval`. `transferFrom` requires an allowance even when called by the holder; finite allowances decrease by the amount spent. An allowance of `type(uint256).max` remains unchanged when spent. Following the vendored OpenZeppelin implementation, spending an allowance does not emit another `Approval` event. Insufficient balances, insufficient allowances, and invalid addresses revert with ERC-6093 custom errors. Failed transactions leave balances and allowances unchanged.

The implementation extends the vendored OpenZeppelin Contracts v5.0.2 ERC20 without overriding its transfer or allowance logic. Dependency versions, sources, archive hashes, and licenses are recorded in [DEPENDENCIES.md](DEPENDENCIES.md).

## Build and check

Use Foundry with the pinned Solidity 0.8.26 compiler installed. All Solidity dependencies are included under `lib/`; no dependency downloads, package manager, git submodules, environment variables, RPC, or wallet are needed to run the checks. The verifier provides the compiler separately.

```sh
forge build
forge test
forge fmt --check
```

The configuration enables the optimizer with 200 runs and sets `bytecode_hash = "none"` for reproducible deployment comparison. FFI and filesystem cheatcode permissions are not enabled. Tests do not read or modify environment variables and do not depend on test order.

The suite covers constructor supply and metadata, CREATE and CREATE2 factory deployment, exact launch-style transfers, events, zero and self-transfers, finite and infinite allowances, invalid addresses, failure rollback, unauthorized spending, absent privileged entrypoints, and forbidden runtime opcodes. Four fuzz tests run 512 cases each. A stateful invariant runs 128 sequences of 64 operations over four holders, checking supply and balance conservation during transfers, approvals, and delegated transfers.

The launch-flow test uses local recipient fixtures and an illustrative pool allocation. It checks token movement only; it does not deploy a Uniswap pool or select launch economics. The supplied protected integration harness depends on the network's factory/pool sources, manifest, and launch environment; that separate integration check remains the launch operator's responsibility.

## Deployment parameters and handoff

Deploy the compiled `SPAD` creation bytecode directly with no appended constructor arguments, no initializer call, and no native currency. The target chain must support the configured Cancun EVM target. Review the compiler settings before producing the final deployment artifact.

```sh
forge inspect src/SPAD.sol:SPAD bytecode
forge inspect src/SPAD.sol:SPAD abi
```

The build artifact is `out/SPAD.sol/SPAD.json`. A Solidity factory creates the token with `new SPAD()` (or `new SPAD{salt: salt}()` for CREATE2). If a factory creates it, the factory receives the entire supply, not the originating wallet. The deployment tests demonstrate both paths. No requester address, owner address, oracle, registry, or other private configuration is required by this token.

For the launch system's token record, use the contract identifier and exact metadata in the table above, `constructorArgs: []`, and `totalSupply: "1000000000000000000000000000"`. Pool parameters, chain addresses, requester recipient, and distribution economics belong to the separate launch configuration and are not selected by this token project. The factory performs the swarm allocation, liquidity funding, and remainder transfer after construction; the token imposes no restrictions on those transfers.

No deployment transactions are broadcast by this project.

## After launch

There are no owner-settable settings or maintenance calls. The launch operator is responsible for verifying the source and build settings on the target chain, checking name/symbol/decimals and total supply, confirming the constructor recipient, and confirming the subsequent distribution and pool integration. The deployer controls the initial supply until those transfers occur.

Holders are responsible for recipient accuracy and spender approvals. When changing a nonzero allowance for a spender that might use it concurrently, revoke it to zero and confirm that transaction before setting the replacement. Read `allowance` for its current value rather than reconstructing allowance usage solely from events.

There is no administrative recovery function: SPAD or other assets sent to the token contract itself cannot be recovered through this contract. Complete independent adversarial review and the network's launch integration checks before release. See [SECURITY.md](SECURITY.md) for the local review's scope and limits.
