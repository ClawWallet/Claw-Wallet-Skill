#!/usr/bin/env node
import { mkdir, readdir, writeFile } from "node:fs/promises";
import path from "node:path";

const EVM_CHAINS = new Set([
  "ethereum",
  "0g",
  "base",
  "bsc",
  "arbitrum",
  "optimism",
  "polygon",
  "avalanche",
  "linea",
  "zksync",
  "monad",
  "kite",
  "tempo",
]);

const WORKFLOW_PROFILES = {
  swap: {
    summary: "Single-asset or routed swap on one chain.",
    inputs: [
      "source token",
      "destination token",
      "amount",
      "slippage tolerance",
      "recipient or target address when different from the sandbox wallet",
    ],
    prechecks: [
      "Load the wallet snapshot with ClawSandboxClient.getStatus().",
      "Refresh balances with ClawSandboxClient.refreshAndGetAssets() or ClawSandboxClient.refreshWallet().",
      "Read the current policy with ClawSandboxClient.getLocalPolicy().",
      "Verify that the route fits the recorded slippage and minimum-output limits.",
    ],
    execution: [
      "Resolve the recorded swap route through the protocol layer or the typed OpenAPI client.",
      "Build the transaction payload that matches the recorded route.",
      "Sign the payload with the Claw SDK or the chain adapter that matches the recorded chain.",
      "Broadcast or submit the transaction through the Claw SDK.",
    ],
    postconditions: [
      "Confirm the balances changed as expected.",
      "Record the resulting transaction hash and history entry.",
    ],
    rollback: [
      "If the swap was not broadcast, stop and keep the package in replayable state.",
      "If the swap was broadcast, record the failure and do not guess a recovery path without the recorded protocol result.",
    ],
  },
  "approve-and-swap": {
    summary: "Token approval followed by swap on one chain.",
    inputs: [
      "approval target",
      "approval amount",
      "swap amount",
      "source token",
      "destination token",
      "slippage tolerance",
    ],
    prechecks: [
      "Load the wallet snapshot with ClawSandboxClient.getStatus().",
      "Refresh balances with ClawSandboxClient.refreshAndGetAssets().",
      "Read the current policy with ClawSandboxClient.getLocalPolicy().",
      "Check the recorded allowance before planning the approval step.",
    ],
    execution: [
      "Prepare the approval transaction or route-specific approval call.",
      "Record the approval hash before moving to the swap step.",
      "Build the swap payload only after the approval is accepted.",
      "Sign and broadcast each on-chain action through the Claw SDK.",
    ],
    postconditions: [
      "Confirm allowance is present and the destination asset is updated.",
      "Record the approval and swap transaction hashes in the workflow artifact.",
    ],
    rollback: [
      "Do not continue to the swap if approval fails.",
      "If the approval succeeded but the swap failed, keep both hashes in the package and document the recovery path separately.",
    ],
  },
  bridge: {
    summary: "Bridge an asset from one chain to another.",
    inputs: [
      "source chain",
      "destination chain",
      "bridge protocol",
      "amount",
      "destination address",
      "finality expectations",
    ],
    prechecks: [
      "Load the wallet snapshot with ClawSandboxClient.getStatus().",
      "Refresh the relevant chain with ClawSandboxClient.refreshChain().",
      "Refresh balances with ClawSandboxClient.refreshAndGetAssets().",
      "Read the current policy with ClawSandboxClient.getLocalPolicy().",
    ],
    execution: [
      "Resolve the bridge quote through the protocol layer or the typed OpenAPI client.",
      "Submit the source-chain action through the Claw SDK.",
      "Wait for bridge completion or relay status updates using the recorded status endpoint.",
      "Verify the destination-chain receipt or balance update.",
    ],
    postconditions: [
      "Confirm the destination asset exists and the amount matches the recorded bridge outcome.",
      "Store the bridge status trail and final transaction identifiers.",
    ],
    rollback: [
      "If the source-chain transaction is pending, keep polling instead of restarting the flow.",
      "If the bridge has already left the source chain, document the recovery and do not create an untracked retry.",
    ],
  },
  "stake-and-claim": {
    summary: "Stake an asset and later claim rewards.",
    inputs: [
      "staking asset",
      "pool or vault",
      "stake amount",
      "claim cadence",
      "reward asset",
    ],
    prechecks: [
      "Load the wallet snapshot with ClawSandboxClient.getStatus().",
      "Refresh balances with ClawSandboxClient.refreshAndGetAssets().",
      "Read the current policy with ClawSandboxClient.getLocalPolicy().",
      "Confirm the claim window or reward schedule from the recorded protocol state.",
    ],
    execution: [
      "Build the stake transaction or route-specific deposit call.",
      "Record the staking receipt and the pool position.",
      "When the claim window opens, build the claim step from the recorded pool state.",
      "Sign and broadcast both actions through the Claw SDK.",
    ],
    postconditions: [
      "Confirm the position or reward balance is visible in the refreshed snapshot.",
      "Record the claim schedule and the reward receipt in the package.",
    ],
    rollback: [
      "If staking fails, do not fabricate the claim step.",
      "If claim timing is the only missing input, leave the package with a timed reminder instead of a guessed retry.",
    ],
  },
  "lp-add": {
    summary: "Add liquidity to a pool.",
    inputs: [
      "pool id",
      "token pair",
      "desired amounts",
      "minimum amounts",
      "LP receipt handling",
    ],
    prechecks: [
      "Load the wallet snapshot with ClawSandboxClient.getStatus().",
      "Refresh balances with ClawSandboxClient.refreshAndGetAssets().",
      "Read the current policy with ClawSandboxClient.getLocalPolicy().",
      "Validate the pool state and the recorded ratio before building the deposit.",
    ],
    execution: [
      "Prepare the add-liquidity route or protocol-specific call.",
      "Sign and broadcast the pool deposit with the Claw SDK or the recorded chain adapter.",
      "Capture the LP token receipt or position id.",
      "Persist the execution result in the workflow artifact.",
    ],
    postconditions: [
      "Confirm the LP position exists in the refreshed history or assets snapshot.",
      "Store the LP receipt and the final pool balance.",
    ],
    rollback: [
      "If the deposit has not been broadcast, stop and keep the package ready for replay.",
      "If the pool state changed, require a fresh recorded quote before rerunning the package.",
    ],
  },
  "lp-remove": {
    summary: "Remove liquidity from a pool.",
    inputs: [
      "pool id",
      "LP amount",
      "expected outputs",
      "slippage tolerance",
    ],
    prechecks: [
      "Load the wallet snapshot with ClawSandboxClient.getStatus().",
      "Refresh balances with ClawSandboxClient.refreshAndGetAssets().",
      "Read the current policy with ClawSandboxClient.getLocalPolicy().",
      "Confirm the LP position and exit constraints from the recorded workflow.",
    ],
    execution: [
      "Prepare the burn or withdraw step from the recorded pool state.",
      "Sign and broadcast the removal transaction through the Claw SDK.",
      "Capture the withdrawal outputs and any resulting receipts.",
      "Save the post-withdraw balance snapshot.",
    ],
    postconditions: [
      "Confirm the LP token position is gone or reduced as expected.",
      "Record the withdrawal hashes and the received assets.",
    ],
    rollback: [
      "If the withdrawal was not broadcast, leave the package as a safe draft.",
      "If the LP position has already moved, refresh the workflow inputs before rerunning.",
    ],
  },
  "batch-route": {
    summary: "Ordered multi-step DeFi route.",
    inputs: [
      "ordered action list",
      "dependency between steps",
      "intermediate outputs",
      "step-specific chain or protocol settings",
    ],
    prechecks: [
      "Load the wallet snapshot with ClawSandboxClient.getStatus().",
      "Refresh balances with ClawSandboxClient.refreshAndGetAssets().",
      "Read the current policy with ClawSandboxClient.getLocalPolicy().",
      "Verify each dependency before the first on-chain action.",
    ],
    execution: [
      "Run the recorded actions in order and stop on the first failure.",
      "Persist each intermediate receipt or hash into the package artifact.",
      "Use the protocol layer only where the Claw SDK does not already wrap the route.",
      "Sign and broadcast each step through the SDK boundary that matches the step.",
    ],
    postconditions: [
      "Confirm the final state matches the recorded end-of-flow snapshot.",
      "Store the ordered receipts so the route can be replayed one step at a time.",
    ],
    rollback: [
      "Do not auto-retry later steps if an earlier step fails.",
      "Record the failed step id and the last successful hash for manual recovery.",
    ],
  },
  "risk-gated-action": {
    summary: "Action that must pass policy or risk checks before execution.",
    inputs: [
      "gating condition",
      "check source",
      "allow or deny outcome",
      "confirmation point",
    ],
    prechecks: [
      "Load the wallet snapshot with ClawSandboxClient.getStatus().",
      "Read the current policy with ClawSandboxClient.getLocalPolicy().",
      "Refresh balances with ClawSandboxClient.refreshAndGetAssets().",
      "Verify the policy gate before any signing step is prepared.",
    ],
    execution: [
      "Capture the policy decision and the human confirmation point.",
      "Only build the transaction after the gate has passed.",
      "Sign and broadcast through the Claw SDK.",
      "Record the gate outcome alongside the on-chain result.",
    ],
    postconditions: [
      "Confirm the recorded action matches the approved risk gate.",
      "Save the policy snapshot used for the decision.",
    ],
    rollback: [
      "If the gate denies the action, stop and keep the package as a safe record.",
      "If the policy changes, refresh the workflow before any retry.",
    ],
  },
};

