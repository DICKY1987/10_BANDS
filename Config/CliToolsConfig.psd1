@{
  Tools = @(
    # Git – periodic fetch + status (headless)
    @{
      Name = 'GitStatusLoop'
      Path = 'pwsh'
      Arguments = @(
        '-NoProfile','-Command', @'
param($Repo = "C:\Users\Richard Wilks\CLI_RESTART", $Interval=60)
Set-Location $Repo
Write-Output "GitStatusLoop started for $Repo. Interval=$Interval sec"
while ($true) {
  try {
    git fetch --all --prune 2>&1 | ForEach-Object { "fetch: $_" }
    $branch = (git rev-parse --abbrev-ref HEAD).Trim()
    $sha    = (git rev-parse --short HEAD).Trim()
    $stat   = (git status -sb).Trim()
    Write-Output ("git: branch={0} sha={1} status={2}" -f $branch,$sha,$stat)
  } catch { Write-Output ("git: ERROR {0}" -f $_.Exception.Message) }
  Start-Sleep -Seconds $Interval
}
'@
      )
      Color = 'Cyan'
    }

    # Example host health ping
    @{
      Name='HostHealth'
      Path='pwsh'
      Arguments=@('-NoProfile','-Command', @'
while ($true) { $free=(Get-PSDrive C).Free/1GB; Write-Output ("health: C: {0:N1} GB free" -f $free); Start-Sleep -Seconds 120 }
'@)
      Color='Green'
    }

    # Stubs for AI CLIs as *batch workers* (replace with your non-interactive entrypoints)
    @{ Name='ClaudeWorker'; Path='pwsh'; Arguments=@('-NoProfile','-Command','Write-Output "claude: worker stub"'); Color='Yellow' }
    @{ Name='CodexWorker' ; Path='pwsh'; Arguments=@('-NoProfile','-Command','Write-Output "codex: worker stub"') ; Color='Magenta' }
    @{ Name='AiderWorker' ; Path='pwsh'; Arguments=@('-NoProfile','-Command','Write-Output "aider: worker stub"') ; Color='Blue' }
  )
  MonitorRefreshRateMs = 200
  DefaultOutputColor   = 'Gray'
}
