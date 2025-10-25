# Example plugin demonstrating custom tool integration.
param()

return [pscustomobject]@{
    Name = 'Example Echo Plugin'
    Tool = 'echo-demo'
    Description = 'Writes a message using PowerShell.''s Write-Output.'
    ResolveCommand = {
        param($task,$promptFile)
        $message = $task.message
        if (-not $message) {
            $message = "Plugin task $($task.id) executed at $(Get-Date -Format 'u')"
        }
        $escaped = $message.Replace('"', '\"')
        return [pscustomobject]@{
            Executable = 'pwsh'
            Arguments  = @('-NoProfile','-Command',"Write-Output \"$escaped\"")
        }
    }
}
