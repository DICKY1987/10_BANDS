Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'AutomationSuite Module Tests' {
    BeforeAll {
        $modulePath = "$PSScriptRoot/../AutomationSuite/AutomationSuite.psm1"
        Import-Module $modulePath -Force
    }

    AfterAll {
        Remove-Module AutomationSuite -Force -ErrorAction SilentlyContinue
    }

    Context 'Write-AutomationLog Function' {
        It 'should be exported from module' {
            Get-Command Write-AutomationLog -Module AutomationSuite | Should -Not -BeNullOrEmpty
        }

        It 'should accept all required log levels' {
            $levels = @('Debug', 'Info', 'Warning', 'Error', 'Critical')
            foreach ($level in $levels) {
                { Write-AutomationLog -Level $level -Message "Test $level" } | Should -Not -Throw
            }
        }

        It 'should handle additional Data parameter' {
            $data = @{ Key1 = 'Value1'; Key2 = 123 }
            { Write-AutomationLog -Level Info -Message "Test" -Data $data } | Should -Not -Throw
        }

        It 'should handle Exception parameter' {
            $exception = New-Object System.Exception("Test exception")
            { Write-AutomationLog -Level Error -Message "Test" -Exception $exception } | Should -Not -Throw
        }

        It 'should handle CorrelationId parameter' {
            { Write-AutomationLog -Level Info -Message "Test" -CorrelationId "TEST123" } | Should -Not -Throw
        }

        It 'should output formatted log entry' {
            $output = Write-AutomationLog -Level Info -Message "Test message" 6>&1
            $output | Should -Match '\[INFO\s*\]'
            $output | Should -Match 'Test message'
        }
    }

    Context 'Start-AutomationCliJob Function' {
        It 'should be exported from module' {
            Get-Command Start-AutomationCliJob -Module AutomationSuite | Should -Not -BeNullOrEmpty
        }

        It 'should require ToolConfig parameter' {
            { Start-AutomationCliJob } | Should -Throw
        }

        It 'should start background job with valid config' {
            $config = @{
                Name = 'TestTool'
                Path = 'powershell.exe'
                Arguments = @('-Command', 'Write-Output "test"')
            }

            $job = Start-AutomationCliJob -ToolConfig $config
            $job | Should -Not -BeNullOrEmpty
            $job.State | Should -BeIn @('Running', 'Completed')
            $job.Name | Should -Be 'TestTool'

            # Cleanup
            Stop-Job $job -ErrorAction SilentlyContinue
            Remove-Job $job -Force -ErrorAction SilentlyContinue
        }

        It 'should tag output with tool name' {
            $config = @{
                Name = 'EchoTest'
                Path = 'powershell.exe'
                Arguments = @('-Command', 'Write-Output "Hello World"')
            }

            $job = Start-AutomationCliJob -ToolConfig $config
            Start-Sleep -Milliseconds 500
            $output = Receive-Job $job

            $output | Should -Match '^EchoTest:'

            # Cleanup
            Stop-Job $job -ErrorAction SilentlyContinue
            Remove-Job $job -Force -ErrorAction SilentlyContinue
        }

        It 'should handle errors within job gracefully' {
            $config = @{
                Name = 'FailTool'
                Path = 'nonexistent-command-12345.exe'
                Arguments = @()
            }

            $job = Start-AutomationCliJob -ToolConfig $config
            Start-Sleep -Milliseconds 500
            $output = Receive-Job $job 2>&1

            $output | Should -Match 'FailTool:.*JOB_ERROR'

            # Cleanup
            Stop-Job $job -ErrorAction SilentlyContinue
            Remove-Job $job -Force -ErrorAction SilentlyContinue
        }

        It 'should pass arguments to tool correctly' {
            $config = @{
                Name = 'ArgTest'
                Path = 'powershell.exe'
                Arguments = @('-Command', 'param($a, $b) Write-Output "$a-$b"', 'arg1', 'arg2')
            }

            $job = Start-AutomationCliJob -ToolConfig $config
            Start-Sleep -Milliseconds 500
            $output = Receive-Job $job

            $output | Should -Match 'arg1-arg2'

            # Cleanup
            Stop-Job $job -ErrorAction SilentlyContinue
            Remove-Job $job -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Get-ToolColor Function' {
        It 'should be exported from module' {
            Get-Command Get-ToolColor -Module AutomationSuite | Should -Not -BeNullOrEmpty
        }

        It 'should return color from color map when tool exists' {
            $colorMap = @{
                'Tool1' = 'Red'
                'Tool2' = 'Blue'
            }

            $color = Get-ToolColor -ToolName 'Tool1' -ColorMap $colorMap
            $color | Should -Be ([System.ConsoleColor]::Red)
        }

        It 'should return default color when tool not in map' {
            $colorMap = @{
                'Tool1' = 'Red'
            }

            $color = Get-ToolColor -ToolName 'UnknownTool' -ColorMap $colorMap -DefaultColor Gray
            $color | Should -Be ([System.ConsoleColor]::Gray)
        }

        It 'should handle invalid color gracefully' {
            $colorMap = @{
                'BadTool' = 'NotAValidColor'
            }

            $color = Get-ToolColor -ToolName 'BadTool' -ColorMap $colorMap -DefaultColor Gray
            $color | Should -Be ([System.ConsoleColor]::Gray)
        }

        It 'should support all valid ConsoleColor values' {
            $validColors = @('Black', 'DarkBlue', 'DarkGreen', 'DarkCyan', 'DarkRed',
                           'DarkMagenta', 'DarkYellow', 'Gray', 'DarkGray', 'Blue',
                           'Green', 'Cyan', 'Red', 'Magenta', 'Yellow', 'White')

            foreach ($colorName in $validColors) {
                $colorMap = @{ 'Test' = $colorName }
                $result = Get-ToolColor -ToolName 'Test' -ColorMap $colorMap
                $result | Should -BeOfType [System.ConsoleColor]
            }
        }
    }

    Context 'Module Export Validation' {
        It 'should export exactly three functions' {
            $exports = Get-Command -Module AutomationSuite
            $exports.Count | Should -Be 3
        }

        It 'should export Write-AutomationLog' {
            $exports = Get-Command -Module AutomationSuite
            $exports.Name | Should -Contain 'Write-AutomationLog'
        }

        It 'should export Start-AutomationCliJob' {
            $exports = Get-Command -Module AutomationSuite
            $exports.Name | Should -Contain 'Start-AutomationCliJob'
        }

        It 'should export Get-ToolColor' {
            $exports = Get-Command -Module AutomationSuite
            $exports.Name | Should -Contain 'Get-ToolColor'
        }
    }

    Context 'Integration: Complete Job Lifecycle' {
        It 'should execute complete job workflow with monitoring' {
            # Create tool config
            $config = @{
                Name = 'IntegrationTest'
                Path = 'powershell.exe'
                Arguments = @('-Command', 'Write-Output "Line1"; Start-Sleep -Milliseconds 100; Write-Output "Line2"')
            }

            # Start job
            $job = Start-AutomationCliJob -ToolConfig $config
            $job | Should -Not -BeNullOrEmpty

            # Wait for job to complete
            Wait-Job $job -Timeout 5 | Out-Null

            # Receive output
            $output = Receive-Job $job

            # Validate output
            $output | Should -HaveCount 2
            $output[0] | Should -Match 'IntegrationTest: Line1'
            $output[1] | Should -Match 'IntegrationTest: Line2'

            # Cleanup
            Remove-Job $job -Force
        }

        It 'should handle multiple concurrent jobs' {
            $jobs = @()

            for ($i = 1; $i -le 3; $i++) {
                $config = @{
                    Name = "ConcurrentJob$i"
                    Path = 'powershell.exe'
                    Arguments = @('-Command', "Write-Output 'Output from job $i'")
                }
                $jobs += Start-AutomationCliJob -ToolConfig $config
            }

            $jobs.Count | Should -Be 3

            # Wait for all jobs
            Wait-Job $jobs -Timeout 5 | Out-Null

            # Verify all completed
            foreach ($job in $jobs) {
                $job.State | Should -Be 'Completed'
            }

            # Cleanup
            Remove-Job $jobs -Force
        }
    }

    Context 'Error Handling and Edge Cases' {
        It 'should throw meaningful error for missing tool name' {
            $config = @{
                Path = 'powershell.exe'
                Arguments = @()
            }

            { Start-AutomationCliJob -ToolConfig $config } | Should -Throw
        }

        It 'should throw meaningful error for missing path' {
            $config = @{
                Name = 'NoPath'
                Arguments = @()
            }

            { Start-AutomationCliJob -ToolConfig $config } | Should -Throw
        }

        It 'should handle empty arguments array' {
            $config = @{
                Name = 'NoArgs'
                Path = 'powershell.exe'
                Arguments = @()
            }

            { Start-AutomationCliJob -ToolConfig $config } | Should -Not -Throw
        }
    }
}
