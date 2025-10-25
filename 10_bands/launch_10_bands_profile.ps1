#!/usr/bin/env pwsh
# launch_10_bands_profile.ps1
# Simplified launcher using Windows Terminal profile

#Requires -Version 5.1

<#
.SYNOPSIS
Launch the 10_Bands Windows Terminal profile.

.PARAMETER ProfileName
Profile to launch (default: 10_Bands).

.PARAMETER Fullscreen
Launch in fullscreen (default: $true).

.PARAMETER UpdateProfile
If set, updates/creates the Windows Terminal profile before launching.

.PARAMETER UseExistingWindow
If set, targets the last existing WT window (-w last).
#>

param(
    [string]$ProfileName = '10_Bands',
    [switch]$Fullscreen = $true,
    [switch]$UpdateProfile,
    [switch]$UseExistingWindow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR','SUCCESS')]$Level='INFO')
    $colors = @{ 'INFO' = 'Cyan'; 'WARN' = 'Yellow'; 'ERROR' = 'Red'; 'SUCCESS' = 'Green' }
    Write-Host "[$Level] $Message" -ForegroundColor $colors[$Level]
}

try {
    # Check if wt is available
    $wt = Get-Command wt -ErrorAction SilentlyContinue
    if (-not $wt) {
        throw "Windows Terminal 'wt' not found. Install from Microsoft Store or winget."
    }

    # Update profile if requested
    if ($UpdateProfile) {
        Write-Log "Updating Windows Terminal profile..." 'INFO'
        $updateScript = Join-Path $PSScriptRoot 'Modules\Update-WTProfile.ps1'

        if (-not (Test-Path $updateScript)) {
            throw "Profile updater not found: $updateScript"
        }

        & $updateScript -ProfileName $ProfileName
        if ($LASTEXITCODE -ne 0) {
            throw "Profile update failed with exit code $LASTEXITCODE"
        }
        Write-Log "Profile updated successfully!" 'SUCCESS'
    }

    # Build launch arguments
    $wtArgs = @('-p', $ProfileName)

    if ($Fullscreen) {
        $wtArgs += '--fullscreen'
    }

    if ($UseExistingWindow) {
        $wtArgs += @('-w', 'last')
    }

    Write-Log "Launching Windows Terminal with profile '$ProfileName'..." 'INFO'
    Write-Log "Command: wt $($wtArgs -join ' ')" 'INFO'

    # Launch Windows Terminal with profile
    & wt @wtArgs

    Write-Log "10_Bands layout launched!" 'SUCCESS'
    exit 0

} catch {
    Write-Log "Failed to launch: $($_.Exception.Message)" 'ERROR'
    Write-Log "Troubleshooting:" 'WARN'
    Write-Log "  1. Ensure Windows Terminal is installed" 'WARN'
    Write-Log "  2. Run with -UpdateProfile to create/update the profile" 'WARN'
    Write-Log "  3. Check that tools (claude, codex, aider) are on PATH" 'WARN'
    exit 1
}
