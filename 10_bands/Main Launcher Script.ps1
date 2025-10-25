# AutomationSuite/Scripts/Start-CliTools.ps1
# Main script to launch CLI tools as background jobs and start the monitor window.

#Requires -Version 5.1
#Requires -Module ..\AutomationSuite.psm1 # Assuming relative path for simplicity

<#
.SYNOPSIS
    Launches multiple CLI tools defined in a configuration file as background jobs
    and opens a separate PowerShell window to monitor their combined output in real-time.
.DESCRIPTION
    1. Imports the core AutomationSuite module.
    2. Loads the tool configuration from CliToolsConfig.psd1.
    3. Iterates through the tools, starting each as a PowerShell background job using Start-AutomationCliJob.
    4. Collects the IDs of the started jobs.
    5. Launches the Show-CliOutput.ps1 script in a new PowerShell window, passing the job IDs.
.NOTES
    Ensure the AutomationSuite module is available in the module path or via relative path.
    Ensure CliToolsConfig.psd1 is in the expected location relative to this script.
#>

[CmdletBinding()]
param()

# --- Configuration ---
$ConfigPath = Join-Path $PSScriptRoot "..\Config\CliToolsConfig.psd1"
$MonitorScriptPath = Join-Path $PSScriptRoot "Show-CliOutput.ps1"
$CorrelationId = [Guid]::NewGuid().ToString("N").Substring(0, 8) # Unique ID for this run

# Set CorrelationId as a script variable for logging
$ExecutionContext.SessionState.PSVariable.Set('CorrelationId', $CorrelationId)

# --- Initialization ---
try {
    Write-AutomationLog -Level Info -Message "Starting CLI Tool Launcher" -Data @{ ConfigPath = $ConfigPath; MonitorScript = $MonitorScriptPath }

    # Load configuration
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found at '$ConfigPath'"
    }
    $Config = Import-PowerShellDataFile -Path $ConfigPath
    Write-AutomationLog -Level Debug -Message "Configuration loaded successfully." -Data @{ ToolCount = $Config.Tools.Count }

    # Check if monitor script exists
     if (-not (Test-Path $MonitorScriptPath)) {
        throw "Monitor script file not found at '$MonitorScriptPath'"
    }

}
catch {
    Write-AutomationLog -Level Critical -Message "Initialization failed." -Exception $_
    Exit 1 # Use standardized exit codes if available via module
}

# --- Start Background Jobs ---
$jobIds = [System.Collections.Generic.List[int]]::new()
$jobNames = [System.Collections.Generic.List[string]]::new()

Write-AutomationLog -Level Info -Message "Starting background jobs..."
foreach ($tool in $Config.Tools) {
    try {
        Write-AutomationLog -Level Debug -Message "Attempting to start job for $($tool.Name)"
        $job = Start-AutomationCliJob -ToolConfig $tool
        if ($job) {
            $jobIds.Add($job.Id)
            $jobNames.Add($job.Name)
            Write-AutomationLog -Level Info -Message "Job started for $($tool.Name)" -Data @{ JobId = $job.Id; State = $job.State }
        } else {
             Write-AutomationLog -Level Warning -Message "Job object was null for $($tool.Name)"
        }
    }
    catch {
        # Log the error but continue trying to start other jobs
        Write-AutomationLog -Level Error -Message "Failed to start job for tool: $($tool.Name)" -Exception $_
        # Consider adding the failed tool name to a list to report at the end
    }
}

if ($jobIds.Count -eq 0) {
    Write-AutomationLog -Level Critical -Message "No jobs were started successfully. Exiting."
    Exit 1 # Use standardized exit codes
}

Write-AutomationLog -Level Info -Message "Finished starting jobs." -Data @{ StartedCount = $jobIds.Count; JobIds = $jobIds -join ', ' }

# --- Launch Monitor Window ---
Write-AutomationLog -Level Info -Message "Launching monitor window..."
try {
    # Prepare arguments for the monitor script: comma-separated list of Job IDs
    $monitorArgs = "-NoExit", "-File", "`"$MonitorScriptPath`"", "-JobIds", ($jobIds -join ',')

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = "powershell.exe"
    $startInfo.Arguments = $monitorArgs -join ' '
    # $startInfo.WindowStyle = 'Normal' # Default is normal
    # $startInfo.CreateNoWindow = $false # Default is false

    Write-AutomationLog -Level Debug -Message "Monitor process arguments: $($startInfo.Arguments)"

    $process = [System.Diagnostics.Process]::Start($startInfo)

    if ($process) {
        Write-AutomationLog -Level Info -Message "Monitor window launched successfully." -Data @{ ProcessId = $process.Id }
    } else {
         throw "Failed to start the monitor process."
    }
}
catch {
    Write-AutomationLog -Level Critical -Message "Failed to launch monitor window." -Exception $_
    # Optional: Stop started jobs?
    # Get-Job -Id $jobIds | Stop-Job -Force
    Exit 1 # Use standardized exit codes
}

Write-AutomationLog -Level Info -Message "Launcher script finished. Monitor window is running."

# --- Optional: Wait for Jobs (Uncomment if needed) ---
# Write-AutomationLog -Level Info -Message "Waiting for background jobs to complete (optional)..."
# Get-Job -Id $jobIds | Wait-Job | Out-Null
# Write-AutomationLog -Level Info -Message "All background jobs have completed."
# Get-Job -Id $jobIds | Receive-Job # To get final output if not monitored live
