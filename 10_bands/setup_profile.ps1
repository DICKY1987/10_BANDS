#!/usr/bin/env pwsh
# setup_profile.ps1
# One-time setup: Creates Windows Terminal profile and optional desktop shortcut

#Requires -Version 5.1

param(
    [string]$ProfileName = '10_Bands',
    [string]$Repo = 'C:\Users\Richard Wilks\CLI_RESTART',
    [switch]$EnablePersistedLayout,
    [switch]$SetAsDefault,
    [switch]$CreateShortcut,
    [switch]$LaunchAfterSetup,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR','SUCCESS')]$Level='INFO')
    $colors = @{ 'INFO' = 'Cyan'; 'WARN' = 'Yellow'; 'ERROR' = 'Red'; 'SUCCESS' = 'Green' }
    Write-Host "[$Level] $Message" -ForegroundColor $colors[$Level]
}

function New-DesktopShortcut {
    param([string]$Name, [string]$ProfileName)

    $desktop = [Environment]::GetFolderPath('Desktop')
    $lnkPath = Join-Path $desktop "$Name.lnk"

    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($lnkPath)

    # Launch with wt command
    $shortcut.TargetPath = 'wt.exe'
    $shortcut.Arguments = "-p `"$ProfileName`" --fullscreen"
    $shortcut.WorkingDirectory = $Repo
    $shortcut.IconLocation = 'wt.exe,0'
    $shortcut.Description = "Launch 10-pane AI development environment"
    $shortcut.WindowStyle = 1  # Normal window

    $shortcut.Save()
    Write-Log "Desktop shortcut created: $lnkPath" 'SUCCESS'
}

function Test-ToolAvailability {
    $tools = @{
        'wt' = 'Windows Terminal'
        'claude' = 'Claude CLI'
        'codex' = 'Codex CLI'
        'aider' = 'Aider'
        'pwsh' = 'PowerShell 7+'
    }

    $missing = @()
    $found = @()

    foreach ($tool in $tools.Keys) {
        if (Get-Command $tool -ErrorAction SilentlyContinue) {
            $found += "$tool ($($tools[$tool]))"
        } else {
            $missing += "$tool ($($tools[$tool]))"
        }
    }

    if ($found.Count -gt 0) {
        Write-Log "Tools found: $($found -join ', ')" 'SUCCESS'
    }

    if ($missing.Count -gt 0) {
        Write-Log "Tools missing: $($missing -join ', ')" 'WARN'
        Write-Log "Layout will still be created, but missing tools won't function" 'WARN'
    }
}

# Main execution
try {
    Write-Log "=== 10_Bands Profile Setup ===" 'INFO'
    Write-Log "Profile Name: $ProfileName" 'INFO'
    Write-Log "Repository: $Repo" 'INFO'

    if ($DryRun) {
        Write-Log "DRY RUN MODE - No changes will be made" 'WARN'
    }

    # Check tool availability
    Write-Log "`nChecking tool availability..." 'INFO'
    Test-ToolAvailability

    # Run profile updater
    Write-Log "`nUpdating Windows Terminal profile..." 'INFO'
    $updateScript = Join-Path $PSScriptRoot 'Modules\Update-WTProfile.ps1'

    if (-not (Test-Path $updateScript)) {
        throw "Update script not found: $updateScript"
    }

    $updateArgs = @{
        ProfileName = $ProfileName
        Repo = $Repo
        DryRun = $DryRun
    }

    if ($EnablePersistedLayout) {
        $updateArgs['EnablePersistedLayout'] = $true
        Write-Log "Persisted window layout will be enabled" 'INFO'
    }

    if ($SetAsDefault) {
        $updateArgs['SetAsDefault'] = $true
        Write-Log "Profile will be set as default" 'INFO'
    }

    & $updateScript @updateArgs

    if ($LASTEXITCODE -ne 0) {
        throw "Profile update failed with exit code $LASTEXITCODE"
    }

    # Create desktop shortcut
    if ($CreateShortcut -and -not $DryRun) {
        Write-Log "`nCreating desktop shortcut..." 'INFO'
        New-DesktopShortcut -Name $ProfileName -ProfileName $ProfileName
    }

    # Launch if requested
    if ($LaunchAfterSetup -and -not $DryRun) {
        Write-Log "`nLaunching 10_Bands layout..." 'INFO'
        Start-Sleep -Seconds 2  # Give user time to see setup results

        & wt -p $ProfileName --fullscreen
        Write-Log "Layout launched!" 'SUCCESS'
    }

    Write-Log "`n=== Setup Complete! ===" 'SUCCESS'
    Write-Log "`nQuick Launch Options:" 'INFO'
    Write-Log "  1. Run: wt -p `"$ProfileName`" --fullscreen" 'INFO'
    Write-Log "  2. Run: .\launch_10_bands_profile.ps1" 'INFO'

    if ($CreateShortcut) {
        Write-Log "  3. Double-click desktop shortcut: $ProfileName" 'INFO'
    }

    if ($SetAsDefault) {
        Write-Log "  4. Just run: wt (set as default profile)" 'INFO'
    }

    Write-Log "`nTo update profile in future: .\setup_profile.ps1" 'INFO'

    exit 0

} catch {
    Write-Log "Setup failed: $($_.Exception.Message)" 'ERROR'
    exit 1
}