const SDK_SURFACE = {
  core: [
    "ClawSandboxClient.getStatus()",
    "ClawSandboxClient.refreshWallet()",
    "ClawSandboxClient.refreshAndGetAssets()",
    "ClawSandboxClient.getAssets()",
    "ClawSandboxClient.getHistory()",
    "ClawSandboxClient.getLocalPolicy()",
    "ClawSandboxClient.refreshChain()",
    "ClawSandboxClient.initWallet()",
    "ClawSandboxClient.unlockWallet()",
    "ClawSandboxClient.reactivateWallet()",
    "ClawSandboxClient.sign()",
    "ClawSandboxClient.broadcast()",
    "ClawSandboxClient.transfer()",
    "createClawWalletClient(...).POST(...) for protocol routes not wrapped by ClawSandboxClient",
    "buildPersonalSignBody()",
  ],
  adapters: [
    "@claw_wallet_sdk/claw_wallet/ethers -> ClawEthersSigner, createClawSandboxJsonRpcProvider",
    "@claw_wallet_sdk/claw_wallet/viem -> createClawAccountFromSandbox",
    "@claw_wallet_sdk/claw_wallet/solana -> ClawSolanaSigner",
    "@claw_wallet_sdk/claw_wallet/sui -> ClawSuiSigner",
  ],
};

