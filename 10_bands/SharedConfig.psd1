@{
    ApplicationName = 'Enterprise Automation Suite'
    Version         = '2.2.0'
    Environment     = 'Production'
    Logging = @{
        Enabled        = $true
        DefaultLevel   = 'Info'
        LogPath        = 'C:\Automation\Logs'
    }
}
