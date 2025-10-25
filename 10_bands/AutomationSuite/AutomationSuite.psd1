@{
    RootModule        = 'AutomationSuite.psm1'
    ModuleVersion     = '2.2.0'
    GUID              = '6f2b8a9b-1f2c-4f7f-9fd1-7d10a8e2a111'
    Author            = 'Enterprise Automation Team'
    Description       = 'Shared utilities: config, logging, retry, transcript.'
    FunctionsToExport = @(
        'Write-AutomationLog',
        'Start-AutomationCliJob',
        'Get-ToolColor'
    )
    PowerShellVersion = '5.1'
}