function parseArgs(argv) {
  const args = {
    name: "",
    workflow: "batch-route",
    chain: "",
    protocol: "",
    step: [],
    note: [],
    outputDir: "scripts",
    overwrite: false,
  };

  if (argv.length === 0) {
    throw new Error("missing workflow package name");
  }

  args.name = argv[0];
  for (let i = 1; i < argv.length; i += 1) {
    const token = argv[i];
    const next = argv[i + 1];
    switch (token) {
      case "--workflow":
        if (!next) throw new Error("--workflow requires a value");
        args.workflow = next;
        i += 1;
        break;
      case "--chain":
        if (!next) throw new Error("--chain requires a value");
        args.chain = next;
        i += 1;
        break;
      case "--protocol":
        if (!next) throw new Error("--protocol requires a value");
        args.protocol = next;
        i += 1;
        break;
      case "--step":
        if (!next) throw new Error("--step requires a value");
        args.step.push(next);
        i += 1;
        break;
      case "--note":
        if (!next) throw new Error("--note requires a value");
        args.note.push(next);
        i += 1;
        break;
      case "--output-dir":
        if (!next) throw new Error("--output-dir requires a value");
        args.outputDir = next;
        i += 1;
        break;
      case "--overwrite":
        args.overwrite = true;
        break;
      default:
        throw new Error(`unknown argument: ${token}`);
    }
  }

  if (!Object.prototype.hasOwnProperty.call(WORKFLOW_PROFILES, args.workflow)) {
    throw new Error(`unknown workflow template: ${args.workflow}`);
  }

  return args;
}

function slugify(value) {
  return String(value)
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/-{2,}/g, "-")
    .replace(/^-+|-+$/g, "") || "workflow";
}

function listify(...items) {
  return items.map((item) => String(item).trim()).filter(Boolean);
}

function cloneArray(value) {
  return [...value];
}

