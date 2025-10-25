# QueueWorker.ps1 (phase 3 concurrency + orchestration)
<#
  Advanced headless queue runner supporting concurrent execution,
  scheduling, dependencies, recurring tasks, and plugin-defined tools.
#>

param(
  [string]$Repo,
  [string]$TasksDir,
  [string]$LogsDir,
  [int]$PollSeconds = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$rootDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $Repo)     { $Repo     = $rootDir }
if (-not $TasksDir) { $TasksDir = Join-Path $rootDir '.tasks' }
if (-not $LogsDir)  { $LogsDir  = Join-Path $rootDir 'logs' }

# Directories
$inbox      = Join-Path $TasksDir 'inbox'
$processing = Join-Path $TasksDir 'processing'
$done       = Join-Path $TasksDir 'done'
$failed     = Join-Path $TasksDir 'failed'
$quarantine = Join-Path $TasksDir 'quarantine'
$stateDir   = Join-Path $Repo '.state'
$ledger     = Join-Path $LogsDir 'ledger.jsonl'
$runningFile = Join-Path $stateDir 'running_tasks.json'
$hbFile      = Join-Path $stateDir 'heartbeat.json'

$null = New-Item -ItemType Directory -Force -Path $inbox,$processing,$done,$failed,$quarantine,$LogsDir,$stateDir

# Policies & configuration
$policyPath = Join-Path (Join-Path (Join-Path $PSScriptRoot '..') 'Config') 'HeadlessPolicies.psd1'
$policy = Import-PowerShellDataFile $policyPath
$maxConcurrent = [int]($policy.Queue.MaxConcurrentTasks ?? 3)
$retryPolicy   = $policy.Retry

# Mutex for ledger writes (cross platform safe name)
$ledgerMutex = [System.Threading.Mutex]::new($false, 'QueueWorkerLedgerMutex')

# Global state
$plugins = @{}
$toolLocks = @{}
$pendingTasks = New-Object System.Collections.ArrayList
$runningJobs  = @{}
$fileContexts = @{}
$taskResults  = @{}

# Helper: safe JSON write
function Write-JsonFile {
  param([string]$Path, [object]$Data)
  $tmp = "$Path.tmp"
  ($Data | ConvertTo-Json -Depth 8) | Set-Content -Path $tmp -Encoding UTF8
  Move-Item -Path $tmp -Destination $Path -Force
}

function Write-Log {
  param([string]$Message,[string]$Level='INFO',[string]$Id='')
  $stamp = (Get-Date).ToString('o')
  $line  = "[$stamp][$Level]$($Id ? "[$Id]" : '') $Message"
  $line | Tee-Object -FilePath (Join-Path $LogsDir 'queueworker.log') -Append | Out-Host
}

function Write-Heartbeat {
  $obj = @{ timestamp = (Get-Date).ToString('o'); pid = $PID; running = $runningJobs.Count; max = $maxConcurrent }
  $obj | ConvertTo-Json -Compress | Set-Content -Path $hbFile -Encoding UTF8
}

function Rotate-LogIfNeeded([string]$path) {
  $maxMB = [int]$policy.Queue.LogRotateMaxMB
  if (Test-Path $path) {
    $mb = ([IO.FileInfo]$path).Length / 1MB
    if ($mb -gt $maxMB) {
      $arch = Join-Path $LogsDir 'archive'
      New-Item -ItemType Directory -Force -Path $arch | Out-Null
      $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
      Move-Item $path (Join-Path $arch ("$(Split-Path $path -Leaf).$ts"))
    }
  }
}

function With-LedgerLock {
  param([scriptblock]$Body)
  $acquired = $false
  try {
    $acquired = $ledgerMutex.WaitOne([TimeSpan]::FromSeconds(30))
    if (-not $acquired) { throw 'Ledger mutex timeout' }
    & $Body
  }
  finally {
    if ($acquired) { $ledgerMutex.ReleaseMutex() | Out-Null }
  }
}

