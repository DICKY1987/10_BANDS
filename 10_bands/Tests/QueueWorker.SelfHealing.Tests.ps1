# Tests/QueueWorker.SelfHealing.Tests.ps1
Describe "QueueWorker self-healing" {
  It "recovers stale processing files" {
    $root = Join-Path $PSScriptRoot '..'
    $tasks = Join-Path $root '.tasks'
    $processing = Join-Path $tasks 'processing'
    $inbox = Join-Path $tasks 'inbox'
    New-Item -ItemType Directory -Force -Path $processing,$inbox | Out-Null
    $f = Join-Path $processing 'stale.jsonl'
    '{"tool":"git","args":["status"],"repo":"."}' | Set-Content -Path $f
    (Get-Item $f).LastWriteTime = (Get-Date).AddMinutes(-30)
    & (Join-Path $root 'scripts\RecoverProcessing.ps1') -TasksDir $tasks -StaleMinutes 10
    Test-Path (Join-Path $inbox 'stale.jsonl') | Should -BeTrue
  }
}