function buildPackageSpec(args) {
  const profile = WORKFLOW_PROFILES[args.workflow];
  const slug = slugify(args.name);
  const chain = String(args.chain || "").trim();
  const protocol = String(args.protocol || "").trim();
  const requiredEnv = ["CLAY_SANDBOX_URL", "CLAY_UID"];
  const optionalEnv = ["CLAY_AGENT_TOKEN"];

  if (chain) {
    optionalEnv.push(`CHAIN_${chain.toUpperCase().replace(/-/g, "_")}_RPC_URL`);
  }
  if (protocol) {
    optionalEnv.push(`PROTOCOL_${protocol.toUpperCase().replace(/-/g, "_")}_ROUTE`);
  }

  const executionSteps = cloneArray(profile.execution);
  executionSteps.push(...listify(...args.step));
  const notes = listify(...args.note);
  if (chain) notes.push(`Primary chain: ${chain}`);
  if (protocol) notes.push(`Protocol: ${protocol}`);

  const packageDir = path.posix.join(args.outputDir.replaceAll("\\", "/"), slug);

  return {
    name: String(args.name).trim(),
    slug,
    workflow_type: args.workflow,
    summary: profile.summary,
    chain,
    protocol,
    package_dir: packageDir,
    required_env: requiredEnv,
    optional_env: optionalEnv,
    inputs: cloneArray(profile.inputs),
    prechecks: cloneArray(profile.prechecks),
    execution_steps: executionSteps,
    postconditions: cloneArray(profile.postconditions),
    rollback: cloneArray(profile.rollback),
    notes,
    sdk_surface: {
      core: cloneArray(SDK_SURFACE.core),
      adapters: cloneArray(SDK_SURFACE.adapters),
    },
    generated_files: ["workflow.md", "workflow.json", "run.mjs", "README.md"],
  };
}

function renderWorkflowMarkdown(spec) {
  const lines = [
    `# ${spec.name}`,
    "",
    `- workflow_type: \`${spec.workflow_type}\``,
    `- package_dir: \`${spec.package_dir}\``,
  ];
  if (spec.chain) lines.push(`- chain: \`${spec.chain}\``);
  if (spec.protocol) lines.push(`- protocol: \`${spec.protocol}\``);
  lines.push(
    "",
    "## Purpose",
    String(spec.summary),
    "",
    "## Required Env",
  );
  for (const envName of spec.required_env) lines.push(`- \`${envName}\``);
  lines.push("", "## Optional Env");
  for (const envName of spec.optional_env) lines.push(`- \`${envName}\``);
  lines.push("", "## Inputs");
  for (const item of spec.inputs) lines.push(`- ${item}`);
  lines.push("", "## Prechecks");
  for (const item of spec.prechecks) lines.push(`- ${item}`);
  lines.push("", "## SDK Surface", "### Core");
  for (const item of spec.sdk_surface.core) lines.push(`- \`${item}\``);
  lines.push("", "### Adapters");
  for (const item of spec.sdk_surface.adapters) lines.push(`- \`${item}\``);
  lines.push("", "## Execution Steps");
  spec.execution_steps.forEach((step, index) => {
    lines.push(`${index + 1}. ${step}`);
  });
  lines.push("", "## Postconditions");
  for (const item of spec.postconditions) lines.push(`- ${item}`);
  lines.push("", "## Rollback");
  for (const item of spec.rollback) lines.push(`- ${item}`);
  if (spec.notes.length) {
    lines.push("", "## Notes");
    for (const item of spec.notes) lines.push(`- ${item}`);
  }
  lines.push("", "## Generated Files");
  for (const item of spec.generated_files) lines.push(`- \`${item}\``);
  return `${lines.join("\n")}\n`;
}

function renderReadme(spec) {
  const requiredEnv = spec.required_env.map((name) => `- \`${name}\``).join("\n");
  const optionalEnv = spec.optional_env.map((name) => `- \`${name}\``).join("\n");
  const coreSurface = spec.sdk_surface.core.map((item) => `- \`${item}\``).join("\n");
  const adapterList = spec.sdk_surface.adapters.map((item) => `- \`${item}\``).join("\n");

  return `# ${spec.name}

This package captures a completed Claw Wallet DeFi flow as a reusable workflow package.

## Layout

- \`workflow.md\`: human-readable replay notes
- \`workflow.json\`: machine-readable manifest
- \`run.mjs\`: SDK-backed replay scaffold
- \`README.md\`: operator instructions

## Required Environment

${requiredEnv}

## Optional Environment

${optionalEnv}

## SDK Surface

### Core

${coreSurface}

### Optional adapters

${adapterList}

## Run

1. Install the SDK package and any adapter peers that your recorded flow needs.
2. Fill in the protocol-layer call in \`run.mjs\` if the generated scaffold still has a placeholder.
3. Run:

\`\`\`bash
node run.mjs
\`\`\`

## Notes

The generated \`run.mjs\` performs the wallet snapshot, execution stub, and post-run verification using the Claw SDK. It intentionally leaves the protocol-specific step explicit so the package records the real route instead of inventing it.
`;
}

