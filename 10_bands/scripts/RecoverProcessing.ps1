# scripts/RecoverProcessing.ps1
param(
  [string]$TasksDir = (Join-Path $PSScriptRoot '..\.tasks'),
  [int]$StaleMinutes = 10
)
$processing = Join-Path $TasksDir 'processing'
$inbox      = Join-Path $TasksDir 'inbox'
$now = Get-Date
Get-ChildItem $processing -File -Filter *.jsonl -ErrorAction SilentlyContinue | ForEach-Object{
  if (($now - $_.LastWriteTime).TotalMinutes -ge $StaleMinutes) {
    Move-Item $_.FullName (Join-Path $inbox $_.Name) -Force
  }
}
