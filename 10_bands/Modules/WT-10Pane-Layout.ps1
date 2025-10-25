#!/usr/bin/env pwsh
# WT-10Pane-Layout.ps1
# Launches a precise 2x5 WT layout in repo root, fullscreen-capable, with logging and rich errors.

param(
    [string]$Repo = 'C:\Users\Richard Wilks\CLI_RESTART',
    [switch]$UseExistingWindow,
    [switch]$Fullscreen,
    [switch]$CreateShortcut
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message,[ValidateSet('INFO','WARN','ERROR')]$Level='INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $line = "[$Level] $ts $Message"
    Write-Host $line
    if ($script:LogFile) { try { Add-Content -LiteralPath $script:LogFile -Value $line } catch {} }
}

function Test-Tool {
    param([Parameter(Mandatory)][string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) { Write-Log "Tool not found on PATH: '$Name'. Install or add to PATH." 'WARN' }
    return $cmd -ne $null
}

function Build-WtArgs {
    param([string]$Repo,[switch]$UseExistingWindow,[switch]$Fullscreen)

    $args = @()
    if ($Fullscreen) { $args += @('--fullscreen') } else { $args += @('--maximized') }
    if ($UseExistingWindow) { $args += @('-w','last') }
    # Quote -d path to survive spaces (Start-Process joins without auto-quoting tokens)
    $quotedRepo = '"' + $Repo + '"'
    $args += @('-d', $quotedRepo)

    # Equal columns
    $args += @(
        'new-tab','-d',$quotedRepo,'--title','Claude','--suppressApplicationTitle','pwsh','-NoExit','-Command','claude',';',
        'split-pane','-V','--size','0.5','-d',$quotedRepo,'--title','Codex-2','--suppressApplicationTitle','pwsh','-NoExit','-Command','codex',';',
        'move-focus','left',';'
    )

    # Left column: 5 equal rows by repeated fractional splits of the remainder
    $args += @(
        'split-pane','-H','--size','0.2','-d',$quotedRepo,'--title','Codex-1','--suppressApplicationTitle','pwsh','-NoExit','-Command','codex',';', 'move-focus','up',';',
        'split-pane','-H','--size','0.25','-d',$quotedRepo,'--title','aider-file_mod-1','--suppressApplicationTitle','pwsh','-NoExit','-Command','aider',';', 'move-focus','up',';',
        'split-pane','-H','--size','0.3333333','-d',$quotedRepo,'--title','aider-file_mod-2','--suppressApplicationTitle','pwsh','-NoExit','-Command','aider',';', 'move-focus','up',';',
        'split-pane','-H','--size','0.5','-d',$quotedRepo,'--title','aider-file_mod-3','--suppressApplicationTitle','pwsh','-NoExit','-Command','aider',';', 'move-focus','right',';'
    )

    # Right column: mirror equal rows
    $args += @(
        'split-pane','-H','--size','0.2','-d',$quotedRepo,'--title','Codex-3','--suppressApplicationTitle','pwsh','-NoExit','-Command','codex',';', 'move-focus','up',';',
        'split-pane','-H','--size','0.25','-d',$quotedRepo,'--title','aider-error_fix-1','--suppressApplicationTitle','pwsh','-NoExit','-Command','aider',';', 'move-focus','up',';',
        'split-pane','-H','--size','0.3333333','-d',$quotedRepo,'--title','aider-error_fix-2','--suppressApplicationTitle','pwsh','-NoExit','-Command','aider',';', 'move-focus','up',';',
        'split-pane','-H','--size','0.5','-d',$quotedRepo,'--title','aider-error_fix-3','--suppressApplicationTitle','pwsh','-NoExit','-Command','aider'
    )
    return ,$args
}

function New-DesktopShortcut {
    param([string]$Name,[string]$Target,[string]$Arguments,[string]$WorkingDirectory)
    $desktop = [Environment]::GetFolderPath('Desktop')
    $lnk = Join-Path $desktop "$Name.lnk"
    $wsh = New-Object -ComObject WScript.Shell
    $sc = $wsh.CreateShortcut($lnk)
    $sc.TargetPath = $Target
    $sc.Arguments = $Arguments
    $sc.WorkingDirectory = $WorkingDirectory
    $sc.IconLocation = 'wt.exe,0'
    $sc.WindowStyle = 1
    $sc.Save()
    Write-Log "Created desktop shortcut: $lnk"
}

# Allow tests to import functions without executing the launcher.
if ($env:WT_LAYOUT_IMPORT -eq '1') { return }

try {
    if (-not (Test-Path -LiteralPath $Repo)) {
        throw "Project root not found: '$Repo'. Ensure the path exists and you have access."
    }

    $logDir = 'C:\\Automation\\Logs'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $script:LogFile = Join-Path $logDir ("WT-10Pane-Layout-" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".log")
    Write-Log "WT layout starting. Repo='$Repo' Fullscreen=$Fullscreen UseExistingWindow=$UseExistingWindow"

    $wt = Get-Command wt -ErrorAction SilentlyContinue
    if (-not $wt) {
        throw "Windows Terminal executable 'wt' not found on PATH. Install Windows Terminal and ensure 'wt.exe' is accessible."
    }

    # Tool presence diagnostics
    $hasClaude = Test-Tool -Name 'claude'
    $hasCodex  = Test-Tool -Name 'codex'
    $hasAider  = Test-Tool -Name 'aider'
    if (-not $hasCodex) { Write-Log "Codex is missing. Install via npm/yarn (command 'codex') or adjust command name." 'WARN' }

    $wtArgs = Build-WtArgs -Repo $Repo -UseExistingWindow:$UseExistingWindow -Fullscreen:$Fullscreen
    Write-Log ("WT args: " + ($wtArgs -join ' '))

    try {
        Start-Process -FilePath 'wt' -ArgumentList $wtArgs | Out-Null
        if ($Fullscreen) {
            try {
                Start-Sleep -Milliseconds 500
                Start-Process -FilePath 'wt' -ArgumentList @('-w','last','action','toggleFullscreen') | Out-Null
            } catch { Write-Log "Fullscreen toggle fallback failed (older WT?). Continuing." 'WARN' }
        }
        Write-Log "Launched 10-pane layout. If not fullscreen, your WT version may not support --fullscreen; attempted action toggle as fallback."
    } catch {
        $hint = 'If pane sizes are uneven, ensure your Windows Terminal version supports split-pane --size and move-focus; also check profile names.'
        throw "Failed to start Windows Terminal. Details: $($_.Exception.Message). Hint: $hint"
    }

    if ($CreateShortcut) {
        $ps = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
        if (-not $ps) { $ps = (Get-Command powershell -ErrorAction SilentlyContinue).Source }
        New-DesktopShortcut -Name '10_BANDS' -Target $ps -Arguments "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Fullscreen" -WorkingDirectory $Repo
    }

    Write-Output "Launched 10-pane layout in $Repo"
}
catch {
    $msg = @()
    $msg += "Unable to launch 10-pane layout."
    $msg += "Reason: $($_.Exception.Message)"
    $msg += "Context: Repo='$Repo', UseExistingWindow=$UseExistingWindow, Fullscreen=$Fullscreen"
    $msg += "Checks: wt=$(if(Get-Command wt -ErrorAction SilentlyContinue){'ok'}else{'missing'}), claude=$(if(Get-Command claude -ErrorAction SilentlyContinue){'ok'}else{'missing'}), codex=$(if(Get-Command codex -ErrorAction SilentlyContinue){'ok'}else{'missing'}), aider=$(if(Get-Command aider -ErrorAction SilentlyContinue){'ok'}else{'missing'})"
    $msg += "Remediation: Install/upgrade Windows Terminal, ensure tools on PATH, and run with -Fullscreen for full-screen or update WT (>=1.17)."
    $full = ($msg -join ' ')
    Write-Log $full 'ERROR'
    throw $full
}
