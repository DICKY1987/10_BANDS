@{
    # Cross-platform default log path: use user temp
    LogPath = "$env:TEMP\10_BANDS\Logs"
    # Other shared configuration
    LogLevel = 'INFO'
    ToolWhitelist = @(
        # Default whitelist can be replaced by environment-specific config
        'aider.exe',
        'codex.exe',
        'claude.exe'
    )
    # Task queue paths
    TaskQueue = @{
        Inbox = "$env:TEMP\10_BANDS\tasks\inbox"
        Processing = "$env:TEMP\10_BANDS\tasks\processing"
        Done = "$env:TEMP\10_BANDS\tasks\done"
        Failed = "$env:TEMP\10_BANDS\tasks\failed"
    }
}