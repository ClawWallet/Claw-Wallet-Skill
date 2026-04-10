# Claw Wallet Skill

Hermes / Agent Skills compatible wallet skill for Claw Wallet. The skill document follows the standard `SKILL.md` frontmatter format that Hermes expects, while the wallet runtime it manages still installs persistent state into `skills/claw-wallet` inside the active workspace.

## Hermes packaging

Hermes discovers skills from skill directories that contain a `SKILL.md` file. For local development, place this skill in a Hermes skills directory such as:

- `~/.hermes/skills/finance/claw-wallet/`
- `workspace/.agents/skills/claw-wallet/`

The skill package itself is Hermes-compatible; the wallet runtime it controls still uses `skills/claw-wallet/` as its workspace install path.

Useful Hermes commands:

```bash
hermes skills list
hermes skills search wallet
```

## Installation

Skill assets are hosted at **`https://www.clawwallet.cc`**. Deploy that site so these paths exist: **`/install`** (same body as `install.sh`), **`/install.ps1`**, **`/SKILL.md`**, **`/claw-wallet.sh`**, **`/claw-wallet`**, **`/claw-wallet.ps1`**, **`/claw-wallet.cmd`**, and **`/bin/<platform binary>`**.

### Linux / macOS (recommended)

From the workspace root:

```bash
mkdir -p skills/claw-wallet
cd skills/claw-wallet
curl -fsSL https://www.clawwallet.cc/install | bash
```

### Windows PowerShell

```powershell
New-Item -ItemType Directory -Path "skills\claw-wallet" -Force | Out-Null
Set-Location "skills\claw-wallet"
Invoke-WebRequest -Uri "https://www.clawwallet.cc/install.ps1" -OutFile "install.ps1" -UseBasicParsing
& ".\install.ps1"
```

### Using with Hermes

Hermes loads this repository as a skill package, but the actual wallet binaries and local config are still installed by the Claw Wallet bootstrap flow into `skills/claw-wallet`.

After the skill is available to Hermes, use the install flow below from the active workspace root.

### Developing from this repo

Run `bash install.sh` or `install.ps1` inside `skills/claw-wallet` with **`CLAW_WALLET_SKIP_SKILL_DOWNLOAD=1`** to keep local `SKILL.md` and wrappers without overwriting them from the CDN.

## After install

Verify status:

- `GET {CLAY_SANDBOX_URL}/health` — expected: `{"status": "ok"}`
- `GET {CLAY_SANDBOX_URL}/api/v1/wallet/status` with `Authorization: Bearer <token>` — confirm wallet is ready

Token and URL are in `skills/claw-wallet/.env.clay`.

## Documentation

See [SKILL.md](./SKILL.md) for full documentation, API reference, and agent rules.
