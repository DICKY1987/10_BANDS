function Invoke-Claude {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][hashtable]$ToolConfig,
        [Parameter(Mandatory=$true)][string[]]$Args
    )
    if (-not (Test-Path $ToolConfig.Path)) { throw "Claude binary not found at $($ToolConfig.Path)" }
    $argList = $Args | ForEach-Object { [string]$_ }
    Start-Process -FilePath $ToolConfig.Path -ArgumentList $argList -NoNewWindow -Wait
}
