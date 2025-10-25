<#
.SYNOPSIS
  Structured JSON logging helper.
#>

function Write-StructuredLog {
    [CmdletBinding()]
    param(
        [ValidateSet('Debug','Information','Warning','Error','Critical')][string]$Level = 'Information',
        [Parameter(Mandatory=$true)][string]$Message,
        [hashtable]$Meta = @{}
    )
    $entry = @{
        timestamp = (Get-Date).ToString("o")
        level     = $Level
        message   = $Message
        meta      = $Meta
    }
    # write to stdout; in production, send to file/forwarder
    $entryJson = $entry | ConvertTo-Json -Depth 6
    Write-Output $entryJson
}
