# AutomationSuite/Scripts/Show-CliOutput.ps1
# Monitors output from background jobs and displays it in this console window with color-coding.

#Requires -Version 5.1
#Requires -Module ..\AutomationSuite.psm1 # Assuming relative path

<#
.SYNOPSIS
    Monitors specified PowerShell background jobs for output in real-time
    and displays each line color-coded based on the source job (tool).
.DESCRIPTION
    1. Takes a comma-separated string of Job IDs as input.
    2. Imports the core AutomationSuite module.
    3. Loads tool configuration (for color mapping).
    4. Retrieves the corresponding Job objects using Get-Job.
    5. Enters a loop, continuously checking each job for new output using Receive-Job.
    6. Parses each output line to identify the source tool.
    7. Uses Get-ToolColor to determine the appropriate color.
    8. Displays the line using Write-Host with the determined color.
    9. Exits when all monitored jobs are completed or failed and have no more output.
.PARAMETER JobIds
    A comma-separated string containing the IDs of the PowerShell Jobs to monitor.
.NOTES
    This script is intended to be launched in a separate PowerShell window, typically
    by the Start-CliTools.ps1 script.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$JobIds # Comma-separated list of job IDs passed as a string
)

# --- Configuration ---
$ConfigPath = Join-Path $PSScriptRoot "..\Config\CliToolsConfig.psd1"
$CorrelationId = [Guid G;].ToString("N").Substring(0, 8) # Unique ID for this monitor session

# Set CorrelationId for logging within this script
$ExecutionContext.SessionState.PSVariable.Set('CorrelationId', $CorrelationId)

# --- Initialization ---
try {
    Write-AutomationLog -Level Info -Message "Starting Output Monitor" -Data @{ InputJobIds = $JobIds; ConfigPath = $ConfigPath }

    # Load configuration for color mapping
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found at '$ConfigPath'"
    }
    $Config = Import-PowerShellDataFile -Path $ConfigPath
    Write-AutomationLog -Level Debug -Message "Monitor configuration loaded."

    # Parse Job IDs
    $targetJobIds = $JobIds -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object { [int]$_ }
    if ($targetJobIds.Count -eq 0) {
        throw "No valid Job IDs provided."
    }
    Write-AutomationLog -Level Debug -Message "Parsed target Job IDs." -Data @{ JobIds = $targetJobIds }

    # Get Job Objects
    $jobsToMonitor = Get-Job -Id $targetJobIds -ErrorAction Stop
    if ($jobsToMonitor.Count -ne $targetJobIds.Count) {
        Write-AutomationLog -Level Warning -Message "Could not find all specified jobs." -Data @{ Found = $jobsToMonitor.Count; Requested = $targetJobIds.Count }
        if ($jobsToMonitor.Count -eq 0) {
            throw "Found none of the specified jobs to monitor."
        }
    }
    Write-AutomationLog -Level Info -Message "Retrieved Job objects to monitor." -Data @{ JobCount = $jobsToMonitor.Count; JobNames = $jobsToMonitor.Name -join ', ' }

    # Create Color Map from Config
    $colorMap = @{}
    foreach ($tool in $Config.Tools) {
        $colorMap[$tool.Name] = $tool.Color
    }
    $defaultColor = [System.ConsoleColor]($Config.DefaultOutputColor)
    Write-AutomationLog -Level Debug -Message "Color map created." -Data @{ MapSize = $colorMap.Count; Default = $defaultColor }


    # Set console title
    $Host.UI.RawUI.WindowTitle = "Monitoring Output - $($jobsToMonitor.Name -join ', ')"
    Write-Host "--- Monitoring Live Output ($($jobsToMonitor.Count) Tools) ---" -ForegroundColor Cyan
    Write-Host "--- Press Ctrl+C to stop monitoring ---" -ForegroundColor Yellow

}
catch {
    Write-AutomationLog -Level Critical -Message "Monitor initialization failed." -Exception $_
    Read-Host "Monitor failed to initialize. Press Enter to exit."
    Exit 1 # Use standardized exit codes
}


