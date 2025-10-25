Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Update-WTProfile' {
    BeforeAll {
        # Import the module for testing
        $modulePath = "$PSScriptRoot/../Modules/Update-WTProfile.ps1"

        # Mock environment to avoid actual file operations
        $script:mockSettingsPath = "$TestDrive\settings.json"
        $script:mockBackupDir = "$TestDrive\backups"

        # Create test settings.json
        $testSettings = @{
            profiles = @{
                list = @(
                    @{ name = "PowerShell"; commandline = "pwsh.exe" }
                )
            }
        }

        New-Item -ItemType Directory -Path (Split-Path $mockSettingsPath) -Force | Out-Null
        $testSettings | ConvertTo-Json -Depth 10 | Set-Content -Path $mockSettingsPath -Encoding UTF8
    }

    Context 'Get-WTSettingsPath' {
        BeforeAll {
            # Load functions by dot-sourcing with import flag
            $env:WT_PROFILE_IMPORT = '1'
            . "$PSScriptRoot/../Modules/Update-WTProfile.ps1"
            Remove-Item env:\WT_PROFILE_IMPORT -ErrorAction SilentlyContinue
        }

        It 'should find Windows Terminal settings.json when it exists' {
            Mock -CommandName Test-Path -MockWith { $true } -ParameterFilter {
                $Path -like "*WindowsTerminal*settings.json"
            }

            $result = Get-WTSettingsPath
            $result | Should -Match "settings.json"
        }

        It 'should throw when no settings.json found' {
            Mock -CommandName Test-Path -MockWith { $false }

            { Get-WTSettingsPath } | Should -Throw "*not found*"
        }

        It 'should check stable, preview, and unpackaged locations in order' {
            Mock -CommandName Test-Path -MockWith {
                param($Path)
                $Path -like "*WindowsTerminalPreview*"
            }

            $result = Get-WTSettingsPath
            $result | Should -Match "WindowsTerminalPreview"
        }
    }

    Context 'Backup-WTSettings' {
        BeforeAll {
            $env:WT_PROFILE_IMPORT = '1'
            . "$PSScriptRoot/../Modules/Update-WTProfile.ps1"
            Remove-Item env:\WT_PROFILE_IMPORT -ErrorAction SilentlyContinue
        }

        It 'should create backup directory if it does not exist' {
            $testSettings = @{ test = "data" }
            $testPath = "$TestDrive\test_settings.json"
            $testSettings | ConvertTo-Json | Set-Content $testPath

            $backupPath = Backup-WTSettings -SettingsPath $testPath

            Test-Path (Split-Path $backupPath) | Should -BeTrue
        }

        It 'should create timestamped backup file' {
            $testSettings = @{ test = "data" }
            $testPath = "$TestDrive\test_settings2.json"
            $testSettings | ConvertTo-Json | Set-Content $testPath

            $backupPath = Backup-WTSettings -SettingsPath $testPath

            $backupPath | Should -Match "settings_backup_\d{8}_\d{6}\.json"
            Test-Path $backupPath | Should -BeTrue
        }

        It 'should copy settings content to backup' {
            $testSettings = @{ unique = "content123" }
            $testPath = "$TestDrive\test_settings3.json"
            $testSettings | ConvertTo-Json | Set-Content $testPath

            $backupPath = Backup-WTSettings -SettingsPath $testPath

            $backupContent = Get-Content $backupPath -Raw | ConvertFrom-Json
            $backupContent.unique | Should -Be "content123"
        }
    }

    Context 'Build-StartupActions' {
        BeforeAll {
            $env:WT_PROFILE_IMPORT = '1'
            . "$PSScriptRoot/../Modules/Update-WTProfile.ps1"
            Remove-Item env:\WT_PROFILE_IMPORT -ErrorAction SilentlyContinue
        }

        It 'should escape backslashes in repo path' {
            $repo = 'C:\Users\Test\Project'
            $actions = Build-StartupActions -Repo $repo

            $actions | Should -Match 'C:\\\\Users\\\\Test\\\\Project'
        }

        It 'should include all 10 pane titles' {
            $repo = 'C:\TestRepo'
            $actions = Build-StartupActions -Repo $repo

            $expectedTitles = @(
                'Claude', 'Codex-1', 'Codex-2', 'Codex-3',
                'aider-file_mod-1', 'aider-file_mod-2', 'aider-file_mod-3',
                'aider-error_fix-1', 'aider-error_fix-2', 'aider-error_fix-3'
            )

            foreach ($title in $expectedTitles) {
                $actions | Should -Match [regex]::Escape($title)
            }
        }

        It 'should include correct split-pane commands' {
            $repo = 'C:\TestRepo'
            $actions = Build-StartupActions -Repo $repo

            # Should have 1 vertical split and 8 horizontal splits
            ($actions | Select-String -Pattern 'split-pane -V' -AllMatches).Matches.Count | Should -Be 1
            ($actions | Select-String -Pattern 'split-pane -H' -AllMatches).Matches.Count | Should -Be 8
        }

        It 'should include correct move-focus commands' {
            $repo = 'C:\TestRepo'
            $actions = Build-StartupActions -Repo $repo

            $actions | Should -Match 'move-focus left'
            $actions | Should -Match 'move-focus right'
            ($actions | Select-String -Pattern 'move-focus up' -AllMatches).Matches.Count | Should -Be 6
        }

        It 'should suppress application title for all panes' {
            $repo = 'C:\TestRepo'
            $actions = Build-StartupActions -Repo $repo

            ($actions | Select-String -Pattern '--suppressApplicationTitle' -AllMatches).Matches.Count | Should -Be 10
        }
    }

    Context 'Update-WTProfile' {
        BeforeAll {
            $env:WT_PROFILE_IMPORT = '1'
            . "$PSScriptRoot/../Modules/Update-WTProfile.ps1"
            Remove-Item env:\WT_PROFILE_IMPORT -ErrorAction SilentlyContinue
        }

        It 'should create new profile when it does not exist' {
            $testSettings = @{
                profiles = @{
                    list = @()
                }
            }
            $testPath = "$TestDrive\new_profile_test.json"
            $testSettings | ConvertTo-Json -Depth 10 | Set-Content $testPath

            $startupActions = "test-actions"
            $result = Update-WTProfile -SettingsPath $testPath -ProfileName "TestProfile" -StartupActions $startupActions

            $profile = $result.profiles.list | Where-Object { $_.name -eq "TestProfile" }
            $profile | Should -Not -BeNullOrEmpty
            $profile.startupActions | Should -Be "test-actions"
        }

        It 'should update existing profile when it exists' {
            $testSettings = @{
                profiles = @{
                    list = @(
                        @{ name = "TestProfile"; startupActions = "old-actions" }
                    )
                }
            }
            $testPath = "$TestDrive\update_profile_test.json"
            $testSettings | ConvertTo-Json -Depth 10 | Set-Content $testPath

            $result = Update-WTProfile -SettingsPath $testPath -ProfileName "TestProfile" -StartupActions "new-actions"

            $profile = $result.profiles.list | Where-Object { $_.name -eq "TestProfile" }
            $profile.startupActions | Should -Be "new-actions"
            $result.profiles.list.Count | Should -Be 1  # Should not duplicate
        }

        It 'should enable persisted layout when switch is set' {
            $testSettings = @{
                profiles = @{ list = @() }
            }
            $testPath = "$TestDrive\persisted_test.json"
            $testSettings | ConvertTo-Json -Depth 10 | Set-Content $testPath

            $result = Update-WTProfile -SettingsPath $testPath -ProfileName "Test" -StartupActions "actions" -EnablePersistedLayout

            $result.firstWindowPreference | Should -Be "persistedWindowLayout"
        }

        It 'should set profile as default when switch is set' {
            $testSettings = @{
                profiles = @{ list = @() }
            }
            $testPath = "$TestDrive\default_test.json"
            $testSettings | ConvertTo-Json -Depth 10 | Set-Content $testPath

            $result = Update-WTProfile -SettingsPath $testPath -ProfileName "DefaultProfile" -StartupActions "actions" -SetAsDefault

            $result.defaultProfile | Should -Be "DefaultProfile"
        }

        It 'should set launchMode to fullscreen' {
            $testSettings = @{
                profiles = @{ list = @() }
            }
            $testPath = "$TestDrive\launch_mode_test.json"
            $testSettings | ConvertTo-Json -Depth 10 | Set-Content $testPath

            $result = Update-WTProfile -SettingsPath $testPath -ProfileName "Test" -StartupActions "actions"

            $result.launchMode | Should -Be "fullscreen"
        }

        It 'should add icon to new profile' {
            $testSettings = @{
                profiles = @{ list = @() }
            }
            $testPath = "$TestDrive\icon_test.json"
            $testSettings | ConvertTo-Json -Depth 10 | Set-Content $testPath

            $result = Update-WTProfile -SettingsPath $testPath -ProfileName "IconTest" -StartupActions "actions"

            $profile = $result.profiles.list | Where-Object { $_.name -eq "IconTest" }
            $profile.icon | Should -Match "ms-appx://.*\.png"
        }
    }

    Context 'Test-JsonValid' {
        BeforeAll {
            $env:WT_PROFILE_IMPORT = '1'
            . "$PSScriptRoot/../Modules/Update-WTProfile.ps1"
            Remove-Item env:\WT_PROFILE_IMPORT -ErrorAction SilentlyContinue
        }

        It 'should return true for valid JSON' {
            $validJson = '{"test": "value", "number": 123}'
            Test-JsonValid -Json $validJson | Should -BeTrue
        }

        It 'should return false for invalid JSON' {
            $invalidJson = '{"test": "value", "number": }'
            Test-JsonValid -Json $invalidJson | Should -BeFalse
        }

        It 'should return true for complex nested JSON' {
            $complexJson = @{
                profiles = @{
                    list = @(
                        @{ name = "test"; nested = @{ deep = "value" } }
                    )
                }
            } | ConvertTo-Json -Depth 10

            Test-JsonValid -Json $complexJson | Should -BeTrue
        }
    }

    Context 'Integration: Full Profile Update Workflow' {
        BeforeAll {
            $env:WT_PROFILE_IMPORT = '1'
            . "$PSScriptRoot/../Modules/Update-WTProfile.ps1"
            Remove-Item env:\WT_PROFILE_IMPORT -ErrorAction SilentlyContinue
        }

        It 'should successfully create complete profile with all features' {
            $testSettings = @{
                profiles = @{
                    list = @(
                        @{ name = "ExistingProfile"; commandline = "cmd.exe" }
                    )
                }
            }
            $testPath = "$TestDrive\integration_test.json"
            $testSettings | ConvertTo-Json -Depth 10 | Set-Content $testPath

            $repo = "C:\TestRepo"
            $startupActions = Build-StartupActions -Repo $repo
            $result = Update-WTProfile `
                -SettingsPath $testPath `
                -ProfileName "10_Bands" `
                -StartupActions $startupActions `
                -EnablePersistedLayout `
                -SetAsDefault

            # Validate profile exists
            $profile = $result.profiles.list | Where-Object { $_.name -eq "10_Bands" }
            $profile | Should -Not -BeNullOrEmpty

            # Validate startup actions
            $profile.startupActions | Should -Not -BeNullOrEmpty
            $profile.startupActions | Should -Match "Claude"
            $profile.startupActions | Should -Match "codex"
            $profile.startupActions | Should -Match "aider"

            # Validate global settings
            $result.firstWindowPreference | Should -Be "persistedWindowLayout"
            $result.defaultProfile | Should -Be "10_Bands"
            $result.launchMode | Should -Be "fullscreen"

            # Validate JSON is valid
            $json = $result | ConvertTo-Json -Depth 10
            Test-JsonValid -Json $json | Should -BeTrue

            # Validate existing profile was not removed
            $existing = $result.profiles.list | Where-Object { $_.name -eq "ExistingProfile" }
            $existing | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Error Handling' {
        BeforeAll {
            $env:WT_PROFILE_IMPORT = '1'
            . "$PSScriptRoot/../Modules/Update-WTProfile.ps1"
            Remove-Item env:\WT_PROFILE_IMPORT -ErrorAction SilentlyContinue
        }

        It 'should handle missing profiles structure gracefully' {
            $testSettings = @{}
            $testPath = "$TestDrive\missing_structure_test.json"
            $testSettings | ConvertTo-Json -Depth 10 | Set-Content $testPath

            $result = Update-WTProfile -SettingsPath $testPath -ProfileName "Test" -StartupActions "actions"

            $result.profiles | Should -Not -BeNullOrEmpty
            $result.profiles.list | Should -Not -BeNullOrEmpty
        }

        It 'should handle missing profiles.list gracefully' {
            $testSettings = @{
                profiles = @{}
            }
            $testPath = "$TestDrive\missing_list_test.json"
            $testSettings | ConvertTo-Json -Depth 10 | Set-Content $testPath

            $result = Update-WTProfile -SettingsPath $testPath -ProfileName "Test" -StartupActions "actions"

            $result.profiles.list | Should -Not -BeNullOrEmpty
        }
    }
}
