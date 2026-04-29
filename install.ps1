# claw wallet unified installer and runtime entrypoint for Windows (PowerShell)
# Served at: https://test.clawwallet.cc/skills/install.ps1
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -Path $ScriptDir

$BaseUrl = if ($env:CLAW_WALLET_BASE_URL) { $env:CLAW_WALLET_BASE_URL } else { "https://test.clawwallet.cc" }
$Command = if ($args.Count -gt 0) { $args[0].ToLowerInvariant() } else { "install" }

$BinaryUrl = "$BaseUrl/bin/clay-sandbox-windows-amd64.exe"
$BinaryPath = Join-Path $ScriptDir "clay-sandbox.exe"
$PidPath = Join-Path $ScriptDir "sandbox.pid"
$LogPath = Join-Path $ScriptDir "sandbox.log"
$ErrLogPath = Join-Path $ScriptDir "sandbox_err.log"

function Download-File {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Target
    )
    $tmpTarget = "$Target.download"
    Invoke-WebRequest -Uri $Url -OutFile $tmpTarget -UseBasicParsing
    Move-Item -Path $tmpTarget -Destination $Target -Force
}

function Download-SkillBundle {
    Write-Host "Downloading skill files from $BaseUrl ..."
    Download-File -Url "$BaseUrl/skills/SKILL.md" -Target (Join-Path $ScriptDir "SKILL.md")
    Download-File -Url "$BaseUrl/skills/install.ps1" -Target (Join-Path $ScriptDir "install.ps1")
    Download-File -Url "$BaseUrl/skills/claw-wallet.ps1" -Target (Join-Path $ScriptDir "claw-wallet.ps1")
    try {
        Download-File -Url "$BaseUrl/skills/claw-wallet.cmd" -Target (Join-Path $ScriptDir "claw-wallet.cmd")
    } catch {
        Write-Host "Note: claw-wallet.cmd not available from server (optional)."
    }
}

function Download-Binary {
    Write-Host "Downloading sandbox binary from $BinaryUrl ..."
    Download-File -Url $BinaryUrl -Target $BinaryPath
}

function Get-RunningSandboxPid {
    if (-not (Test-Path $PidPath)) { return $null }
    try {
        $raw = Get-Content -Path $PidPath -TotalCount 1 -ErrorAction SilentlyContinue
        $pidValue = "$raw".Trim()
        if (-not $pidValue) { return $null }
        $pidInt = [int]$pidValue
        $proc = Get-Process -Id $pidInt -ErrorAction SilentlyContinue
        if ($proc) { return $pidInt }
    } catch {
    }
    try { Remove-Item -Path $PidPath -Force -ErrorAction SilentlyContinue } catch { }
    return $null
}