# --- Monitoring Loop ---
try {
    $monitorRefreshRateMs = $Config.MonitorRefreshRateMs

    # Loop while any job is running OR any job still has output data
    while ( ($jobsToMonitor.State -contains 'Running') -or ($jobsToMonitor.HasMoreData -contains $true) ) {

        foreach ($job in $jobsToMonitor) {
            # Check for new data without blocking if none exists (Receive-Job returns $null quickly)
            # Use a loop here in case a lot of data arrived between sleeps
            while ($job.HasMoreData) {
                 $outputLines = Receive-Job -Job $job -ErrorAction SilentlyContinue #-Keep # Keep makes it slower if output is huge

                 if ($outputLines -ne $null) {
                     # Ensure outputLines is always an array
                     if ($outputLines -isnot [array]) { $outputLines = @($outputLines) }

                     foreach ($line in $outputLines) {
                        # Expected format: "ToolName: Actual output line"
                        $lineString = $line.ToString() # Handle different output types

                        # Match the pattern "ToolName: " at the start
                        if ($lineString -match '^([^:]+):\s*(.*)$') {
                            $toolName = $matches[1].Trim()
                            $message = $matches[2] # Keep remaining whitespace
                            $color = Get-ToolColor -ToolName $toolName -ColorMap $colorMap -DefaultColor $defaultColor
                        } else {
                            # Line doesn't match the expected format, print with default color
                            $toolName = "UNKNOWN"
                            $message = $lineString
                            $color = $defaultColor
                            Write-AutomationLog -Level Debug -Message "Received output line without expected 'ToolName:' prefix." -Data @{ Line = $lineString; JobName = $job.Name }
                        }

                        # Display the colored output
                        Write-Host $lineString -ForegroundColor $color
                    }
                 } elseif ($job.JobStateInfo.Reason -ne $null) {
                     # Log if Receive-Job failed for a reason
                     Write-AutomationLog -Level Warning -Message "Error receiving job data for $($job.Name)." -Data @{ JobState = $job.State; Reason = $job.JobStateInfo.Reason.Message }
                     # Avoid tight loop on error
                     Start-Sleep -Milliseconds 100
                 }
            } # End while $job.HasMoreData
        } # End foreach job

        # Short sleep to prevent high CPU usage
        Start-Sleep -Milliseconds $monitorRefreshRateMs

        # Update the list of jobs to monitor (filter out completed ones *that have no more data*)
        $jobsToMonitor = $jobsToMonitor | Where-Object { $_.State -eq 'Running' -or $_.HasMoreData }

    } # End while running or has data

    Write-AutomationLog -Level Info -Message "All monitored jobs have finished and output has been received."

    # Final check for any remaining data (less likely with the loop condition but good practice)
    foreach ($job in (Get-Job -Id $targetJobIds)) {
         if ($job.HasMoreData) {
             Write-AutomationLog -Level Debug -Message "Receiving final output chunk for $($job.Name)"
             Receive-Job -Job $job | ForEach-Object { Write-Host $_.ToString() -ForegroundColor $defaultColor }
         }
    }

}
catch {
    # Catch errors during the monitoring loop itself
    Write-AutomationLog -Level Critical -Message "An error occurred during output monitoring." -Exception $_
}
finally {
    # --- Cleanup and Exit ---
    Write-Host "--- Monitoring Complete ---" -ForegroundColor Cyan
    $finalJobStates = Get-Job -Id $targetJobIds | Select-Object Name, Id, State, PSBeginTime, PSEndTime
    Write-AutomationLog -Level Info -Message "Final Job States:" -Data @{ JobStates = ($finalJobStates | ConvertTo-Json -Compress) }
    Write-Host "Final Job States:"
    $finalJobStates | Format-Table -AutoSize | Out-Host

    # Optional: Remove jobs after monitoring (or leave them for inspection)
    # Get-Job -Id $targetJobIds | Remove-Job -Force
    # Write-AutomationLog -Level Info -Message "Cleaned up monitored jobs."

    # Keep window open until user presses Enter
    Read-Host "Press Enter to close this monitor window..."
}
