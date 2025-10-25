# AutomationSuite/AutomationSuite.psm1
# Core module for Automation Suite functionalities

#Requires -Version 5.1

<#
.SYNOPSIS
    Core module providing shared functions for job management, logging, and utilities.

.DESCRIPTION
    Encapsulates functions for starting background CLI jobs, handling output,
    color-coding, and basic structured logging, based on provided frameworks.

.NOTES
    Author: Gemini AI (Based on User's Frameworks)
    Version: 1.0.0
#>

#region Logging (Simplified from Framework)
# Incorporate basic structured logging inspired by Powershell_logging_framework.txt

function Write-AutomationLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Debug", "Info", "Warning", "Error", "Critical")]
        [string]$Level,
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [hashtable]$Data = @{},
        [System.Exception]$Exception,
        [string]$CorrelationId = ($ExecutionContext.SessionState.PSVariable.Get('CorrelationId') -ne $null ? $ExecutionContext.SessionState.PSVariable.Get('CorrelationId').Value : [Guid]::NewGuid().ToString("N").Substring(0, 8)),
        [string]$Source = (Get-PSCallStack)[1].FunctionName
    )

    # Simplified logging - Outputs to Host for demonstration
    # In a real scenario, integrate fully with the provided logging framework (file, event log etc.)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = "[{0}] [{1,-8}] [{2}] [{3}] {4}" -f $timestamp, $Level.ToUpper(), $CorrelationId, $Source, $Message

    $color = switch ($Level) {
        'Debug'    { 'Gray' }
        'Info'     { 'White' }
        'Warning'  { 'Yellow' }
        'Error'    { 'Red' }
        'Critical' { 'Magenta' }
        default    { 'White' }
    }

    Write-Host $logEntry -ForegroundColor $color

    if ($PSBoundParameters.ContainsKey('Data') -and $Data.Count -gt 0) {
        Write-Host ("    Data: {0}" -f ($Data | Out-String).Trim()) -ForegroundColor DarkGray
    }
    if ($PSBoundParameters.ContainsKey('Exception') -and $Exception) {
        Write-Host ("    Exception: {0} - {1}" -f $Exception.GetType().Name, $Exception.Message) -ForegroundColor DarkRed
    }
}
#endregion Logging

#region Job Management

function Start-AutomationCliJob {
    <#
    .SYNOPSIS
        Starts a CLI tool as a background PowerShell job with output tagging.
    .DESCRIPTION
        Takes configuration for a CLI tool, starts it using Start-Job,
        and configures the job to prepend each output line (stdout and stderr)
        with the tool's unique name for later identification.
    .PARAMETER ToolConfig
        A hashtable containing Name, Path, and Arguments for the tool.
    .OUTPUTS
        System.Management.Automation.Job
        The PowerShell Job object representing the background process.
    .NOTES
        Integrates basic logging via Write-AutomationLog.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ToolConfig
    )

    $toolName = $ToolConfig.Name
    $toolPath = $ToolConfig.Path
    $toolArgs = $ToolConfig.Arguments

    Write-AutomationLog -Level Info -Message "Starting background job for tool: $toolName" -Data @{ Path = $toolPath; Args = $toolArgs }

    try {
        # Define the script block to execute the tool and tag output
        # Use *>&1 to merge all streams (stdout, stderr, etc.) before tagging
        $scriptBlock = {
            param($TName, $TPath, $TArgs)
            try {
                # Execute the command and pipe all output streams (*>)
                # to ForEach-Object (%) to prepend the tool name.
                # Use Start-Transcript within the job for robust logging if needed.
                & $TPath $TArgs *>&1 | ForEach-Object { "$TName: $_" }
            }
            catch {
                # Catch errors during tool execution within the job
                "$TName: JOB_ERROR: $($_.Exception.Message)"
                # Optionally re-throw or handle differently
            }
        }

        # Start the job
        $job = Start-Job -Name $toolName -ScriptBlock $scriptBlock -ArgumentList @($toolName, $toolPath, $toolArgs)

        Write-AutomationLog -Level Info -Message "Successfully started job" -Data @{ ToolName = $toolName; JobId = $job.Id; JobState = $job.State }
        return $job
    }
    catch {
        Write-AutomationLog -Level Error -Message "Failed to start job for tool: $toolName" -Exception $_
        # Decide if failure to start one job should stop others (throw) or just be logged
        throw "Failed to start job for '$toolName': $($_.Exception.Message)"
    }
}

#endregion Job Management

#region Utilities

function Get-ToolColor {
    <#
    .SYNOPSIS
        Gets the console color associated with a tool name based on configuration.
    .PARAMETER ToolName
        The unique name identifier of the tool.
    .PARAMETER ColorMap
        A hashtable mapping tool names to ConsoleColor strings.
    .PARAMETER DefaultColor
        The ConsoleColor to return if the tool name is not found in the map.
    .OUTPUTS
        System.ConsoleColor
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolName,
        [Parameter(Mandatory = $true)]
        [hashtable]$ColorMap,
        [System.ConsoleColor]$DefaultColor = 'Gray'
    )

    if ($ColorMap.ContainsKey($ToolName)) {
        try {
            return [System.ConsoleColor]($ColorMap[$ToolName])
        }
        catch {
            Write-AutomationLog -Level Warning -Message "Invalid color specified for tool '$ToolName': '$($ColorMap[$ToolName])'. Using default."
            return $DefaultColor
        }
    }
    else {
        Write-AutomationLog -Level Debug -Message "No color specified for tool '$ToolName'. Using default."
        return $DefaultColor
    }
}

#endregion Utilities

# Export functions to make them available outside the module
Export-ModuleMember -Function Write-AutomationLog, Start-AutomationCliJob, Get-ToolColor

Write-AutomationLog -Level Debug -Message "AutomationSuite module loaded."
