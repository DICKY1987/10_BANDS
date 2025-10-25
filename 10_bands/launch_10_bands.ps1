param([switch]$Fullscreen,[switch]$UseExistingWindow)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $here 'Modules\WT-10Pane-Layout.ps1'
& pwsh -NoProfile -ExecutionPolicy Bypass -File $script -Repo 'C:\Users\Richard Wilks\CLI_RESTART' -Fullscreen:$Fullscreen -UseExistingWindow:$UseExistingWindow
