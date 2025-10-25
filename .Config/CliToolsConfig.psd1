@{
    # Queue and runtime settings
    QueuePath   = Join-Path $env:TEMP "10_bands_queue"
    WorkerCount = 2

    # Tool registry (whitelist). Each entry should contain at least Name and Path.
    Tools = @{
        "aider" = @{
            Name = "aider"
            Path = "C:\Program Files\aider\aider.exe"  # adjust per environment
            ArgsTemplate = "--input {0} --output {1}"
        }
        "codex" = @{
            Name = "codex"
            Path = "C:\tools\codex\codex.exe"
            ArgsTemplate = "-in {0} -out {1}"
        }
        "claude" = @{
            Name = "claude"
            Path = "C:\tools\claude\claude.exe"
            ArgsTemplate = "--task {0}"
        }
    }

    # Logging settings
    LogPath = Join-Path $env:TEMP "10_bands_logs"
    LogLevel = "Information"
}