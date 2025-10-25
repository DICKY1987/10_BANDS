#!/usr/bin/env pwsh
# Update-WTProfile.ps1
# Generates/updates Windows Terminal settings.json with 10_Bands profile

#Requires -Version 5.1

param(
    [string]$Repo = 'C:\Users\Richard Wilks\CLI_RESTART',
    [string]$ProfileName = '10_Bands',
    [switch]$EnablePersistedLayout,
    [switch]$SetAsDefault,
    [switch]$DryRun,
    [switch]$Backup = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR','SUCCESS')]$Level='INFO')
    $colors = @{
        'INFO' = 'Cyan'
        'WARN' = 'Yellow'
        'ERROR' = 'Red'
        'SUCCESS' = 'Green'
    }
    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host "[$Level] $ts $Message" -ForegroundColor $colors[$Level]
}

function Get-WTSettingsPath {
    # Windows Terminal settings.json locations
    $paths = @(
        # Windows Terminal (stable)
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        # Windows Terminal Preview
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
        # Unpackaged (dev builds)
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )

    foreach ($path in $paths) {
        if (Test-Path $path) {
            Write-Log "Found Windows Terminal settings: $path" 'SUCCESS'
            return $path
        }
    }

    throw "Windows Terminal settings.json not found. Checked locations:`n$($paths -join "`n")"
}

function Backup-WTSettings {
    param([string]$SettingsPath)

    $backupDir = Join-Path (Split-Path $SettingsPath) "backups"
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupPath = Join-Path $backupDir "settings_backup_$timestamp.json"

    Copy-Item -LiteralPath $SettingsPath -Destination $backupPath -Force
    Write-Log "Backup created: $backupPath" 'SUCCESS'
    return $backupPath
}

function Build-StartupActions {
    param([string]$Repo)

    # Build the startup actions string matching the current layout
    $repoEscaped = $Repo -replace '\\', '\\'

    $actions = @(
        "new-tab -d `"$repoEscaped`" --title `"Claude`" --suppressApplicationTitle pwsh -NoExit -Command claude",
        "split-pane -V --size 0.5 -d `"$repoEscaped`" --title `"Codex-2`" --suppressApplicationTitle pwsh -NoExit -Command codex",
        "move-focus left",
        # Left column
        "split-pane -H --size 0.2 -d `"$repoEscaped`" --title `"Codex-1`" --suppressApplicationTitle pwsh -NoExit -Command codex",
        "move-focus up",
        "split-pane -H --size 0.25 -d `"$repoEscaped`" --title `"aider-file_mod-1`" --suppressApplicationTitle pwsh -NoExit -Command aider",
        "move-focus up",
        "split-pane -H --size 0.3333333 -d `"$repoEscaped`" --title `"aider-file_mod-2`" --suppressApplicationTitle pwsh -NoExit -Command aider",
        "move-focus up",
        "split-pane -H --size 0.5 -d `"$repoEscaped`" --title `"aider-file_mod-3`" --suppressApplicationTitle pwsh -NoExit -Command aider",
        "move-focus right",
        # Right column
        "split-pane -H --size 0.2 -d `"$repoEscaped`" --title `"Codex-3`" --suppressApplicationTitle pwsh -NoExit -Command codex",
        "move-focus up",
        "split-pane -H --size 0.25 -d `"$repoEscaped`" --title `"aider-error_fix-1`" --suppressApplicationTitle pwsh -NoExit -Command aider",
        "move-focus up",
        "split-pane -H --size 0.3333333 -d `"$repoEscaped`" --title `"aider-error_fix-2`" --suppressApplicationTitle pwsh -NoExit -Command aider",
        "move-focus up",
        "split-pane -H --size 0.5 -d `"$repoEscaped`" --title `"aider-error_fix-3`" --suppressApplicationTitle pwsh -NoExit -Command aider"
    )

    return ($actions -join " ; ")
}

