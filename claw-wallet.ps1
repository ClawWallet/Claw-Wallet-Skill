$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BinaryPath = Join-Path $ScriptDir "clay-sandbox.exe"
$LogPath = Join-Path $ScriptDir "sandbox.log"
$ErrLogPath = Join-Path $ScriptDir "sandbox_err.log"
$PidPath = Join-Path $ScriptDir "sandbox.pid"
$SkillBranch = if ($env:CLAW_WALLET_SKILL_BRANCH) { $env:CLAW_WALLET_SKILL_BRANCH } else { "dev" }

# upgrade runs before binary check (remote install script + binary, no git)
if ($args.Count -gt 0 -and $args[0] -eq "upgrade") {
    Set-Location $ScriptDir
    if (Test-Path $BinaryPath) {
        & $BinaryPath stop 2>$null
    }
    Remove-Item $PidPath -ErrorAction SilentlyContinue
    $BaseUrl = if ($env:CLAW_WALLET_BASE_URL) { $env:CLAW_WALLET_BASE_URL } else { "https://test.clawwallet.cc" }
    Write-Host "Upgrading from $BaseUrl/install.ps1 ..."
    $env:CLAW_WALLET_SKIP_INIT = "1"
    $env:CLAW_WALLET_INSTALL_DIR = $ScriptDir
    $installPs1 = Join-Path $env:TEMP "claw-wallet-install-$(Get-Random).ps1"
    try {
        Invoke-WebRequest -Uri "$BaseUrl/install.ps1" -OutFile $installPs1 -UseBasicParsing
        & $installPs1
    } finally {
        Remove-Item $installPs1 -ErrorAction SilentlyContinue
        Remove-Item Env:\CLAW_WALLET_INSTALL_DIR -ErrorAction SilentlyContinue
    }
    exit $LASTEXITCODE
}

# uninstall runs before binary check
if ($args.Count -gt 0 -and $args[0] -eq "uninstall") {
    Set-Location $ScriptDir
    if (Test-Path $BinaryPath) {
        & $BinaryPath stop 2>$null
    }
    Remove-Item $PidPath -ErrorAction SilentlyContinue
    Write-Host ""
    Write-Host "=== WARNING: Uninstall claw-wallet skill ==="
    Write-Host "This will DELETE the entire skill directory and all wallet data."
    Write-Host "Files to be removed: .env.clay, identity.json, share3.json, and all others."
    Write-Host "This action is IRREVERSIBLE. Please backup .env.clay, identity.json, share3.json first if needed."
    Write-Host ""
    $confirm = Read-Host "Type 'yes' to confirm uninstall"
    if ($confirm -ne "yes") {
        Write-Host "Uninstall cancelled."
        exit 0
    }
    Write-Host "Removing $ScriptDir ..."
    $ParentDir = Split-Path -Parent $ScriptDir
    Set-Location $ParentDir
    Remove-Item -Path $ScriptDir -Recurse -Force
    Write-Host "claw-wallet skill has been uninstalled."
    exit 0
}

if (!(Test-Path $BinaryPath)) {
    Write-Host "claw wallet sandbox is not installed. Expected binary at: $BinaryPath"
    Write-Host "Run: & `"$ScriptDir\install.ps1`""
    exit 1
}

function Get-RunningSandboxPid {
    if (!(Test-Path $PidPath)) {
        return $null
    }
    $pidValue = (Get-Content $PidPath -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    if ([string]::IsNullOrWhiteSpace($pidValue)) {
        return $null
    }
    $proc = Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue
    if ($null -ne $proc) {
        return $proc.Id
    }
    Remove-Item $PidPath -ErrorAction SilentlyContinue
    return $null
}

function Start-Sandbox {
    $runningPid = Get-RunningSandboxPid
    if ($null -ne $runningPid) {
        Write-Host "claw wallet sandbox is already running."
        Write-Host "PID file: $PidPath"
        Write-Host "Log files: $LogPath , $ErrLogPath"
        return
    }

    $proc = Start-Process `
        -FilePath $BinaryPath `
        -ArgumentList "serve" `
        -WorkingDirectory $ScriptDir `
        -WindowStyle Hidden `
        -RedirectStandardOutput $LogPath `
        -RedirectStandardError $ErrLogPath `
        -PassThru
    Set-Content -Path $PidPath -Value $proc.Id
    Write-Host "claw wallet sandbox launched in the background."
    Write-Host "PID file: $PidPath"
    Write-Host "Log files: $LogPath , $ErrLogPath"
    $envClay = Join-Path $ScriptDir ".env.clay"
    if (Test-Path $envClay) {
        Write-Host "API auth: if HTTP returns 401, send header Authorization: Bearer <token> using AGENT_TOKEN or CLAY_AGENT_TOKEN from .env.clay (or agent_token in identity.json). See SKILL.md."
    }
}

function Stop-Sandbox {
    Set-Location $ScriptDir
    & $BinaryPath stop | Out-Null
    Remove-Item $PidPath -ErrorAction SilentlyContinue
    Write-Host "claw wallet sandbox stop requested."
}

if ($args.Count -eq 0 -or $args[0] -eq "start") {
    Start-Sandbox
    exit 0
}

if ($args[0] -eq "restart") {
    Stop-Sandbox
    Start-Sleep -Seconds 1
    Start-Sandbox
    exit 0
}

if ($args[0] -eq "stop") {
    Stop-Sandbox
    exit 0
}

if ($args[0] -eq "is-running") {
    $runningPid = Get-RunningSandboxPid
    if ($null -ne $runningPid) {
        Write-Host "claw wallet sandbox is running."
        exit 0
    }
    else {
        Write-Host "claw wallet sandbox is not running."
        exit 1
    }
}

if ($args[0] -eq "serve") {
    Set-Location $ScriptDir
    if ($args.Count -gt 1) {
        & $BinaryPath @args
    }
    else {
        & $BinaryPath serve
    }
    exit $LASTEXITCODE
}

Set-Location $ScriptDir
& $BinaryPath @args