function Write-Ledger {
  param([hashtable]$Record)
  With-LedgerLock {
    ($Record | ConvertTo-Json -Compress) + "`n" | Add-Content -Path $ledger -Encoding UTF8
  }
  Rotate-LogIfNeeded $ledger
}

function Get-CB { if (Test-Path $cbPath) { Get-Content $cbPath -Raw | ConvertFrom-Json } else { @{} } }
function Save-CB($o) { ($o | ConvertTo-Json -Compress) | Set-Content -Path $cbPath -Encoding UTF8 }

$cbPath = Join-Path $stateDir 'circuit_breakers.json'

function Trip-Or-Reset-CB($tool, [bool]$success) {
  $cb = Get-CB
  if (-not $cb.ContainsKey($tool)) { $cb.$tool = @{ fails = 0; state='closed'; until=(Get-Date) } }
  if ($success) {
    $cb.$tool.fails = 0; $cb.$tool.state='closed'
  }
  else {
    $cb.$tool.fails++
    if ($cb.$tool.fails -ge [int]$policy.CircuitBreaker.WindowFailures) {
      $cb.$tool.state='open'
      $cb.$tool.until=(Get-Date).AddSeconds([int]$policy.CircuitBreaker.OpenSeconds)
    }
  }
  Save-CB $cb
}

function Is-Broken($tool) {
  $cb = Get-CB
  if (-not $cb.ContainsKey($tool)) { return $false }
  if ($cb.$tool.state -ne 'open') { return $false }
  return (Get-Date) - [datetime]$cb.$tool.until -lt [timespan]::Zero
}

function Heal-GitRepo([string]$repo) {
  $gitLock = Join-Path $repo '.git'
  $gitLock = Join-Path $gitLock 'index.lock'
  if (Test-Path $gitLock) {
    $age = (Get-Date) - (Get-Item $gitLock).LastWriteTime
    if ($age.TotalMinutes -ge [int]$policy.Git.IndexLockStaleMinutes -and -not (Get-Process git -ErrorAction SilentlyContinue)) {
      Remove-Item $gitLock -Force
    }
  }
}

function Test-GitBranchSafety {
  param([array]$GitArgs)
  if ($GitArgs -contains 'checkout' -and $GitArgs -contains '-b') {
    $idx = [array]::IndexOf($GitArgs, '-b')
    if ($idx -ge 0 -and ($idx + 1) -lt $GitArgs.Count) {
      $branchName = $GitArgs[$idx + 1]
      if ($branchName -match '^rollback/') { return @{ Safe = $false; Reason = "Branch creation with name starting with 'rollback/' is not allowed: $branchName" } }
    }
  }
  if ($GitArgs -contains 'branch' -and $GitArgs.Count -ge 2) {
    $idx = [array]::IndexOf($GitArgs, 'branch')
    if ($idx -ge 0 -and ($idx + 1) -lt $GitArgs.Count) {
      $branchName = $GitArgs[$idx + 1]
      if (-not $branchName.StartsWith('-') -and $branchName -match '^rollback/') {
        return @{ Safe = $false; Reason = "Branch creation with name starting with 'rollback/' is not allowed: $branchName" }
      }
    }
  }
  if ($GitArgs -contains 'push') {
    foreach ($arg in $GitArgs) {
      if ($arg -match '^rollback/') { return @{ Safe = $false; Reason = "Push to branch starting with 'rollback/' is not allowed: $arg" } }
      if ($arg -match ':refs/heads/rollback/' -or $arg -match ':refs/remotes/.*/rollback/') { return @{ Safe = $false; Reason = "Push to ref starting with 'rollback/' is not allowed: $arg" } }
      if ($arg -match '^refs/heads/rollback/' -or $arg -match '^refs/remotes/.*/rollback/') { return @{ Safe = $false; Reason = "Push to ref starting with 'rollback/' is not allowed: $arg" } }
    }
  }
  return @{ Safe = $true; Reason = '' }
}

