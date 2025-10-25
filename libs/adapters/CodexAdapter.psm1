function Invoke-Codex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][hashtable]$ToolConfig,
        [Parameter(Mandatory=$true)][string[]]$Args
    )
    if (-not (Test-Path $ToolConfig.Path)) { throw "Codex binary not found at $($ToolConfig.Path)" }
    $argList = $Args | ForEach-Object { [string]$_ }
    Start-Process -FilePath $ToolConfig.Path -ArgumentList $argList -NoNewWindow -Wait
}
