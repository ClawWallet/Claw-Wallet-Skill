# Claw Wallet Skill

Local sandbox wallet skill for OpenClaw and Claude Code agents. Install the sandbox locally, operate through localhost APIs or CLI, and support both local wallets and phase2 remote-managed wallets.

## Claude Code marketplace

This repository is now structured so it can be added as a third-party Claude Code marketplace.

Use:

```bash
/plugin marketplace add <this-repo-url>
/plugin install claw-wallet@claw-wallet-marketplace
```

This is a community marketplace setup, not an Anthropic-curated listing. To appear in Anthropic's official directory, the repo still needs to pass their review and submission flow.

## Installation

Skill assets are hosted at **`https://test.clawwallet.cc`**. Deploy that site so these paths exist: **`/skills/install.sh`**, **`/skills/install.ps1`**, **`/skills/SKILL.md`**, **`/skills/claw-wallet.sh`**, **`/skills/claw-wallet`**, **`/skills/claw-wallet.ps1`**, **`/skills/claw-wallet.cmd`**, and **`/bin/<platform binary>`**.

### Linux / macOS (recommended)

From the workspace root:

```bash
mkdir -p skills/claw-wallet-test
cd skills/claw-wallet-test
curl -fsSL https://test.clawwallet.cc/skills/install.sh | bash
```

### Windows PowerShell

```powershell
New-Item -ItemType Directory -Path "skills\claw-wallet-test" -Force | Out-Null
Set-Location "skills\claw-wallet-test"
Invoke-WebRequest -Uri "https://test.clawwallet.cc/install.ps1" -OutFile "install.ps1" -UseBasicParsing
& ".\install.ps1"
```

### Option: npx skills add

For the `dev` test environment, prefer Option 1 so the local checkout is pinned to the `dev` branch explicitly.

```bash
npx skills add ClawWallet/Claw-Wallet-Skill -a openclaw --yes
```

Then run the installer from the cloned skill directory (or use the curl flow above instead of git).

### Developing from this repo

`install.sh` and `install.ps1` are now the unified local entrypoints.

- No argument: install flow, including wallet initialization
- `upgrade`: refresh skill files and binary without re-running wallet init
- `start` / `restart` / `stop` / `is-running` / `serve` / `uninstall`: runtime management commands

## After install

Verify status:

- `GET {CLAY_SANDBOX_URL}/health` — expected: `{"status": "ok"}`
- `GET {CLAY_SANDBOX_URL}/api/v1/wallet/status` with `Authorization: Bearer <token>` when a token is present; if `AGENT_TOKEN` is empty, local dev mode allows the request without the header — confirm wallet is ready

Token and URL are in `skills/claw-wallet-test/.env.clay`.

## Documentation

See [SKILL.md](./SKILL.md) for full documentation, API reference, and agent rules.