function Load-Plugins {
  $pluginDir = Join-Path $Repo 'plugins'
  if (-not (Test-Path $pluginDir)) { return }
  foreach ($file in Get-ChildItem -Path $pluginDir -Filter '*.ps1' -File -ErrorAction SilentlyContinue) {
    try {
      $plugin = & $file.FullName
      if ($plugin -and $plugin.Name -and $plugin.Tool -and $plugin.ResolveCommand) {
        $plugins[$plugin.Tool.ToLowerInvariant()] = $plugin
        Write-Log "Loaded plugin '$($plugin.Name)' for tool '$($plugin.Tool)'" 'INFO'
      }
    }
    catch {
      Write-Log "Failed to load plugin $($file.Name): $_" 'ERROR'
    }
  }
}

function Validate-Task([hashtable]$t) {
  if (-not $t.id)      { $t.id = ([Guid]::NewGuid().ToString('n')).Substring(0,10) }
  if (-not $t.tool)    { throw "Task missing 'tool'" }
  if (-not $t.repo)    { $t.repo = $Repo }
  $t.priority = ($t.priority ?? 'normal').ToString().ToLowerInvariant()
  if ($t.priority -notin @('high','normal','low')) { $t.priority = 'normal' }
  $t.max_retries = [int]($t.max_retries ?? $retryPolicy.DefaultMaxRetries)
  $t.backoff_sec = [int]($t.backoff_sec ?? $retryPolicy.BackoffStartSeconds)
  $t.backoff_max = [int]($t.backoff_max ?? $retryPolicy.BackoffMaxSeconds)
  $t.jitter_sec  = [int]($t.jitter_sec  ?? $retryPolicy.JitterSeconds)
  $t.attempt     = [int]($t.attempt ?? 0)
  $t.depends_on  = @($t.depends_on) | Where-Object { $_ }
  if ($t.run_at) {
    try {
      $t.run_at = [datetime]::Parse($t.run_at)
    }
    catch {
      throw "Invalid run_at timestamp for task $($t.id)"
    }
  }
  $t.recurring_minutes = if ($t.recurring_minutes) { [int]$t.recurring_minutes } else { 0 }
  return $t
}

function Get-TaskPriorityValue($task) {
  switch ($task.priority) {
    'high' { return 2 }
    'normal' { return 1 }
    'low' { return 0 }
    default { return 1 }
  }
}

function Build-Command([hashtable]$Task, [string]$PromptFile) {
  $tool = ($Task.tool ?? 'aider').ToLowerInvariant()
  $flags = @($Task.flags) | Where-Object { $_ }
  $args  = @($Task.args)  | Where-Object { $_ }
  $files = @($Task.files) | ForEach-Object {
    $p = $_
    if (-not [System.IO.Path]::IsPathRooted($p)) { Join-Path $Task.repo $p } else { $p }
  }

  if ($plugins.ContainsKey($tool)) {
    $plugin = $plugins[$tool]
    $cmd = & $plugin.ResolveCommand $Task $PromptFile
    if (-not $cmd) { throw "Plugin for $tool returned no command" }
    return ,@($cmd.Executable, @($cmd.Arguments))
  }

  switch ($tool) {
    'aider' {
      $exe = 'aider'
      $argv = @()
      if ($PromptFile) { $argv += @('--message-file', $PromptFile) }
      $argv += $flags
      $argv += $files
      return ,@($exe, $argv)
    }
    'codex' {
      $exe = 'codex'
      $argv = @()
      if ($PromptFile) { $argv += @('--message-file', $PromptFile) }
      $argv += $flags
      $argv += $files
      return ,@($exe, $argv)
    }
    'claude' {
      $exe = 'claude'
      $argv = @()
      if ($PromptFile) { $argv += @('--message-file', $PromptFile) }
      $argv += $flags
      $argv += $files
      return ,@($exe, $argv)
    }
    'git' {
      $exe = 'git'
      $argv = @()
      $argv += $args
      $safety = Test-GitBranchSafety -GitArgs $argv
      if (-not $safety.Safe) { throw "SECURITY: $($safety.Reason)" }
      return ,@($exe, $argv)
    }
    default {
      $exe = $tool
      $argv = @()
      if ($PromptFile) { $argv += @('--message-file', $PromptFile) }
      $argv += $flags + $args + $files
      return ,@($exe, $argv)
    }
  }
}

