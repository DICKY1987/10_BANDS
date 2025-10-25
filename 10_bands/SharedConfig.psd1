@{
    ApplicationName = 'Enterprise Automation Suite'
    Version         = '2.2.0'
    Environment     = 'Production'
    # Default relative roots under the repository
    Paths = @{
        TasksRoot = '.tasks'
        LogsRoot  = 'logs'
        StateRoot = '.state'
    }
    Logging = @{
        Enabled        = $true
        DefaultLevel   = 'Info'
        # Use repo-relative logs folder by default; consumers should resolve to absolute
        LogPath        = 'logs'
    }
}