function Update-WTProfile {
    param(
        [string]$SettingsPath,
        [string]$ProfileName,
        [string]$StartupActions,
        [switch]$EnablePersistedLayout,
        [switch]$SetAsDefault
    )

    # Read settings.json
    $settingsContent = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8
    $settings = $settingsContent | ConvertFrom-Json

    function Set-ObjectProperty {
        param(
            [Parameter(Mandatory)]$Object,
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)]$Value
        )
        $prop = $Object.PSObject.Properties[$Name]
        if ($null -eq $prop) {
            $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
        } else {
            $prop.Value = $Value
        }
    }

    # Ensure profiles structure exists (StrictMode-safe)
    $profilesProp = $settings.PSObject.Properties['profiles']
    if ($null -eq $profilesProp) {
        Set-ObjectProperty -Object $settings -Name 'profiles' -Value ([PSCustomObject]@{})
        $profiles = $settings.PSObject.Properties['profiles'].Value
    } else {
        $profiles = $profilesProp.Value
    }

    $listProp = $profiles.PSObject.Properties['list']
    if ($null -eq $listProp) {
        Set-ObjectProperty -Object $profiles -Name 'list' -Value @()
        $profileList = @()
    } else {
        $profileList = [object[]]$listProp.Value
    }

    # Find existing profile
    $existingProfile = $profileList | Where-Object { $_.name -eq $ProfileName }

    if ($existingProfile) {
        Write-Log "Updating existing profile '$ProfileName'..." 'INFO'
        Set-ObjectProperty -Object $existingProfile -Name 'startupActions' -Value $StartupActions
        if ($null -eq $existingProfile.PSObject.Properties['icon']) {
            $existingProfile | Add-Member -NotePropertyName 'icon' -NotePropertyValue 'ms-appx:///ProfileIcons/{61c54bbd-c2c6-5271-96e7-009a87ff44bf}.png' -Force
        }
    } else {
        Write-Log "Creating new profile '$ProfileName'..." 'INFO'
        $newProfile = [PSCustomObject]@{
            name = $ProfileName
            startupActions = $StartupActions
            icon = 'ms-appx:///ProfileIcons/{61c54bbd-c2c6-5271-96e7-009a87ff44bf}.png'
            hidden = $false
        }

        # Append to list and write back
        $arr = @($profileList) + @($newProfile)
        Set-ObjectProperty -Object $profiles -Name 'list' -Value $arr
    }

    # Set global settings
    if ($EnablePersistedLayout) {
        Write-Log "Enabling persisted window layout..." 'INFO'
        Set-ObjectProperty -Object $settings -Name 'firstWindowPreference' -Value 'persistedWindowLayout'
    }

    if ($SetAsDefault) {
        Write-Log "Setting '$ProfileName' as default profile..." 'INFO'
        Set-ObjectProperty -Object $settings -Name 'defaultProfile' -Value $ProfileName
    }

    # Set fullscreen launch mode if not already set
    if ($null -eq $settings.PSObject.Properties['launchMode']) {
        Set-ObjectProperty -Object $settings -Name 'launchMode' -Value 'fullscreen'
        Write-Log "Set launchMode to fullscreen" 'INFO'
    }

    return $settings
}

function Test-JsonValid {
    param([string]$Json)

    try {
        $null = $Json | ConvertFrom-Json
        return $true
    } catch {
        Write-Log "JSON validation failed: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

# Allow tests to import functions without executing the script
if ($env:WT_PROFILE_IMPORT -eq '1') { return }

# Main execution
try {
    Write-Log "=== Windows Terminal Profile Updater ===" 'INFO'
    Write-Log "Profile: $ProfileName | Repo: $Repo" 'INFO'

    # Locate settings.json
    $settingsPath = Get-WTSettingsPath

    # Backup settings
    if ($Backup -and -not $DryRun) {
        $backupPath = Backup-WTSettings -SettingsPath $settingsPath
    }

    # Build startup actions
    Write-Log "Building startup actions for 10-pane layout..." 'INFO'
    $startupActions = Build-StartupActions -Repo $Repo
    Write-Log "Startup actions string length: $($startupActions.Length) chars" 'INFO'

    # Update profile
    $updatedSettings = Update-WTProfile `
        -SettingsPath $settingsPath `
        -ProfileName $ProfileName `
        -StartupActions $startupActions `
        -EnablePersistedLayout:$EnablePersistedLayout `
        -SetAsDefault:$SetAsDefault

    # Convert to JSON with proper formatting
    $jsonOutput = $updatedSettings | ConvertTo-Json -Depth 10 -Compress:$false

    # Validate JSON
    if (-not (Test-JsonValid -Json $jsonOutput)) {
        throw "Generated JSON is invalid. Settings not updated."
    }

    if ($DryRun) {
        Write-Log "=== DRY RUN MODE ===" 'WARN'
        Write-Log "Would update: $settingsPath" 'INFO'
        Write-Log "`nProfile startup actions:" 'INFO'
        Write-Host $startupActions -ForegroundColor Gray

        $outputPath = Join-Path $PSScriptRoot "settings_preview.json"
        $jsonOutput | Set-Content -LiteralPath $outputPath -Encoding UTF8
        Write-Log "`nFull preview saved to: $outputPath" 'INFO'
    } else {
        # Write updated settings
        $jsonOutput | Set-Content -LiteralPath $settingsPath -Encoding UTF8
        Write-Log "Settings updated successfully!" 'SUCCESS'
        Write-Log "Backup available at: $backupPath" 'INFO'
    }

    Write-Log "`n=== Next Steps ===" 'SUCCESS'
    Write-Log "Launch with: wt --profile `"$ProfileName`" --fullscreen" 'INFO'
    Write-Log "Or simply: wt -p `"$ProfileName`"" 'INFO'

    if ($SetAsDefault) {
        Write-Log "Profile set as default - just run: wt" 'INFO'
    }

    exit 0

} catch {
    Write-Log "Failed to update Windows Terminal profile: $($_.Exception.Message)" 'ERROR'
    Write-Log "Stack trace: $($_.ScriptStackTrace)" 'ERROR'
    exit 1
}
