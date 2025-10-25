<#
.SYNOPSIS
  Domain core module for 10_BANDS.
.DESCRIPTION
  Exposes a small, well-documented public API that other layers consume.
#>

Export-ModuleMember -Function Get-ToolColor, Write-AutomationLog, Start-AutomationCliJob

function Get-ToolColor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ToolName,
        [Parameter(Mandatory = $false)][hashtable]$ColorMap = @{}
    )
    if ($null -ne $ColorMap -and $ColorMap.ContainsKey($ToolName)) {
        return $ColorMap[$ToolName]
    }
    return 'Gray'
}

function Write-AutomationLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Debug','Information','Warning','Error','Critical')][string]$Level,
        [Parameter(Mandatory=$true)][string]$Message,
        [hashtable]$Meta = @{}
    )
    if (Get-Command -Name Write-StructuredLog -ErrorAction SilentlyContinue) {
        Write-StructuredLog -Level $Level -Message $Message -Meta $Meta
    } else {
        $ts = (Get-Date).ToString("o")
        Write-Output "[$ts] [$Level] $Message"
    }
}

function Start-AutomationCliJob {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)][hashtable]$ToolConfig,
        [Parameter(Mandatory=$false)][object[]]$Arguments
    )

    if ($PSCmdlet.ShouldProcess($ToolConfig.Name, "Start background job")) {
        # Validate path
        $path = $ToolConfig.Path
        if (-not (Test-Path $path)) { throw "Tool not found: $path" }

        # Basic argument sanitization: ensure strings, no embedded newlines
        $args = @()
        if ($Arguments) { $args = $Arguments | ForEach-Object { ([string]$_).Replace("`n"," ").Replace("`r"," ") } }

        # Start process (blocking to simplify orchestration; can be adjusted)
        Start-Process -FilePath $path -ArgumentList $args -NoNewWindow -Wait
        Write-AutomationLog -Level 'Information' -Message "Started tool: $($ToolConfig.Name)" -Meta @{ Path = $path }
    }
}
