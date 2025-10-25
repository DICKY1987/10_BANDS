# AutomationSuite module core
# Exported functions: Write-AutomationLog, Start-AutomationCliJob, Get-ToolColor

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Module-level whitelist (can be loaded from config in follow-up)
if (-not ($script:ToolWhitelist)) {
    # Example whitelist (absolute paths or executable names)
    $script:ToolWhitelist = @(
        'C:\Program Files\Aider\aider.exe',
        'C:\Program Files\Codex\codex.exe',
        'C:\Program Files\Claude\claude.exe'
    )
}

function Write-AutomationLog {
    <#
    .SYNOPSIS
      Writes an operational log entry. Attempts structured logging if available.
    .PARAMETER Message
      The message text
    .PARAMETER Level
      Log level (INFO/ERROR/WARN/DEBUG)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet('DEBUG','INFO','WARN','ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = (Get-Date).ToString('o')
    $prefix = "[$timestamp] [$Level]"

    try {
        if (Get-Command -Name Write-StructuredLog -ErrorAction SilentlyContinue) {
            # Structured logging adapter - use if available
            Write-StructuredLog -Level $Level -Message $Message -Timestamp $timestamp
        }
        else {
            # Fallback to console output
            Write-Output "$prefix $Message"
        }
    }
    catch {
        # If structured logging fails, warning and fallback
        Write-Warning "Structured logging failed: $($_.Exception.Message)"
        Write-Output "$prefix $Message"
    }
}

function Start-AutomationCliJob {
    <#
    .SYNOPSIS
      Start a background job for a CLI tool, with basic validation and ShouldProcess support.
    .PARAMETER ToolConfig
      A hashtable or object describing the tool. Required keys: Name, Path, Args (optional).
    .EXAMPLE
      Start-AutomationCliJob -ToolConfig @{ Name='Aider'; Path='C:\Program Files\Aider\aider.exe'; Args='--task foo' }
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$ToolConfig
    )

    # Basic validation
    if (-not $ToolConfig.ContainsKey('Name') -or -not $ToolConfig.ContainsKey('Path')) {
        throw "ToolConfig must include 'Name' and 'Path'"
    }

    $toolName = [string]$ToolConfig['Name']
    $toolPath = [string]$ToolConfig['Path']
    $toolArgs = if ($ToolConfig.ContainsKey('Args')) { [string]$ToolConfig['Args'] } else { '' }

    # Simple path validation: must be absolute, must exist, and be whitelisted
    if (-not [System.IO.Path]::IsPathRooted($toolPath)) {
        throw "Tool path must be absolute: $toolPath"
    }

    if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) {
        throw "Tool not found: $toolPath"
    }

    # Whitelist check (if whitelist configured)
    $basename = [System.IO.Path]::GetFileName($toolPath)
    $isWhitelisted = $false
    foreach ($entry in $script:ToolWhitelist) {
        if ($entry -ieq $toolPath -or $entry -ieq $basename) {
            $isWhitelisted = $true
            break
        }
    }
    if (-not $isWhitelisted) {
        throw "Tool is not in the configured whitelist: $toolPath"
    }

    # Basic argument sanitization: allow only printable characters and common punctuation
    if ($toolArgs -ne '') {
        if ($toolArgs -match '[^\r\n\t -~]') {
            throw "Tool arguments contain invalid characters"
        }
    }

    if ($PSCmdlet.ShouldProcess($toolName, "Start background job for $toolName")) {
        try {
            $scriptBlock = {
                param($exe, $arguments)
                # Start the process and wait for exit
                & $exe $arguments
                exit $LASTEXITCODE
            }

            # Start as a background job and pass arguments safely by using $using: scoping
            Start-Job -Name "automation-$($toolName)-$(Get-Random)" -ScriptBlock $scriptBlock -ArgumentList $toolPath, $toolArgs -ErrorAction Stop
        }
        catch {
            Write-AutomationLog -Message "Failed to start job for $toolName: $($_.Exception.Message)" -Level 'ERROR'
            throw
        }
    }
}

function Get-ToolColor {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ToolName,

        [Parameter(Mandatory=$false)]
        [hashtable]$ColorMap
    )

    if (-not $ColorMap) {
        $ColorMap = @{
            'Aider' = 'Green'
            'Codex' = 'Cyan'
            'Claude' = 'Magenta'
        }
    }

    if ($ColorMap.ContainsKey($ToolName)) {
        return $ColorMap[$ToolName]
    }
    return 'Gray'
}

Export-ModuleMember -Function Write-AutomationLog, Start-AutomationCliJob, Get-ToolColor