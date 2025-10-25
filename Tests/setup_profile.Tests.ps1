# Pester v5-style test file (focused on the previously failing regex)
Import-Module -Force -Name "$PSScriptRoot/../AutomationSuite/AutomationSuite.psd1"

Describe "setup_profile Script Tests" {
    It "should set ErrorActionPreference to Stop" {
        # Example: check that script sets ErrorActionPreference
        $scriptContent = Get-Content -Path "$PSScriptRoot/../Modules/Update-WTProfile.ps1" -Raw -ErrorAction Stop
        # The regex must match the literal assignment: Continue = 'Stop' (escaped single quotes)
        $pattern = "Continue\s*=\s*'Stop'"
        $scriptContent | Should -Match $pattern
    }
}