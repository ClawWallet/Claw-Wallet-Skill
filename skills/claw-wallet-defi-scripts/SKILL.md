---
name: claw-wallet-defi-scripts
description: "Convert a completed Claw Wallet DeFi sequence into a reusable workflow package with SDK-backed verification, execution, and a replayable script entrypoint."
---

# Claw Wallet DeFi Scripts

## What this skill produces

Generate a workflow package under `scripts/<slug>/` with these files:

- `workflow.md`
- `workflow.json`
- `run.mjs`
- `README.md`

The package should capture a completed DeFi flow in a way that can be replayed, audited, and turned into a one-click script later.

Use `scripts/scaffold_defi_workflow.mjs` to generate the package.

## When to use

- Convert a finished swap, bridge, stake, LP, approval, or batch flow into a reusable package.
- Record the exact SDK calls used in a complex DeFi session.
- Preserve the protocol layer while keeping the wallet and signing layer explicit.
- Generate a package that another agent can re-run without reconstructing the flow from scratch.

## Core rule

Do not write a generic template and stop there.

The package must preserve:

- the chain and protocol
- the SDK calls used for wallet state, policy, signing, broadcasting, and verification
- the execution order
- the rollback or recovery note
- the protocol-specific inputs that made the flow succeed

If the SDK does not already wrap a protocol path, use the typed OpenAPI client from `createClawWalletClient(...)` and record the exact route in the package. Do not invent a helper name.

Common direct routes in this repo include `/api/v1/tx/swap/uniswap_v3`, `/api/v1/tx/swap/solana-jup`, `/api/v1/tx/bridge/lifi/execute`, `/api/v1/tx/evm/invoke`, and `/api/v1/tx/broadcast`.

## SDK boundary

Use the real Claw SDK surface:

- `ClawSandboxClient.getStatus()`
- `ClawSandboxClient.refreshWallet()`
- `ClawSandboxClient.refreshAndGetAssets()`
- `ClawSandboxClient.getAssets()`
- `ClawSandboxClient.getHistory()`
- `ClawSandboxClient.getLocalPolicy()`
- `ClawSandboxClient.refreshChain()`
- `ClawSandboxClient.initWallet()`
- `ClawSandboxClient.unlockWallet()`
- `ClawSandboxClient.reactivateWallet()`
- `ClawSandboxClient.sign()`
- `ClawSandboxClient.broadcast()`
- `ClawSandboxClient.transfer()`
- `createClawWalletClient(...)` for direct OpenAPI routes
- `buildPersonalSignBody()` for personal-sign style payloads
- optional chain adapters from:
  - `@claw_wallet_sdk/claw_wallet/ethers`
  - `@claw_wallet_sdk/claw_wallet/viem`
  - `@claw_wallet_sdk/claw_wallet/solana`
  - `@claw_wallet_sdk/claw_wallet/sui`

## Package contract

Every generated package should contain:

### `workflow.md`

Human-readable replay notes with:

- purpose
- required environment
- inputs
- prechecks
- SDK surface
- execution steps
- postconditions
- rollback
- notes

### `workflow.json`

Machine-readable manifest with:

- name
- slug
- workflow_type
- chain
- protocol
- required_env
- optional_env
- inputs
- prechecks
- execution_steps
- postconditions
- rollback
- notes
- sdk_surface
- generated_files

### `run.mjs`

Replay scaffold that:

- loads `workflow.json`
- snapshots wallet state with the Claw SDK
- leaves the protocol-specific step explicit in `executeProtocolStep(...)`
- uses the SDK for final verification
- treats `CLAY_AGENT_TOKEN` as optional so local dev mode can run without a bearer token

### `README.md`

Short operator guide with the command to run the package and the required environment.

## Workflow

### 1. Capture the sequence

Summarize the observed action chain in a stable form:

- chain
- protocol
- inputs
- approvals
- execution steps
- success criteria
- rollback or retry behavior

### 2. Normalize the recipe

Rewrite the flow as a workflow package, not as a generic checklist.

The package should still be readable by a person, but it must also be machine-friendly enough to regenerate the replay entrypoint.

### 3. Map the SDK

Record which SDK layer each part of the flow uses:

- wallet and policy state: `getStatus()`, `refreshWallet()`, `refreshAndGetAssets()`, `getAssets()`, `getHistory()`, `getLocalPolicy()`
- on-chain execution: `sign()`, `broadcast()`, `transfer()`
- direct protocol routes: `createClawWalletClient(...).POST(...)`
- chain-native adapters: the optional signer/account adapters in the SDK subpaths

### 4. Scaffold the package

If the flow matches a common template from `references/common-defi-workflows.md`, reuse that template and then fill in the real protocol inputs.

If it does not match a common template, generate a custom package and keep the protocol step explicit in `run.mjs`.

### 5. Hand off for implementation

After the package is stable, the next step is to fill the protocol layer with the real SDK or OpenAPI calls used by the project.

Do not invent SDK calls. If a route is missing from the wrapper layer, say so explicitly in the package and call the typed OpenAPI client directly.

## Output expectations

The generated package should make the next execution deterministic:

- the recorded flow is preserved in `workflow.md`
- the manifest is machine-readable in `workflow.json`
- the replay entrypoint exists in `run.mjs`
- the package has a clear command in `README.md`
- the SDK boundary is explicit
- the rollback note is recorded

If the flow moves funds or submits on-chain actions, still follow the wallet confirmation rules from the parent skill.

## References

- [Common DeFi workflows](references/common-defi-workflows.md)
