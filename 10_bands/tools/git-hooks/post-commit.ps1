#!/usr/bin/env pwsh
param(
    [string]$RepoRoot,
    [string]$TasksDir
)

if (-not $RepoRoot) { $RepoRoot = (Resolve-Path '..').Path }
if (-not $TasksDir) { $TasksDir = Join-Path $RepoRoot '.tasks' }
$inbox = Join-Path $TasksDir 'inbox'
New-Item -ItemType Directory -Force -Path $inbox | Out-Null

$task = @{ id = (Get-Date).ToString('yyyyMMddHHmmss'); tool = 'git'; args = @('status','-sb'); repo = $RepoRoot }
$file = Join-Path $inbox ("hook_{0}.jsonl" -f $task.id)
[System.IO.File]::WriteAllText($file, ($task | ConvertTo-Json -Compress) + "`n", [System.Text.UTF8Encoding]::new($true))
