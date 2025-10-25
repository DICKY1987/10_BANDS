function Invoke-Git {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][hashtable]$ToolConfig,
        [Parameter(Mandatory=$true)][string[]]$Args
    )
    # ToolConfig.Path could be 'git' (on PATH). Validate minimal
    $gitPath = $ToolConfig.Path
    if (-not $gitPath) { $gitPath = 'git' }
    Start-Process -FilePath $gitPath -ArgumentList $Args -NoNewWindow -Wait
}
