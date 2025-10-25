@{
    RootModule        = 'AutomationCore.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'f1a2b3c4-d5e6-4a2b-98c0-123456789abc'
    Author            = '10_BANDS Team'
    Description       = 'Domain core functions for the 10_BANDS orchestrator.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Get-ToolColor','Write-AutomationLog','Start-AutomationCliJob')
    PrivateData = @{
        PSData = @{
            Tags = @('domain','automation','core')
            LicenseUri = ''
            ProjectUri = 'https://github.com/DICKY1987/10_BANDS'
        }
    }
}
