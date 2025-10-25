# scripts/run_quality.ps1
# Runs Python and PowerShell quality gates headlessly. Exits non-zero on failure.
[CmdletBinding()] param(
  [string]$Python = "python",
  [string]$LogsDir = (Join-Path $PSScriptRoot "..\logs")
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ruffLog   = Join-Path $LogsDir "ruff_$stamp.log"
$pytestLog = Join-Path $LogsDir "pytest_$stamp.log"
$pesterLog = Join-Path $LogsDir "pester_$stamp.log"

function Invoke-Step($Name, [scriptblock]$Body) {
  Write-Host "== $Name ==" -ForegroundColor Cyan
  & $Body
  if ($LASTEXITCODE -ne 0) { throw "$Name failed with exit code $LASTEXITCODE" }
}

# Python: ruff (format check + lint) then pytest
Invoke-Step "Ruff format (check)" { & $Python -m ruff format --check | Tee-Object -FilePath $ruffLog -Append; $global:LASTEXITCODE = $LASTEXITCODE }
Invoke-Step "Ruff lint" { & $Python -m ruff check . | Tee-Object -FilePath $ruffLog -Append; $global:LASTEXITCODE = $LASTEXITCODE }
Invoke-Step "pytest" { & $Python -m pytest | Tee-Object -FilePath $pytestLog -Append; $global:LASTEXITCODE = $LASTEXITCODE }

# PowerShell: Pester
Import-Module Pester -ErrorAction Stop
$cfgPath = Join-Path $PSScriptRoot "..\PesterConfiguration.psd1"
if (Test-Path $cfgPath) {
  $cfg = Import-PowerShellDataFile $cfgPath
  $results = Invoke-Pester -Configuration $cfg 2>&1 | Tee-Object -FilePath $pesterLog
} else {
  $results = Invoke-Pester -Path (Join-Path $PSScriptRoot '..\Tests') -Output Detailed 2>&1 | Tee-Object -FilePath $pesterLog
}
if (-not $results.Result -or $results.Result.FailedCount -gt 0) {
  throw "Pester tests failed"
}

Write-Host "Quality gate: OK" -ForegroundColor Green
