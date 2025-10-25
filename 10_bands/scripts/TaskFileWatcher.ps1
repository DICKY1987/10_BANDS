param(
    [string]$WatchPath = (Join-Path (Join-Path $PSScriptRoot '..') 'src'),
    [string]$TasksDir = (Join-Path (Join-Path $PSScriptRoot '..') '.tasks'),
    [string]$Tool = 'git',
    [string[]]$Args = @('status','-sb'),
    [int]$DebounceSeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$watchRoot = [System.IO.Path]::GetFullPath($WatchPath)
$tasksRoot = [System.IO.Path]::GetFullPath($TasksDir)
$inbox = Join-Path $tasksRoot 'inbox'
New-Item -ItemType Directory -Force -Path $inbox | Out-Null

$watcher = New-Object System.IO.FileSystemWatcher $watchRoot
$watcher.IncludeSubdirectories = $true
$watcher.EnableRaisingEvents = $true
$subscriptions = @()

Write-Host "Watching $watchRoot (debounce $DebounceSeconds s)"

$timer = New-Object System.Timers.Timer ($DebounceSeconds * 1000)
$timer.AutoReset = $false
$enqueueAction = {
    $task = @{ id = (Get-Date).ToString('yyyyMMddHHmmss'); tool = $Tool; args = $Args }
    $file = Join-Path $inbox ("watch_{0}.jsonl" -f $task.id)
    [System.IO.File]::WriteAllText($file, ($task | ConvertTo-Json -Compress) + "`n", [System.Text.UTF8Encoding]::new($true))
    Write-Host "Enqueued task $($task.id) after changes"
}.GetNewClosure()
$timer.add_Elapsed($enqueueAction)
$restartAction = { $timer.Stop(); $timer.Start() }.GetNewClosure()
$subscriptions += Register-ObjectEvent -InputObject $watcher -EventName Changed -Action $restartAction
$subscriptions += Register-ObjectEvent -InputObject $watcher -EventName Created -Action $restartAction
$subscriptions += Register-ObjectEvent -InputObject $watcher -EventName Deleted -Action $restartAction

try {
    while ($true) { Start-Sleep -Seconds 1 }
}
finally {
    foreach ($sub in $subscriptions) { Unregister-Event -SubscriptionId $sub.Id }
    $watcher.Dispose()
    $timer.Stop()
    $timer.Dispose()
}
