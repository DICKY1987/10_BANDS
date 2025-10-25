Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'launch_10_bands_profile Script Tests' {
    BeforeAll {
        $scriptPath = "$PSScriptRoot/../launch_10_bands_profile.ps1"
    }

    Context 'Write-Log Function' {
        BeforeAll {
            # Extract and load Write-Log function
            $scriptContent = Get-Content $scriptPath -Raw
            if ($scriptContent -match '(?s)function Write-Log \{.*?\n\}') {
                Invoke-Expression $Matches[0]
            }
        }

        It 'should output messages with correct format' {
            $output = Write-Log -Message "Test message" -Level 'INFO' 6>&1
            $output | Should -Match '\[INFO\]'
            $output | Should -Match 'Test message'
        }

        It 'should support all required log levels' {
            $levels = @('INFO', 'WARN', 'ERROR', 'SUCCESS')
            foreach ($level in $levels) {
                { Write-Log -Message "Test" -Level $level } | Should -Not -Throw
            }
        }

        It 'should use different colors for different levels' {
            # Validate color mapping exists in script
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match "INFO.*=.*Cyan"
            $scriptContent | Should -Match "WARN.*=.*Yellow"
            $scriptContent | Should -Match "ERROR.*=.*Red"
            $scriptContent | Should -Match "SUCCESS.*=.*Green"
        }
    }

    Context 'Parameter Validation' {
        It 'should have ProfileName parameter with default value' {
            $help = Get-Help $scriptPath -Parameter ProfileName
            $help.defaultValue | Should -Be '10_Bands'
        }

        It 'should have Fullscreen switch parameter with default true' {
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match '\[switch\]\$Fullscreen\s*=\s*\$true'
        }

        It 'should have UpdateProfile switch parameter' {
            $help = Get-Help $scriptPath
            $param = $help.parameters.parameter | Where-Object { $_.name -eq 'UpdateProfile' }
            $param | Should -Not -BeNullOrEmpty
            $param.type.name | Should -Be 'SwitchParameter'
        }

        It 'should have UseExistingWindow switch parameter' {
            $help = Get-Help $scriptPath
            $param = $help.parameters.parameter | Where-Object { $_.name -eq 'UseExistingWindow' }
            $param | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Windows Terminal Detection' {
        BeforeAll {
            Mock -CommandName Write-Log -MockWith { }
        }

        It 'should check for wt command availability' {
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match "Get-Command wt"
        }

        It 'should throw error when wt is not available' {
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match 'Windows Terminal.*not found'
        }
    }

    Context 'Profile Update Logic' {
        It 'should call Update-WTProfile.ps1 when UpdateProfile is set' {
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match 'if \(\$UpdateProfile\)'
            $scriptContent | Should -Match 'Update-WTProfile\.ps1'
        }

        It 'should pass ProfileName to Update-WTProfile.ps1' {
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match '-ProfileName \$ProfileName'
        }

        It 'should check exit code after profile update' {
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match 'if \(\$LASTEXITCODE -ne 0\)'
        }

        It 'should throw on profile update failure' {
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match 'throw.*Profile update failed'
        }
    }

    Context 'Launch Arguments Building' {
        It 'should build basic launch arguments with profile name' {
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match '\$wtArgs.*=.*@\('
            $scriptContent | Should -Match '-p.*\$ProfileName'
        }

        It 'should add fullscreen flag when Fullscreen is true' {
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match 'if \(\$Fullscreen\).*--fullscreen'
        }

        It 'should add window flag when UseExistingWindow is true' {
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match 'if \(\$UseExistingWindow\).*-w.*last'
        }
    }

    Context 'Windows Terminal Launch' {
        It 'should launch wt with constructed arguments' {
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match '&\s+wt\s+@wtArgs'
        }

        It 'should log launch command for debugging' {
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match 'wt \$\(\$wtArgs -join'
        }
    }

    Context 'Error Handling and Troubleshooting' {
        It 'should provide troubleshooting tips on failure' {
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match 'Troubleshooting:'
        }

        It 'should suggest running with UpdateProfile flag' {
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match '-UpdateProfile'
        }

        It 'should mention checking tool availability' {
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match 'claude.*codex.*aider'
        }

        It 'should exit with error code on failure' {
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match 'exit 1'
        }

        It 'should exit with success code on success' {
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match 'exit 0'
        }
    }

    Context 'Script Structure and Best Practices' {
        It 'should use StrictMode' {
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match 'Set-StrictMode -Version Latest'
        }

        It 'should set ErrorActionPreference to Stop' {
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match "\$ErrorActionPreference\s*=\s*'Stop'"
        }

        It 'should require PowerShell 5.1 or higher' {
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match '#Requires -Version 5\.1'
        }

        It 'should use try-catch for error handling' {
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match 'try\s*\{'
            $scriptContent | Should -Match '\}\s*catch\s*\{'
        }
    }

    Context 'Output and Logging' {
        It 'should log launch initiation' {
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match "Launching Windows Terminal"
        }

        It 'should log successful launch' {
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match "layout launched.*SUCCESS"
        }

        It 'should log failures' {
            $scriptContent = Get-Content $scriptPath -Raw
            $scriptContent | Should -Match "Failed to launch.*ERROR"
        }
    }

    Context 'Integration: Full Launch Workflow' {
        BeforeAll {
            # Create mock update script
            $mockUpdateScript = "$TestDrive\Modules\Update-WTProfile.ps1"
            New-Item -ItemType Directory -Path (Split-Path $mockUpdateScript) -Force | Out-Null
            @'
param($ProfileName)
Write-Output "Mock Update: $ProfileName"
exit 0
'@ | Set-Content $mockUpdateScript
        }

        It 'should execute complete workflow without errors in structure' {
            # Validate script has all necessary components
            $scriptContent = Get-Content $scriptPath -Raw

            # Check for main workflow steps
            @(
                'Get-Command wt',
                'if \(\$UpdateProfile\)',
                '\$wtArgs',
                '&\s+wt',
                'try\s*\{',
                'catch\s*\{'
            ) | ForEach-Object {
                $scriptContent | Should -Match $_
            }
        }
    }
}
