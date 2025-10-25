@{
    RootModule        = 'AutomationSuite.psm1'
    ModuleVersion     = '2.2.1'
    GUID              = '6f2b8a9b-1f2c-4f7f-9fd1-7d10a8e2a111'
    Author            = 'Enterprise Automation Team'
    CompanyName       = 'Enterprise Automation Team'
    Copyright         = '(c) 2025 Enterprise Automation Team'
    Description       = 'Shared utilities: config, logging, retry, and job orchestration helpers.'
    FunctionsToExport = @('Write-AutomationLog','Start-AutomationCliJob','Get-ToolColor')
    PowerShellVersion = '5.1'
    RequiredModules   = @()
    PrivateData       = @{
        PSData = @{
            Tags        = @('automation','orchestration','tools','logging')
            ProjectUri  = 'https://github.com/DICKY1987/10_BANDS'
            LicenseUri  = 'https://opensource.org/licenses/MIT'
            ReleaseNotes = @{
                '2.2.1' = 'Added safer job startup validation, improved logging fallback'
            }
            HelpInfoURI = 'https://github.com/DICKY1987/10_BANDS/wiki'
        }
    }
}