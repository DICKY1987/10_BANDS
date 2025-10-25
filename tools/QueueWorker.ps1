# QueueWorker.ps1 (hardened, headless, self-healing)
<#
  Headless queue runner for aider / codex / claude / git (or any CLI).
  Watches a tasks directory for *.jsonl files (one JSON object per line).
#>

param(
  [string]$Repo      = (Join-Path $PSScriptRoot ".."),
  [string]$TasksDir  = (Join-Path $PSScriptRoot "..\.tasks"),
  [string]$LogsDir   = (Join-Path $PSScriptRoot "..\logs"),
  [int]$PollSeconds  = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Dirs
$inbox      = Join-Path $TasksDir "inbox"
$processing = Join-Path $TasksDir "processing"
$done       = Join-Path $TasksDir "done"
$failed     = Join-Path $TasksDir "failed"
$quarantine = Join-Path $TasksDir "quarantine"
$null = New-Item -ItemType Directory -Force -Path $inbox,$processing,$done,$failed,$quarantine,$LogsDir

# Policy & state
$policy  = Import-PowerShellDataFile (Join-Path $PSScriptRoot '..\Config\HeadlessPolicies.psd1')
$stateDir = Join-Path $PSScriptRoot '..\.state'
$ledger   = Join-Path $LogsDir 'ledger.jsonl'
$cbPath   = Join-Path $stateDir 'circuit_breakers.json'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

# Logger
function Write-Log {
  param([string]$Message,[string]$Level="INFO",[string]$Id="")
  $stamp = (Get-Date).ToString("o")
  $line  = "[$stamp][$Level]$($Id ? "[$Id]" : "") $Message"
  $line | Tee-Object -FilePath (Join-Path $LogsDir "queueworker.log") -Append | Out-Host
}

function Write-Heartbeat {
  $obj = @{ timestamp = (Get-Date).ToString('o'); pid = $PID }
  $obj | ConvertTo-Json -Compress | Set-Content -Encoding UTF8 -Path (Join-Path $stateDir 'heartbeat.json')
}

function Rotate-LogIfNeeded([string]$path) {
  $maxMB = [int]$policy.Queue.LogRotateMaxMB
  if (Test-Path $path) {
    $mb = ([IO.FileInfo]$path).Length/1MB
    if ($mb -gt $maxMB) {
      $arch = Join-Path $LogsDir "archive"; New-Item -ItemType Directory -Force -Path $arch | Out-Null
      $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
      Move-Item $path (Join-Path $arch ("$(Split-Path $path -Leaf).$ts"))
    }
  }
}

function Write-Ledger($rec) {
  ($rec | ConvertTo-Json -Compress) + "`n" | Add-Content -Path $ledger -Encoding UTF8
  Rotate-LogIfNeeded $ledger
}

function Validate-Task([hashtable]$t) {
  if (-not $t.id)      { $t.id = ([Guid]::NewGuid().ToString('n')).Substring(0,10) }
  if (-not $t.tool)    { throw "Task missing 'tool'" }
  if (-not $t.repo)    { $t.repo = $Repo }
  $t.max_retries   = $t.max_retries  ?? $policy.Retry.DefaultMaxRetries
  $t.backoff_sec   = $t.backoff_sec  ?? $policy.Retry.BackoffStartSeconds
  $t.backoff_max   = $t.backoff_max  ?? $policy.Retry.BackoffMaxSeconds
  $t.jitter_sec    = $t.jitter_sec   ?? $policy.Retry.JitterSeconds
  $t.attempt       = [int]($t.attempt ?? 0)
  return $t
}

function Get-CB { if (Test-Path $cbPath) { Get-Content $cbPath -Raw | ConvertFrom-Json } else { @{} } }
function Save-CB($o) { ($o | ConvertTo-Json -Compress) | Set-Content -Path $cbPath -Encoding UTF8 }

function Is-Broken($tool) {
  $cb = Get-CB
  if (-not $cb.ContainsKey($tool)) { return $false }
  if ($cb.$tool.state -ne 'open') { return $false }
  return (Get-Date) - [datetime]$cb.$tool.until -lt [timespan]::Zero
}

function Trip-Or-Reset-CB($tool, [bool]$success) {
  $cb = Get-CB
  if (-not $cb.ContainsKey($tool)) { $cb.$tool = @{ fails = 0; state='closed'; until=(Get-Date) } }
  if ($success) {
    $cb.$tool.fails = 0; $cb.$tool.state='closed'
  } else {
    $cb.$tool.fails++
    if ($cb.$tool.fails -ge [int]$policy.CircuitBreaker.WindowFailures) {
      $cb.$tool.state='open'
      $cb.$tool.until=(Get-Date).AddSeconds([int]$policy.CircuitBreaker.OpenSeconds)
    }
  }
  Save-CB $cb
}

function Heal-GitRepo([string]$repo) {
  $gitLock = Join-Path $repo ".git\index.lock"
  if (Test-Path $gitLock) {
    $age = (Get-Date) - (Get-Item $gitLock).LastWriteTime
    if ($age.TotalMinutes -ge [int]$policy.Git.IndexLockStaleMinutes -and -not (Get-Process git -ErrorAction SilentlyContinue)) {
      Remove-Item $gitLock -Force
    }
  }
}

# Tool command builders
function Build-Command {
  param(
    [hashtable]$Task,
    [string]$PromptFile
  )
  $tool = ($Task.tool ?? "aider").ToLowerInvariant()
  $flags = @($Task.flags) | Where-Object { $_ }
  $args  = @($Task.args)  | Where-Object { $_ }
  $files = @($Task.files) | ForEach-Object {
    $p = $_
    if (-not [System.IO.Path]::IsPathRooted($p)) { Join-Path $Task.repo $p } else { $p }
  }

  switch ($tool) {
    "aider" {
      $exe = "aider"
      $argv = @()
      if ($PromptFile) { $argv += @("--message-file", $PromptFile) }
      $argv += $flags
      $argv += $files
      return ,@($exe, $argv)
    }
    "codex" {
      $exe = "codex"
      $argv = @()
      if ($PromptFile) { $argv += @("--message-file", $PromptFile) }
      $argv += $flags
      $argv += $files
      return ,@($exe, $argv)
    }
    "claude" {
      $exe = "claude"
      $argv = @()
      if ($PromptFile) { $argv += @("--message-file", $PromptFile) }
      $argv += $flags
      $argv += $files
      return ,@($exe, $argv)
    }
    "git" {
      $exe = "git"
      $argv = @()
      $argv += $args
      return ,@($exe, $argv)
    }
    default {
      $exe = $tool
      $argv = @()
      if ($PromptFile) { $argv += @("--message-file", $PromptFile) }
      $argv += $flags + $args + $files
      return ,@($exe, $argv)
    }
  }
}

function Try-Invoke-WithRetry([hashtable]$task, [scriptblock]$run) {
  $exit = 0
  while ($true) {
    $task.attempt++
    $start = Get-Date
    $exit = & $run.InvokeReturnAsIs()
    $ok = ($exit -eq 0)
    Write-Ledger @{
      ts=(Get-Date).ToString('o'); id=$task.id; tool=$task.tool; attempt=$task.attempt;
      exit=$exit; ok=$ok; repo=$task.repo
    }
    Trip-Or-Reset-CB $task.tool $ok
    if ($ok) { return 0 }
    if ($task.attempt -ge [int]$task.max_retries) { return $exit }
    $sleep = [Math]::Min([int]$task.backoff_max, [int]$task.backoff_sec * [Math]::Pow(2, $task.attempt-1)) + (Get-Random -Min 0 -Max ([int]$task.jitter_sec))
    Start-Sleep -Seconds $sleep
  }
}

# One-time recovery pass
& (Join-Path $PSScriptRoot 'RecoverProcessing.ps1') -TasksDir (Join-Path $PSScriptRoot '..\.tasks') -StaleMinutes $policy.Queue.RecoveryProcessingStaleMinutes

Write-Log "QueueWorker starting. Repo=$Repo TasksDir=$TasksDir LogsDir=$LogsDir"

$stopFile = Join-Path $PSScriptRoot "..\STOP.HEADLESS"
while ($true) {
  Write-Heartbeat
  Heal-GitRepo $Repo

  if (Test-Path $stopFile) { Write-Log "Stop file detected; exiting."; break }

  $file = Get-ChildItem $inbox -File -Filter *.jsonl -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -First 1
  if (-not $file) { Start-Sleep -Seconds $PollSeconds; continue }

  $work = Join-Path $processing $file.Name
  try { Move-Item $file.FullName $work -Force } catch { continue }

  $lines = Get-Content -LiteralPath $work -Raw -Encoding UTF8 -ErrorAction Stop -ReadCount 0
  $allOk = $true

  foreach ($line in ($lines -split "(`r`n|`n)" | Where-Object { $_ -match '\S' })) {
    try {
      $task = Validate-Task (ConvertFrom-Json $line -ErrorAction Stop)
    } catch {
      Move-Item $work (Join-Path $failed $file.Name) -Force
      Write-Ledger @{ ts=(Get-Date).ToString('o'); id='parse'; tool='n/a'; attempt=0; exit=999; ok=$false; note='bad json'; file=$file.Name }
      $allOk=$false; break
    }

    if (Is-Broken $task.tool) {
      Move-Item $work (Join-Path $quarantine $file.Name) -Force
      $allOk=$false; break
    }

    $promptFile = $null
    if ($task.prompt) {
      $promptDir = Join-Path $LogsDir "prompts"; New-Item -ItemType Directory -Force -Path $promptDir | Out-Null
      $promptFile = Join-Path $promptDir ("prompt_{0}.txt" -f $task.id)
      [IO.File]::WriteAllText($promptFile, [string]$task.prompt, [Text.UTF8Encoding]::new($true))
    }
    $exe,$argv = Build-Command -Task $task -PromptFile $promptFile
    $taskLog = Join-Path $LogsDir ("task_{0}.log" -f $task.id)

    $runner = {
      param($exe,$argv,$log,$timeout)
      try {
        $exePath = (Get-Command $exe -ErrorAction Stop).Source
      } catch {
        [IO.File]::AppendAllText($log, "Could not locate executable: $exe`n", [Text.UTF8Encoding]::new($true))
        return 127
      }
      $job = Start-Job -ScriptBlock { param($ep,$av,$lg) & $ep @av 2>&1 | Tee-Object -FilePath $lg -Append; $LASTEXITCODE } -ArgumentList $exePath,$argv,$log
      if ($timeout -gt 0) { if (-not (Wait-Job $job -Timeout $timeout)) { Stop-Job $job -Force; return 998 } } else { Wait-Job $job | Out-Null }
      $code = Receive-Job $job -Keep | Select-Object -Last 1
      if ($null -eq $code -or $code -isnot [int]) { $code = 0 }
      return $code
    }.GetNewClosure()

    $code = Try-Invoke-WithRetry $task { $runner.Invoke($exe,$argv,$taskLog,[int]($task.timeout_sec ?? 0)) }
    if ($code -ne 0) { $allOk = $false }
  }

  if ($allOk) { Move-Item $work (Join-Path $done $file.Name) -Force } else {
    Move-Item $work (Join-Path $failed $file.Name) -Force
  }
}
