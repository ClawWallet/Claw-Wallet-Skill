# claw wallet minimal installer for Windows (PowerShell)
# Served at: https://test.clawwallet.cc/skills/install.ps1
# Usage: first-time install (wallet init) | upgrade (CLAW_WALLET_SKIP_INIT=1, no wallet init)
$ErrorActionPreference = "Stop"
# When upgrade runs the script from a temp file, CLAW_WALLET_INSTALL_DIR is the skill directory
if ($env:CLAW_WALLET_INSTALL_DIR) {
    $ScriptDir = $env:CLAW_WALLET_INSTALL_DIR
} else {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
Set-Location -Path $ScriptDir

$BaseUrl = if ($env:CLAW_WALLET_BASE_URL) { $env:CLAW_WALLET_BASE_URL } else { "https://test.clawwallet.cc" }

function Download-SkillBundle {
    Write-Host "Downloading SKILL.md and wrapper scripts from $BaseUrl ..."
    $skillMd = Join-Path $ScriptDir "SKILL.md"
    Invoke-WebRequest -Uri "$BaseUrl/skills/SKILL.md" -OutFile $skillMd -UseBasicParsing
    $ps1 = Join-Path $ScriptDir "claw-wallet.ps1"
    Invoke-WebRequest -Uri "$BaseUrl/skills/claw-wallet.ps1" -OutFile $ps1 -UseBasicParsing
    $cmdPath = Join-Path $ScriptDir "claw-wallet.cmd"
    try {
        Invoke-WebRequest -Uri "$BaseUrl/skills/claw-wallet.cmd" -OutFile $cmdPath -UseBasicParsing
    } catch {
        Write-Host "Note: claw-wallet.cmd not available from server (optional)."
    }
}

if ($env:CLAW_WALLET_SKIP_SKILL_DOWNLOAD -ne "1") {
    Download-SkillBundle
}

$BinaryUrl = "$BaseUrl/bin/clay-sandbox-windows-amd64.exe"
$BinaryTarget = Join-Path $ScriptDir "clay-sandbox.exe"

# --- Common: stop, download, start ---
$SkipStop = $env:CLAW_WALLET_SKIP_STOP -eq "1"
if (-not $SkipStop) {
    & (Join-Path $ScriptDir "claw-wallet.ps1") stop *> $null
}

Write-Host "Downloading sandbox binary from $BinaryUrl ..."
$TempBinary = "$BinaryTarget.download"
Invoke-WebRequest -Uri $BinaryUrl -OutFile $TempBinary -UseBasicParsing
Move-Item -Path $TempBinary -Destination $BinaryTarget -Force

& (Join-Path $ScriptDir "claw-wallet.ps1") start

# --- First-time only: wallet init (skipped when upgrade passes CLAW_WALLET_SKIP_INIT=1) ---
function Do-WalletInit {
    Write-Host "Waiting for sandbox and initializing wallet ..."
    $envClayPath = Join-Path $ScriptDir ".env.clay"
    for ($i = 1; $i -le 90; $i++) {
        $sandboxUrl = $null
        $agentToken = $null
        if (Test-Path $envClayPath) {
            $lines = Get-Content $envClayPath -ErrorAction SilentlyContinue
            foreach ($line in $lines) {
                if ($line -match '^CLAY_SANDBOX_URL=(.+)$') { $sandboxUrl = $matches[1].Trim().Trim('"').Trim("'").TrimEnd() }
                if ($line -match '^(CLAY_AGENT_TOKEN|AGENT_TOKEN)=(.+)$') { $agentToken = $matches[2].Trim().Trim('"').Trim("'").TrimEnd() }
            }
        }
        if ($sandboxUrl) {
            try {
                $health = Invoke-RestMethod -Uri "$sandboxUrl/health" -Method Get -ErrorAction Stop
                if ($health.status -eq "ok" -and $agentToken) {
                    $headers = @{
                        "Authorization" = "Bearer $agentToken"
                        "Content-Type" = "application/json"
                    }
                    $initResp = Invoke-RestMethod -Uri "$sandboxUrl/api/v1/wallet/init" -Method Post -Headers $headers -Body "{}" -ErrorAction Stop
                    if ($initResp) {
                        Write-Host "Wallet initialized."
                    }
                    return
                }
            } catch {
                # Health or init may fail, retry
            }
        }
        Start-Sleep -Seconds 1
    }
    Write-Host "Warning: health not ok or .env.clay not ready after 90s. Check sandbox.log, then run POST {CLAY_SANDBOX_URL}/api/v1/wallet/init manually. See SKILL.md."
}

if ($env:CLAW_WALLET_SKIP_INIT -ne "1") {
    Do-WalletInit
}

# --- Common: final messages ---
Write-Host "Check .env.clay for CLAY_SANDBOX_URL and CLAY_AGENT_TOKEN (or AGENT_TOKEN)."
Write-Host "HTTP clients (curl, agents) must call protected APIs with: Authorization: Bearer <same token>."
Write-Host "The same value is duplicated in identity.json as agent_token. See SKILL.md section 'HTTP authentication (sandbox)'."
Write-Host "Sandbox binary refreshed at: $BinaryTarget"

# Identity and config are persistent. To reset, delete .env.clay, identity.json and share3.json.