function Update-RunningTasksFile {
  $payload = @()
  foreach ($entry in $runningJobs.Values) {
    $payload += [ordered]@{
      id = $entry.task.id
      tool = $entry.task.tool
      repo = $entry.task.repo
      started = $entry.started.ToString('o')
      file = $entry.sourceFile
      priority = $entry.task.priority
      attempt = $entry.task.attempt
    }
  }
  Write-JsonFile -Path $runningFile -Data $payload
}

function Ensure-RunningTasksFile {
  if (-not (Test-Path $runningFile)) { Write-JsonFile -Path $runningFile -Data @() }
}

function Handle-DependencyFailure($task, $reason, $fileContext, $entry) {
  Write-Log "Task $($task.id) skipped due to dependency: $reason" 'WARN' $task.id
  $taskResults[$task.id] = @{ success = $false; reason = $reason; exit = 409 }
  Write-Ledger @{ ts=(Get-Date).ToString('o'); id=$task.id; tool=$task.tool; attempt=0; exit=409; ok=$false; repo=$task.repo; note=$reason }
  $fileContext.failures++
  $fileContext.completed++
  [void]$pendingTasks.Remove($entry)
}

function Schedule-RecurringTask($task) {
  if ($task.recurring_minutes -le 0) { return }
  $nextTime = (Get-Date).AddMinutes([int]$task.recurring_minutes)
  $newTask = [hashtable]$task.Clone()
  $newTask.run_at = $nextTime.ToString('o')
  $newTask.attempt = 0
  $tid = "$($task.id)_$([DateTime]::Now.ToString('HHmmss'))"
  $newTask.id = $tid
  $payload = ($newTask | ConvertTo-Json -Compress)
  $fileName = "recur_$tid.jsonl"
  $target = Join-Path $inbox $fileName
  Set-Content -Path $target -Value $payload -Encoding UTF8
  Write-Log "Recurring task $($task.id) scheduled for $nextTime (file: $fileName)" 'INFO'
}

Load-Plugins
Ensure-RunningTasksFile

function New-FileContext($fileName,$taskCount) {
  return [pscustomobject]@{ file=$fileName; total=$taskCount; completed=0; failures=0; tasks=@() }
}

function Add-PendingTask($task,$fileContext) {
  $entry = [pscustomobject]@{ task=$task; sourceFile=$fileContext.file; state='pending'; added=(Get-Date); fileContext=$fileContext }
  $pendingTasks.Add($entry) | Out-Null
  $fileContext.tasks += $task.id
  return $entry
}

function Read-TaskFile($path) {
  $lines = Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop -ReadCount 0
  return $lines -split "(`r`n|`n)" | Where-Object { $_ -match '\S' }
}

function Is-TaskReady($entry) {
  $task = $entry.task
  if ($entry.state -ne 'pending') { return $false }
  $key = $task.tool.ToLowerInvariant()
  if ($toolLocks.ContainsKey($key) -and $toolLocks[$key]) { return $false }
  if ($runningJobs.Count -ge $maxConcurrent) { return $false }
  if ($task.run_at -and [datetime]$task.run_at -gt (Get-Date)) { return $false }
  foreach ($dep in $task.depends_on) {
    if (-not $taskResults.ContainsKey($dep)) { return $false }
    if (-not $taskResults[$dep].success) { return $false }
  }
  return $true
}

function Acquire-ToolLock($tool,$jobId) {
  $key = $tool.ToLowerInvariant()
  if (-not $toolLocks.ContainsKey($key)) { $toolLocks[$key] = $null }
  if ($toolLocks[$key]) { return $false }
  $toolLocks[$key] = $jobId
  return $true
}

function Release-ToolLock($tool,$jobId) {
  $key = $tool.ToLowerInvariant()
  if ($toolLocks.ContainsKey($key) -and $toolLocks[$key] -eq $jobId) { $toolLocks[$key] = $null }
}

