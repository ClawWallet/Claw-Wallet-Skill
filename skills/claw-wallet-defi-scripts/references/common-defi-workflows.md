# Common DeFi Workflows

This reference maps a recorded DeFi session to a reusable workflow package.

## Package contract

Every generated package should use the same file roles:

- `workflow.md` for the human replay notes
- `workflow.json` for the machine-readable manifest
- `run.mjs` for the SDK-backed replay scaffold
- `README.md` for the one-command operator guide

## Normalized fields

Keep the package manifest focused on the data needed to replay the flow:

- `name`
- `slug`
- `workflow_type`
- `chain`
- `protocol`
- `required_env`
- `optional_env`
- `inputs`
- `prechecks`
- `execution_steps`
- `postconditions`
- `rollback`
- `notes`
- `sdk_surface`
- `generated_files`

## SDK mapping

Use the real Claw SDK boundary, not invented helper names.

### State and verification

Use these when the package needs wallet state, policy, or replay verification:

- `ClawSandboxClient.getStatus()`
- `ClawSandboxClient.refreshWallet()`
- `ClawSandboxClient.refreshAndGetAssets()`
- `ClawSandboxClient.getAssets()`
- `ClawSandboxClient.getHistory()`
- `ClawSandboxClient.getLocalPolicy()`
- `ClawSandboxClient.refreshChain()`

### Execution

Use these when the package signs, broadcasts, or submits a recorded action:

- `ClawSandboxClient.initWallet()`
- `ClawSandboxClient.unlockWallet()`
- `ClawSandboxClient.reactivateWallet()`
- `ClawSandboxClient.sign()`
- `ClawSandboxClient.broadcast()`
- `ClawSandboxClient.transfer()`
- `buildPersonalSignBody()`

### Direct OpenAPI routes

If the Claw wrapper does not expose a route yet, call it through:

- `createClawWalletClient(...).POST(...)`

Record the exact route in the package so the step is recoverable later.

Common examples in this repo include:

- `/api/v1/tx/swap/uniswap_v3`
- `/api/v1/tx/swap/solana-jup`
- `/api/v1/tx/bridge/lifi/execute`
- `/api/v1/tx/evm/invoke`
- `/api/v1/tx/broadcast`

### Optional adapters

Use chain adapters only when the recorded flow needs a native signer or account object:

- `@claw_wallet_sdk/claw_wallet/ethers`
- `@claw_wallet_sdk/claw_wallet/viem`
- `@claw_wallet_sdk/claw_wallet/solana`
- `@claw_wallet_sdk/claw_wallet/sui`

## Common workflow templates

### swap

Use for a single-asset swap on one chain.

Record:

- source token
- destination token
- amount
- slippage tolerance
- route selection

SDK calls:

- `getStatus()`
- `refreshAndGetAssets()`
- `getLocalPolicy()`
- protocol route through `createClawWalletClient(...).POST(...)` or the recorded SDK wrapper
- `sign()` / `broadcast()` or the recorded chain adapter
- `getHistory()`

### approve-and-swap

Use when allowance must exist before the swap.

Record:

- approval target
- approval amount
- swap amount
- approval receipt
- swap receipt

SDK calls:

- `getStatus()`
- `refreshAndGetAssets()`
- `getLocalPolicy()`
- approval transaction or route-specific route
- `sign()` / `broadcast()`
- swap transaction or route-specific route
- `getHistory()`

### bridge

Use when moving an asset between chains.

Record:

- source chain
- destination chain
- bridge protocol
- transfer amount
- destination address
- finality expectation

SDK calls:

- `getStatus()`
- `refreshChain()`
- `refreshAndGetAssets()`
- `getLocalPolicy()`
- bridge quote or route through `createClawWalletClient(...).POST(...)`
- `sign()` / `broadcast()`
- `getHistory()`

### stake-and-claim

Use when deposit and reward claim are separate actions.

Record:

- staking asset
- pool or vault
- stake amount
- claim cadence
- reward asset

SDK calls:

- `getStatus()`
- `refreshAndGetAssets()`
- `getLocalPolicy()`
- stake transaction or route-specific route
- claim transaction or route-specific route
- `getHistory()`

### lp-add

Use when adding liquidity to a pool.

Record:

- pool id
- token pair
- desired ratio
- minimum amounts
- LP receipt handling

SDK calls:

- `getStatus()`
- `refreshAndGetAssets()`
- `getLocalPolicy()`
- pool-specific deposit route
- `sign()` / `broadcast()`
- `getHistory()`

### lp-remove

Use when withdrawing liquidity from a pool.

Record:

- pool id
- LP amount
- expected outputs
- slippage tolerance

SDK calls:

- `getStatus()`
- `refreshAndGetAssets()`
- `getLocalPolicy()`
- burn or withdraw route
- `sign()` / `broadcast()`
- `getHistory()`

### batch-route

Use when multiple actions should run in order.

Record:

- ordered action list
- dependency between steps
- intermediate outputs
- failure stop condition

SDK calls:

- `getStatus()`
- `refreshAndGetAssets()`
- `getLocalPolicy()`
- one SDK or OpenAPI call per recorded step
- `getHistory()`

### risk-gated-action

Use when the flow must pass policy or risk checks first.

Record:

- gating condition
- check source
- allow or deny outcome
- confirmation point

SDK calls:

- `getStatus()`
- `getLocalPolicy()`
- `refreshAndGetAssets()`
- `sign()` only after the gate is accepted
- `broadcast()` or `transfer()` for the final action
- `getHistory()`

## Implementation note

If the flow does not match a common template, the package should still use the same file contract and should keep the protocol step explicit in `run.mjs`.

The workflow package is not the protocol implementation itself. It is the recorded replay bundle that tells the next agent exactly which SDK layer to use, what to check before execution, and what to verify afterward.
