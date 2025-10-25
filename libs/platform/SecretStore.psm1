<#
.SYNOPSIS
  Small wrapper for SecretManagement and environment fallback.
.DESCRIPTION
  - Primary: use Microsoft.PowerShell.SecretManagement and SecretStore providers.
  - Fallback: use environment variables or throw if missing.
#>

function Get-SecretValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$false)][string]$FallbackEnvVar
    )
    try {
        if (Get-Module -ListAvailable -Name Microsoft.PowerShell.SecretManagement) {
            Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction SilentlyContinue
            $s = Get-Secret -Name $Name -ErrorAction SilentlyContinue
            if ($s) { return $s }
        }
    } catch {
        # ignore to fallback to env var
    }

    if ($FallbackEnvVar -and $env:$FallbackEnvVar) {
        return $env:$FallbackEnvVar
    }

    throw "Secret '$Name' not found in Secret Management backends or environment."
}