function renderRunMjs(spec) {
  const evmChains = JSON.stringify([...EVM_CHAINS].sort());
  return `#!/usr/bin/env node
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import {
  ClawSandboxClient,
  createClawWalletClient,
  buildPersonalSignBody,
} from "@claw_wallet_sdk/claw_wallet";

const workflowDir = dirname(fileURLToPath(import.meta.url));
const manifest = JSON.parse(await readFile(resolve(workflowDir, "workflow.json"), "utf8"));

function requireEnv(name) {
  const value = process.env[name]?.trim() ?? "";
  if (!value) {
    throw new Error(\`missing $\{name}\`);
  }
  return value;
}

function optionalEnv(name) {
  return process.env[name]?.trim() ?? "";
}

async function loadOptionalAdapter(chain) {
  const normalized = String(chain || "").trim().toLowerCase();
  if (!normalized) return null;
  const evmChains = ${evmChains};
  if (evmChains.includes(normalized)) {
    return import("@claw_wallet_sdk/claw_wallet/ethers");
  }
  if (normalized === "solana") {
    return import("@claw_wallet_sdk/claw_wallet/solana");
  }
  if (normalized === "sui") {
    return import("@claw_wallet_sdk/claw_wallet/sui");
  }
  return null;
}

async function snapshotBefore(sandbox) {
  return {
    status: await sandbox.getStatus(),
    assets: await sandbox.refreshAndGetAssets(),
    policy: await sandbox.getLocalPolicy(),
  };
}

async function executeProtocolStep(context) {
  // Replace this placeholder with the actual protocol-layer call that was
  // recorded in the original DeFi session.
  // Use one of these SDK paths depending on the recorded flow:
  // - createClawWalletClient(...).POST(<protocol path>, { body }) for direct OpenAPI routes
  // - sandbox.sign(...) / sandbox.broadcast(...) for the core wallet pipeline
  // - optional adapter imports from @claw_wallet_sdk/claw_wallet/{ethers|solana|sui|viem}
  //   when the protocol needs a chain-native signer or account object.
  // - buildPersonalSignBody(...) when the recorded step is a personal-sign style payload
  throw new Error("TODO: implement the recorded protocol step for this workflow package.");
}

async function main() {
  const sandboxUrl = requireEnv("CLAY_SANDBOX_URL");
  const sandboxToken = optionalEnv("CLAY_AGENT_TOKEN");
  const uid = requireEnv("CLAY_UID");

  const sandbox = new ClawSandboxClient({
    uid,
    sandboxUrl,
    sandboxToken,
  });

  const api = createClawWalletClient({
    baseUrl: sandboxUrl,
    agentToken: sandboxToken || undefined,
  });

  const adapterModule = await loadOptionalAdapter(manifest.chain);
  const before = await snapshotBefore(sandbox);

  const protocolResult = await executeProtocolStep({
    manifest,
    sandbox,
    api,
    adapterModule,
    before,
    buildPersonalSignBody,
  });

  const after = {
    status: await sandbox.getStatus(),
    assets: await sandbox.getAssets(),
    history: await sandbox.getHistory({
      chain: manifest.chain || undefined,
      limit: 20,
    }),
  };

  console.log(JSON.stringify({
    manifest,
    before,
    protocolResult,
    after,
  }, null, 2));
}

await main();
`;
}

async function writePackage(spec, overwrite) {
  const packageDir = path.resolve(spec.package_dir);
  const entries = await readdir(packageDir).catch(() => []);
  if (entries.length && !overwrite) {
    throw new Error(`package directory ${packageDir} already exists; use --overwrite to replace its files`);
  }
  await mkdir(packageDir, { recursive: true });

  const files = {
    "workflow.json": `${JSON.stringify(spec, null, 2)}\n`,
    "workflow.md": renderWorkflowMarkdown(spec),
    "README.md": renderReadme(spec),
    "run.mjs": renderRunMjs(spec),
  };

  await Promise.all(
    Object.entries(files).map(([name, content]) =>
      writeFile(path.join(packageDir, name), content, "utf8"),
    ),
  );
}

function validateWorkflow(args) {
  if (!Object.prototype.hasOwnProperty.call(WORKFLOW_PROFILES, args.workflow)) {
    throw new Error(`unknown workflow template: ${args.workflow}`);
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  validateWorkflow(args);
  const spec = buildPackageSpec(args);
  await writePackage(spec, args.overwrite);
  console.log(`Workflow package written to ${spec.package_dir}`);
}

await main();
