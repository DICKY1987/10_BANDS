



function Start-WtPane {
    <#
    .SYNOPSIS
        Starts a Windows Terminal pane with a specific command.
    .PARAMETER Title
        Title for the pane.
    .PARAMETER Command
        Command to execute inside pane.
    .PARAMETER IsFirstPane
        If set, launches new window; otherwise splits.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Command,
        [switch]$IsFirstPane,
        [string]$WorkingDirectory
    )
    $args = @()
    if ($IsFirstPane) {
        if ($WorkingDirectory) {
            $args += @('wt', '-w', '0', 'new-tab', '-d', $WorkingDirectory, 'powershell', '-NoExit', '-Command', $Command)
        } else {
            $args += @('wt', '-w', '0', 'new-tab', 'powershell', '-NoExit', '-Command', $Command)
        }
    } else {
        if ($WorkingDirectory) {
            $args += @('wt', '-w', '0', 'split-pane', '-H', '-d', $WorkingDirectory, 'powershell', '-NoExit', '-Command', $Command)
        } else {
            $args += @('wt', '-w', '0', 'split-pane', '-H', 'powershell', '-NoExit', '-Command', $Command)
        }
    }
    Write-AutomationLog -Level Info -Message "Launching Windows Terminal pane '$Title'"
    Start-Process -FilePath $args[0] -ArgumentList $args[1..($args.Length-1)] | Out-Null
}

function Wait-UntilReady {
    <#
    .SYNOPSIS
        Waits for a TCP port or a process to be ready.
    .PARAMETER TimeoutSeconds
        Max seconds to wait.
    .PARAMETER TestScript
        Custom readiness check returning $true|$false.
    #>
    [CmdletBinding()]
    param(
        [int]$TimeoutSeconds = 60,
        [scriptblock]$TestScript
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            if ($TestScript -and (& $TestScript)) { return $true }
        } catch {}
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Invoke-ToolInPane {
    <#
    .SYNOPSIS
        Orchestrates starting a tool in a WT pane with pre/post hooks.
    .PARAMETER Config
        Hashtable: Title, Cli, Args[], ReadyTest (scriptblock), LogPath.
    .PARAMETER IsFirstPane
        Start a fresh tab if true.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [switch]$IsFirstPane
    )
    $corr = New-CorrelationId
    $logPath = $null
    try {
        # Prepare log path
        if ($Config.LogPath) {
            $logPath = [IO.Path]::Combine($Config.LogPath, "$($Config.Title)-$(Get-Date -f 'yyyyMMdd_HHmmss').log")
            Start-TranscriptSafe -Path $logPath
        }
        # Dependency check
        $dep = Test-Dependency -Commands @('wt','powershell')
        if (-not $dep.IsSatisfied) { throw "Missing dependencies: $($dep.Missing -join ', ')" }

        $cmd = $Config.Cli
        if ($Config.Args) { $cmd += ' ' + ($Config.Args -join ' ') }

        Write-AutomationLog -Level Info -Message "Starting tool '$($Config.Title)'" -Data @{ Cmd = $cmd } -CorrelationId $corr

        Start-WtPane -Title $Config.Title -Command $cmd -IsFirstPane:$IsFirstPane -WorkingDirectory $Config.WorkingDirectory

        if ($Config.ReadyTest) {
            if (-not (Wait-UntilReady -TimeoutSeconds 60 -TestScript $Config.ReadyTest)) {
                throw "Readiness check for '$($Config.Title)' timed out."
            }
        }

        Write-AutomationLog -Level Info -Message "Tool '$($Config.Title)' is ready" -CorrelationId $corr
        return [PSCustomObject]@{ Title = $Config.Title; Transcript = $logPath; CorrelationId = $corr }
    } catch {
        Write-AutomationLog -Level Error -Message "Failed to start tool '$($Config.Title)'" -Exception $_ -CorrelationId $corr
        throw
    } finally {
        Stop-TranscriptSafe
    }
}

Export-ModuleMember -Function Start-WtPane, Wait-UntilReady, Invoke-ToolInPane

