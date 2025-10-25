<#
.SYNOPSIS
  Adapter for Aider CLI.
#>

function Invoke-Aider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][hashtable]$ToolConfig,
        [Parameter(Mandatory=$true)][string[]]$Args
    )
    if (-not (Test-Path $ToolConfig.Path)) { throw "Aider binary not found at $($ToolConfig.Path)" }
    $argList = $Args | ForEach-Object { [string]$_ }
    Start-Process -FilePath $ToolConfig.Path -ArgumentList $argList -NoNewWindow -Wait
}