function Start-TaskJob($entry) {
  $task = $entry.task
  $promptFile = $null
  if ($task.prompt) {
    $promptDir = Join-Path $LogsDir 'prompts'
    New-Item -ItemType Directory -Force -Path $promptDir | Out-Null
    $promptFile = Join-Path $promptDir ("prompt_{0}.txt" -f $task.id)
    [IO.File]::WriteAllText($promptFile, [string]$task.prompt, [System.Text.UTF8Encoding]::new($true))
  }
  try {
    $exe,$argv = Build-Command -Task $task -PromptFile $promptFile
  }
  catch {
    Write-Log "Task $($task.id) rejected: $_" 'ERROR' $task.id
    Write-Ledger @{ ts=(Get-Date).ToString('o'); id=$task.id; tool=$task.tool; attempt=0; exit=403; ok=$false; note=$_.Exception.Message; repo=$task.repo }
    $entry.fileContext.failures++
    $entry.fileContext.completed++
    $entry.state = 'complete'
    return $false
  }

  $taskLog = Join-Path $LogsDir ("task_{0}.log" -f $task.id)
  $timeout = [int]($task.timeout_sec ?? 0)
  $job = Start-Job -InitializationScript { Set-StrictMode -Version Latest } -ArgumentList @($task,$exe,$argv,$taskLog,$timeout,$retryPolicy) -ScriptBlock {
    param($task,$exe,$argv,$log,$timeout,$retryPolicy)
    function Invoke-Attempt {
      param($exe,$argv,$log,$timeout)
      try {
        $exePath = (Get-Command $exe -ErrorAction Stop).Source
      }
      catch {
        [IO.File]::AppendAllText($log, "Could not locate executable: $exe`n", [System.Text.UTF8Encoding]::new($true))
        return @{ Exit = 127; Duration = 0; TimedOut = $false }
      }
      $psi = [System.Diagnostics.ProcessStartInfo]::new()
      $psi.FileName = $exePath
      foreach ($arg in $argv) { $null = $psi.ArgumentList.Add($arg) }
      $psi.RedirectStandardOutput = $true
      $psi.RedirectStandardError = $true
      $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
      $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
      $psi.UseShellExecute = $false
      $psi.CreateNoWindow = $true
      $proc = [System.Diagnostics.Process]::new()
      $proc.StartInfo = $psi
      $stdoutBuilder = [System.Text.StringBuilder]::new()
      $stderrBuilder = [System.Text.StringBuilder]::new()
      $handlerOut = [System.Diagnostics.DataReceivedEventHandler]{ param($s,$e) if ($e.Data) { [void]$stdoutBuilder.AppendLine($e.Data) } }
      $handlerErr = [System.Diagnostics.DataReceivedEventHandler]{ param($s,$e) if ($e.Data) { [void]$stderrBuilder.AppendLine($e.Data) } }
      $proc.add_OutputDataReceived($handlerOut)
      $proc.add_ErrorDataReceived($handlerErr)
      $null = $proc.Start()
      $proc.BeginOutputReadLine()
      $proc.BeginErrorReadLine()
      $timedOut = $false
      if ($timeout -gt 0) {
        if (-not $proc.WaitForExit($timeout * 1000)) {
          $timedOut = $true
          try { $proc.Kill() } catch { }
        }
      }
      $proc.WaitForExit()
      $proc.CancelOutputRead()
      $proc.CancelErrorRead()
      $proc.remove_OutputDataReceived($handlerOut)
      $proc.remove_ErrorDataReceived($handlerErr)
      $stdout = $stdoutBuilder.ToString()
      $stderr = $stderrBuilder.ToString()
      $stamp = (Get-Date).ToString('u')
      [IO.File]::AppendAllText($log, "=== Attempt $stamp ===`n", [System.Text.UTF8Encoding]::new($true))
      if ($stdout) { [IO.File]::AppendAllText($log, $stdout, [System.Text.UTF8Encoding]::new($true)) }
      if ($stderr) { [IO.File]::AppendAllText($log, $stderr, [System.Text.UTF8Encoding]::new($true)) }
      $code = if ($timedOut) { 998 } else { $proc.ExitCode }
      return @{ Exit=$code; TimedOut=$timedOut }
    }

    $attempts = @()
    $maxRetries = [int]($task.max_retries)
    $backoffStart = [int]($task.backoff_sec)
    $backoffMax = [int]($task.backoff_max)
    $jitter = [int]($task.jitter_sec)
    $retryCodes = @($retryPolicy.RetryOnExitCodes)
    $attempt = [int]($task.attempt)
    $success = $false
    while ($true) {
      $attempt++
      $started = Get-Date
      $result = Invoke-Attempt -exe $exe -argv $argv -log $log -timeout $timeout
      $duration = (Get-Date) - $started
      $attempts += [pscustomobject]@{
        Attempt=$attempt
        Exit=$result.Exit
        DurationMs=[int]$duration.TotalMilliseconds
        Timestamp=$started.ToString('o')
        TimedOut=$result.TimedOut
      }
      if ($result.Exit -eq 0) { $success = $true; break }
      if ($attempt -ge $maxRetries -or -not ($retryCodes -contains $result.Exit)) { break }
      $sleep = [Math]::Min($backoffMax, $backoffStart * [Math]::Pow(2, $attempt-1)) + (Get-Random -Minimum 0 -Maximum $jitter)
      Start-Sleep -Seconds [int][Math]::Ceiling($sleep)
    }
    return [pscustomobject]@{
      Task=$task
      Attempts=$attempts
      Success=$success
      FinalExit=$attempts[-1].Exit
      Started=$attempts[0].Timestamp
      Ended=(Get-Date).ToString('o')
    }
  }

  if (-not $job) { return $false }
  $entry.state = 'running'
  if (-not (Acquire-ToolLock $task.tool $job.Id)) {
    Write-Log "Failed to acquire tool lock for $($task.tool)" 'WARN' $task.id
    return $false
  }
  $runningJobs[$job.Id] = [pscustomobject]@{
    job=$job
    task=$task
    sourceFile=$entry.sourceFile
    started=Get-Date
    fileContext=$entry.fileContext
    entry=$entry
  }
  Update-RunningTasksFile
  return $true
}

