# Orchestrator.ps1
#Requires -Version 5.1

param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'SharedConfig.psd1'),
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module -Force (Join-Path $PSScriptRoot 'AutomationSuite\AutomationSuite.psd1')
Import-Module -Force (Join-Path $PSScriptRoot 'IpcUtils\IpcUtils.psd1')

$corr = New-CorrelationId
try {
    $config = Get-AutomationConfig -Path $ConfigPath

    Write-AutomationLog -Level Info -Message "Starting orchestration" -CorrelationId $corr -Data @{
        Machine = $env:COMPUTERNAME
        User    = $env:USERNAME
    }

    if ($DryRun) {
        Write-AutomationLog -Level Info -Message "DryRun mode: evaluating steps only" -CorrelationId $corr
    }

    # Launch requested tools
    $userDir = 'C:\Users\Richard Wilks'
    $repoDir = 'C:\Users\Richard Wilks\CLI_RESTART'

    $tools = @(
        @{ # Claude
            Title            = 'Claude CLI'
            Cli              = "cd `"$repoDir`"; claude --dangerously-skip-permissions"
            LogPath          = $config.Logging.LogPath
            WorkingDirectory = $userDir
        },
        @{ # Codex
            Title            = 'Codex CLI'
            Cli              = "cd `"$repoDir`"; codex --sandbox danger-full-access --ask-for-approval never"
            LogPath          = $config.Logging.LogPath
            WorkingDirectory = $userDir
        },
        @{ # aider with DeepSeek via Ollama
            Title            = 'aider (deepseek-8b)'
            Cli              = "cd `"$repoDir`"; aider --model ollama/deepseek-coder:8b"
            LogPath          = $config.Logging.LogPath
            WorkingDirectory = $userDir
        }
    )

    if (-not $DryRun) {
        for ($i = 0; $i -lt $tools.Count; $i++) {
            $isFirst = ($i -eq 0)
            Invoke-ToolInPane -Config $tools[$i] -IsFirstPane:$isFirst | Out-Null
        }
    } else {
        $tools | ForEach-Object {
            Write-AutomationLog -Level Info -Message "DryRun: would start '$( $_.Title )' with: $( $_.Cli )" -CorrelationId $corr
        }
    }

    Write-AutomationLog -Level Info -Message "Orchestration complete" -CorrelationId $corr
    exit 0
} catch {
    # Prefer project error handler if available
    if (Get-Command -Name Invoke-AutomationErrorHandler -ErrorAction SilentlyContinue) {
        $err = Invoke-AutomationErrorHandler -Exception $_ -CorrelationId $corr -Source 'Orchestrator'
        exit ($err.ExitCode)
    } else {
        Write-Error $_
        exit 1
    }
}
