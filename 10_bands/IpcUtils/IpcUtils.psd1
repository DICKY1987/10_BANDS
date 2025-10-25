@{
    RootModule        = 'IpcUtils.psm1'
    ModuleVersion     = '2.2.0'
    GUID              = 'cb9b4d6b-e09d-4a2a-b8e6-19245e770abc'
    Author            = 'Enterprise Automation Team'
    Description       = 'Inter-process utilities with Windows Terminal orchestration.'
    FunctionsToExport = @(
        'Start-WtPane',
        'Wait-UntilReady',
        'Invoke-ToolInPane'
    )
    RequiredModules   = @('AutomationSuite')
    PowerShellVersion = '5.1'
}
