#!/usr/bin/env pwsh
# Manual verification script for git branch safety validation

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Load the Test-GitBranchSafety function from QueueWorker.ps1
$workerScript = Join-Path $PSScriptRoot 'tools/QueueWorker.ps1'
$workerContent = Get-Content $workerScript -Raw

# Extract and define the Test-GitBranchSafety function
if ($workerContent -match '(?ms)function Test-GitBranchSafety \{.*?\r?\n\}') {
    Invoke-Expression $Matches[0]
} else {
    Write-Error "Could not find Test-GitBranchSafety function"
    exit 1
}

Write-Host "`n=== Git Branch Safety Validation Demo ===" -ForegroundColor Cyan
Write-Host ""

# Test cases
$testCases = @(
    @{
        Description = "Safe: git status"
        Args = @('status')
        ExpectedSafe = $true
    }
    @{
        Description = "Safe: git checkout -b feature/new-feature"
        Args = @('checkout', '-b', 'feature/new-feature')
        ExpectedSafe = $true
    }
    @{
        Description = "BLOCKED: git checkout -b rollback/main/20251025"
        Args = @('checkout', '-b', 'rollback/main/20251025')
        ExpectedSafe = $false
    }
    @{
        Description = "BLOCKED: git branch rollback/feature"
        Args = @('branch', 'rollback/feature')
        ExpectedSafe = $false
    }
    @{
        Description = "BLOCKED: git push origin rollback/main"
        Args = @('push', 'origin', 'rollback/main')
        ExpectedSafe = $false
    }
    @{
        Description = "BLOCKED: git push origin HEAD:refs/heads/rollback/test"
        Args = @('push', 'origin', 'HEAD:refs/heads/rollback/test')
        ExpectedSafe = $false
    }
    @{
        Description = "Safe: git push origin main"
        Args = @('push', 'origin', 'main')
        ExpectedSafe = $true
    }
    @{
        Description = "Safe: git checkout -b my-rollback-feature (rollback not at start)"
        Args = @('checkout', '-b', 'my-rollback-feature')
        ExpectedSafe = $true
    }
)

$passed = 0
$failed = 0

foreach ($test in $testCases) {
    $result = Test-GitBranchSafety -GitArgs $test.Args
    
    if ($result.Safe -eq $test.ExpectedSafe) {
        Write-Host "✓ PASS: " -ForegroundColor Green -NoNewline
        Write-Host $test.Description
        if (-not $result.Safe) {
            Write-Host "  Reason: $($result.Reason)" -ForegroundColor Yellow
        }
        $passed++
    } else {
        Write-Host "✗ FAIL: " -ForegroundColor Red -NoNewline
        Write-Host $test.Description
        Write-Host "  Expected Safe=$($test.ExpectedSafe), Got Safe=$($result.Safe)" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "=== Results ===" -ForegroundColor Cyan
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })

if ($failed -eq 0) {
    Write-Host "`n✓ All validation tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n✗ Some tests failed!" -ForegroundColor Red
    exit 1
}