function Complete-FileContext($ctx) {
  $source = Join-Path $processing $ctx.file
  $dest = if ($ctx.failures -gt 0) { Join-Path $failed $ctx.file } else { Join-Path $done $ctx.file }
  if (Test-Path $source) { Move-Item $source $dest -Force }
  if ($fileContexts.ContainsKey($ctx.file)) { $fileContexts.Remove($ctx.file) }
}

# One-time recovery pass remains (ensure cross-platform path)
& (Join-Path $PSScriptRoot 'RecoverProcessing.ps1') -TasksDir (Join-Path $Repo '.tasks') -StaleMinutes $policy.Queue.RecoveryProcessingStaleMinutes

Write-Log "QueueWorker starting. Repo=$Repo TasksDir=$TasksDir LogsDir=$LogsDir (MaxConcurrent=$maxConcurrent)"

$stopFile = Join-Path $Repo 'STOP.HEADLESS'

while ($true) {
  Write-Heartbeat
  Heal-GitRepo $Repo

  if (Test-Path $stopFile) { Write-Log 'Stop file detected; exiting.'; break }

  foreach ($jobId in @($runningJobs.Keys)) {
    $info = $runningJobs[$jobId]
    $job = $info.job
    if ($job.State -in @('Running','NotStarted')) { continue }
    $payload = Receive-Job -Job $job -ErrorAction SilentlyContinue
    Remove-Job -Job $job -Force | Out-Null
    Release-ToolLock $info.task.tool $jobId
    $runningJobs.Remove($jobId)
    Update-RunningTasksFile
    $info.fileContext.completed++
    if ($info.entry) { $info.entry.state = 'complete'; [void]$pendingTasks.Remove($info.entry) }

    if (-not $payload) {
      Write-Log "Task $($info.task.id) produced no payload" 'WARN' $info.task.id
      $taskResults[$info.task.id] = @{ success=$false; exit=1; reason='No payload' }
      Write-Ledger @{ ts=(Get-Date).ToString('o'); id=$info.task.id; tool=$info.task.tool; attempt=$info.task.attempt; exit=1; ok=$false; repo=$info.task.repo; note='No payload from job' }
      $info.fileContext.failures++
    }
    else {
      foreach ($attempt in $payload.Attempts) {
        Write-Ledger @{ ts=$attempt.Timestamp; id=$info.task.id; tool=$info.task.tool; attempt=$attempt.Attempt; exit=$attempt.Exit; ok=($attempt.Exit -eq 0); repo=$info.task.repo; duration_ms=$attempt.DurationMs }
      }
      Trip-Or-Reset-CB $info.task.tool $payload.Success
      $taskResults[$info.task.id] = @{ success=$payload.Success; exit=$payload.FinalExit }
      if ($payload.Attempts) { $info.task.attempt = ($payload.Attempts | Select-Object -Last 1).Attempt }
      if (-not $payload.Success) { $info.fileContext.failures++ }
      else { Schedule-RecurringTask $info.task }
    }

    if ($info.fileContext.completed -ge $info.fileContext.total) {
      Complete-FileContext $info.fileContext
    }
  }

  foreach ($entry in @($pendingTasks.ToArray())) {
    if ($entry.state -ne 'pending') { continue }
    $task = $entry.task
    if ($task.depends_on) {
      $blocked = $false
      foreach ($dep in $task.depends_on) {
        if ($taskResults.ContainsKey($dep)) {
          if (-not $taskResults[$dep].success) {
            Handle-DependencyFailure $task "Dependency $dep failed" $entry.fileContext $entry
            $entry.state = 'complete'
            $blocked = $true
            break
          }
        }
      }
      if ($blocked) { continue }
    }
  }

  $ready = @($pendingTasks | Where-Object { Is-TaskReady $_ }) | Sort-Object @{Expression = { -Get-TaskPriorityValue($_.task) }}, @{Expression = { $_.added }}
  foreach ($entry in $ready) {
    if ($runningJobs.Count -ge $maxConcurrent) { break }
    Start-TaskJob $entry | Out-Null
  }

  $file = Get-ChildItem $inbox -File -Filter *.jsonl -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -First 1
  if ($file) {
    $work = Join-Path $processing $file.Name
    try { Move-Item $file.FullName $work -Force } catch { }
    if (Test-Path $work) {
      try {
        $lines = Read-TaskFile $work
        $ctx = New-FileContext $file.Name $lines.Count
        $fileContexts[$file.Name] = $ctx
        $parseFailed = $false
        $quarantined = $false
        foreach ($line in $lines) {
          try {
            $task = Validate-Task (ConvertFrom-Json $line -ErrorAction Stop)
          }
          catch {
            Write-Log "Bad JSON in $($file.Name): $_" 'ERROR'
            Move-Item $work (Join-Path $failed $file.Name) -Force
            $parseFailed = $true
            break
          }
          if (Is-Broken $task.tool) {
            Move-Item $work (Join-Path $quarantine $file.Name) -Force
            Write-Log "Circuit breaker open for $($task.tool); quarantined $($file.Name)" 'WARN'
            $quarantined = $true
            break
          }
          Add-PendingTask $task $ctx | Out-Null
        }
        $ctx.total = $ctx.tasks.Count
        if ($parseFailed -or $quarantined) {
          if ($fileContexts.ContainsKey($file.Name)) { $fileContexts.Remove($file.Name) }
          continue
        }
        if ($ctx.total -eq 0) {
          Complete-FileContext $ctx
          continue
        }
      }
      catch {
        Write-Log "Failed to parse $($file.Name): $_" 'ERROR'
        Move-Item $work (Join-Path $failed $file.Name) -Force
      }
    }
  }
  elseif ($runningJobs.Count -eq 0 -and $pendingTasks.Count -eq 0) {
    Start-Sleep -Seconds $PollSeconds
  }
}

Write-JsonFile -Path $runningFile -Data @()
Write-Log 'QueueWorker stopped.'