function Prepare-LogPaths {
    try {
        if (-not (Test-Path $ScriptDir)) { New-Item -ItemType Directory -Path $ScriptDir -Force | Out-Null }
        if (Test-Path $LogPath) { Remove-Item -Path $LogPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path $ErrLogPath) { Remove-Item -Path $ErrLogPath -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType File -Path $LogPath -Force | Out-Null
        New-Item -ItemType File -Path $ErrLogPath -Force | Out-Null
        return
    } catch {
    }
    $baseTemp = $env:TEMP
    if (-not $baseTemp) {
        $baseTemp = Join-Path $env:SystemRoot "Temp"
    }
    $fallbackDir = Join-Path $baseTemp "claw-wallet"
    New-Item -ItemType Directory -Path $fallbackDir -Force | Out-Null
    $script:LogPath = Join-Path $fallbackDir "sandbox.log"
    $script:ErrLogPath = Join-Path $fallbackDir "sandbox_err.log"
    New-Item -ItemType File -Path $LogPath -Force | Out-Null
    New-Item -ItemType File -Path $ErrLogPath -Force | Out-Null
    Write-Host "Warning: could not use logs in $ScriptDir; using fallback logs in $fallbackDir"
}

function Start-Sandbox {
    $runningPid = Get-RunningSandboxPid
    if ($runningPid) {
        Write-Host "claw wallet sandbox is already running."
        Write-Host "PID file: $PidPath"
        Write-Host "Log files: $LogPath , $ErrLogPath"
        return
    }

    if (-not (Test-Path $BinaryPath)) {
        Write-Host "claw wallet sandbox is not installed. Expected binary at: $BinaryPath"
        Write-Host "Run: & `"$ScriptDir\install.ps1`""
        exit 1
    }

    Prepare-LogPaths
    $proc = Start-Process -FilePath $BinaryPath -ArgumentList @("serve") -WorkingDirectory $ScriptDir -RedirectStandardOutput $LogPath -RedirectStandardError $ErrLogPath -WindowStyle Hidden -PassThru
    if ($proc -and $proc.Id) {
        Set-Content -Path $PidPath -Value $proc.Id -Encoding ascii
    }
    Write-Host "claw wallet sandbox launched in the background."
    Write-Host "PID file: $PidPath"
    Write-Host "Log files: $LogPath , $ErrLogPath"
    if (Test-Path (Join-Path $ScriptDir ".env.clay")) {
        Write-Host "API auth: if HTTP returns 401, send header Authorization: Bearer <token> using AGENT_TOKEN or CLAY_AGENT_TOKEN from .env.clay (or agent_token in identity.json). See SKILL.md."
    }
}

function Stop-Sandbox {
    $runningPid = Get-RunningSandboxPid
    if ($runningPid) {
        try { Stop-Process -Id $runningPid -Force -ErrorAction SilentlyContinue } catch { }
    }
    if (Test-Path $BinaryPath) {
        try { & $BinaryPath stop *> $null } catch { }
    }
    try { Remove-Item -Path $PidPath -Force -ErrorAction SilentlyContinue } catch { }
}

function Get-EnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$Lines
    )
    foreach ($line in $Lines) {
        if ($line -match ("^" + [regex]::Escape($Name) + "=(.+)$")) {
            return $matches[1].Trim().Trim('"').Trim("'").TrimEnd()
        }
    }
    return $null
}

function Do-WalletInit {
    Write-Host "Waiting for sandbox and initializing wallet ..."
    $envClayPath = Join-Path $ScriptDir ".env.clay"
    for ($i = 1; $i -le 90; $i++) {
        $sandboxUrl = $null
        $agentToken = $null
        if (Test-Path $envClayPath) {
            $lines = Get-Content $envClayPath -ErrorAction SilentlyContinue
            $sandboxUrl = Get-EnvValue -Name "CLAY_SANDBOX_URL" -Lines $lines
            $agentToken = Get-EnvValue -Name "CLAY_AGENT_TOKEN" -Lines $lines
            if (-not $agentToken) {
                $agentToken = Get-EnvValue -Name "AGENT_TOKEN" -Lines $lines
            }
        }
        if ($sandboxUrl) {
            try {
                $health = Invoke-RestMethod -Uri "$sandboxUrl/health" -Method Get -ErrorAction Stop
                if ($health.status -eq "ok") {
                    $initParams = @{
                        Uri         = "$sandboxUrl/api/v1/wallet/init"
                        Method      = "Post"
                        Body        = "{}"
                        ErrorAction = "Stop"
                        Headers     = @{
                            "Content-Type" = "application/json"
                        }
                    }
                    if ($agentToken) {
                        $initParams["Headers"]["Authorization"] = "Bearer $agentToken"
                    }
                    $initResp = Invoke-RestMethod @initParams
                    if ($initResp) {
                        Write-Host "Wallet initialized."
                    } else {
                        Write-Host "Wallet init request completed."
                    }
                    return
                }
            } catch {
            }
        }
        if (($i % 10) -eq 0) {
            Write-Host "  Still waiting for sandbox health or wallet/init ... (${i}s)"
        }
        Start-Sleep -Seconds 1
    }
    Write-Host "Warning: health not ok or .env.clay not ready after 90s. Check sandbox.log, then run POST {CLAY_SANDBOX_URL}/api/v1/wallet/init manually. If AGENT_TOKEN is empty, local dev mode allows the request without Authorization. See SKILL.md."
}

function Print-FinalMessages {
    Write-Host "Check .env.clay for CLAY_SANDBOX_URL"
    Write-Host "If you have set an AGENT_TOKEN, then HTTP clients (curl, agents) must call protected APIs with: Authorization: Bearer <same token>."
    Write-Host "Sandbox start success. at: $BinaryPath"
}

function Install-OrUpgrade {
    param([bool]$RunWalletInit)
    Stop-Sandbox
    Download-SkillBundle
    Download-Binary
    Start-Sandbox
    if ($RunWalletInit) {
        Do-WalletInit
    }
    Print-FinalMessages
}

function Uninstall-Skill {
    Stop-Sandbox
    Write-Host ""
    Write-Host "=== WARNING: Uninstall claw-wallet skill ==="
    Write-Host "This will DELETE the entire skill directory and all wallet data."
    Write-Host "Files to be removed: .env.clay, identity.json, share3.json, and all others."
    Write-Host "This action is IRREVERSIBLE. Please backup .env.clay, identity.json, share3.json first if needed."
    Write-Host ""
    $confirm = Read-Host "Type 'yes' to confirm uninstall"
    if ($confirm -ne "yes") {
        Write-Host "Uninstall cancelled."
        return
    }
    Write-Host "Removing $ScriptDir ..."
    $ParentDir = Split-Path -Parent $ScriptDir
    Set-Location $ParentDir
    Remove-Item -Path $ScriptDir -Recurse -Force
    Write-Host "claw-wallet skill has been uninstalled."
}

switch ($Command) {
    "install" {
        Install-OrUpgrade -RunWalletInit $true
        break
    }
    "upgrade" {
        Install-OrUpgrade -RunWalletInit $false
        break
    }
    "start" {
        Start-Sandbox
        break
    }
    "restart" {
        Stop-Sandbox
        Start-Sleep -Seconds 1
        Start-Sandbox
        break
    }
    "stop" {
        Stop-Sandbox
        Write-Host "claw wallet sandbox stop requested."
        break
    }
    "is-running" {
        if (Get-RunningSandboxPid) {
            Write-Host "claw wallet sandbox is running."
            exit 0
        }
        Write-Host "claw wallet sandbox is not running."
        exit 1
    }
    "uninstall" {
        Uninstall-Skill
        break
    }
    "serve" {
        if (-not (Test-Path $BinaryPath)) {
            Write-Host "claw wallet sandbox is not installed. Expected binary at: $BinaryPath"
            Write-Host "Run: & `"$ScriptDir\install.ps1`""
            exit 1
        }
        if ($args.Count -gt 1) {
            $forwardArgs = $args[1..($args.Count - 1)]
            & $BinaryPath serve @forwardArgs
        } else {
            & $BinaryPath serve
        }
        exit $LASTEXITCODE
    }
    default {
        if (-not (Test-Path $BinaryPath)) {
            Write-Host "claw wallet sandbox is not installed. Expected binary at: $BinaryPath"
            Write-Host "Run: & `"$ScriptDir\install.ps1`""
            exit 1
        }
        & $BinaryPath @args
        exit $LASTEXITCODE
    }
}
