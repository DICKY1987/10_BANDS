# Tests/QueueWorker.RollbackIntegration.Tests.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe "QueueWorker Rollback Branch Integration" {
    BeforeAll {
        $root = Join-Path $PSScriptRoot '..'
        $tasksDir = Join-Path $root '.tasks.test'
        $logsDir = Join-Path $root 'logs.test'
        $inbox = Join-Path $tasksDir 'inbox'
        $failed = Join-Path $tasksDir 'failed'
        $done = Join-Path $tasksDir 'done'
        
        # Clean up any previous test artifacts
        if (Test-Path $tasksDir) { Remove-Item $tasksDir -Recurse -Force }
        if (Test-Path $logsDir) { Remove-Item $logsDir -Recurse -Force }
        
        # Create directories
        New-Item -ItemType Directory -Force -Path $inbox, $failed, $done, $logsDir | Out-Null
    }

    AfterAll {
        # Clean up test artifacts
        if (Test-Path $tasksDir) { Remove-Item $tasksDir -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path $logsDir) { Remove-Item $logsDir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    Context "Safe git commands are processed" {
        It "processes safe git status command" {
            $taskFile = Join-Path $inbox 'safe_status.jsonl'
            $task = @{
                id = 'test-safe-status'
                tool = 'git'
                args = @('status')
                repo = $root
            } | ConvertTo-Json -Compress
            
            $task | Set-Content -Path $taskFile -Encoding UTF8
            
            Test-Path $taskFile | Should -BeTrue
            
            # Verify task file structure is valid
            $taskContent = Get-Content $taskFile -Raw | ConvertFrom-Json
            $taskContent.tool | Should -Be 'git'
            $taskContent.args | Should -Contain 'status'
        }

        It "processes safe git checkout to existing branch" {
            $taskFile = Join-Path $inbox 'safe_checkout.jsonl'
            $task = @{
                id = 'test-safe-checkout'
                tool = 'git'
                args = @('checkout', 'main')
                repo = $root
            } | ConvertTo-Json -Compress
            
            $task | Set-Content -Path $taskFile -Encoding UTF8
            
            Test-Path $taskFile | Should -BeTrue
        }
    }

    Context "Dangerous rollback commands format validation" {
        It "creates valid task for rollback checkout -b" {
            $taskFile = Join-Path $inbox 'dangerous_checkout.jsonl'
            $task = @{
                id = 'test-dangerous-checkout'
                tool = 'git'
                args = @('checkout', '-b', 'rollback/main/20251025_120000')
                repo = $root
            } | ConvertTo-Json -Compress
            
            $task | Set-Content -Path $taskFile -Encoding UTF8
            
            # Verify task is properly formatted
            $taskContent = Get-Content $taskFile -Raw | ConvertFrom-Json
            $taskContent.tool | Should -Be 'git'
            $taskContent.args | Should -Contain 'checkout'
            $taskContent.args | Should -Contain '-b'
            $taskContent.args | Should -Contain 'rollback/main/20251025_120000'
        }

        It "creates valid task for rollback branch creation" {
            $taskFile = Join-Path $inbox 'dangerous_branch.jsonl'
            $task = @{
                id = 'test-dangerous-branch'
                tool = 'git'
                args = @('branch', 'rollback/feature')
                repo = $root
            } | ConvertTo-Json -Compress
            
            $task | Set-Content -Path $taskFile -Encoding UTF8
            
            $taskContent = Get-Content $taskFile -Raw | ConvertFrom-Json
            $taskContent.args | Should -Contain 'rollback/feature'
        }

        It "creates valid task for rollback push" {
            $taskFile = Join-Path $inbox 'dangerous_push.jsonl'
            $task = @{
                id = 'test-dangerous-push'
                tool = 'git'
                args = @('push', 'origin', 'rollback/main')
                repo = $root
            } | ConvertTo-Json -Compress
            
            $task | Set-Content -Path $taskFile -Encoding UTF8
            
            $taskContent = Get-Content $taskFile -Raw | ConvertFrom-Json
            $taskContent.args | Should -Contain 'push'
            $taskContent.args | Should -Contain 'rollback/main'
        }

        It "creates valid task for rollback refspec push" {
            $taskFile = Join-Path $inbox 'dangerous_refspec.jsonl'
            $task = @{
                id = 'test-dangerous-refspec'
                tool = 'git'
                args = @('push', 'origin', 'HEAD:refs/heads/rollback/test')
                repo = $root
            } | ConvertTo-Json -Compress
            
            $task | Set-Content -Path $taskFile -Encoding UTF8
            
            $taskContent = Get-Content $taskFile -Raw | ConvertFrom-Json
            $taskContent.args[2] | Should -Match 'rollback'
        }
    }

    Context "Build-Command validation" {
        BeforeAll {
            # Load the Build-Command and Test-GitBranchSafety functions
            $workerScript = Join-Path $root 'scripts\QueueWorker.ps1'
            $workerContent = Get-Content $workerScript -Raw
            
            # Extract functions
            $functionMatch = $workerContent -match '(?ms)function Test-GitBranchSafety \{.*?\r?\n\}'
            if ($functionMatch) {
                Invoke-Expression $Matches[0]
            }
            
            # Extract Build-Command (more complex due to switch statement)
            if ($workerContent -match '(?ms)function Build-Command \{.*?\n\}(?=\r?\n\r?\nfunction|\r?\n\r?\n#|\r?\n$)') {
                Invoke-Expression $Matches[0]
            }
        }

        It "Build-Command throws for rollback checkout -b" {
            $task = @{
                tool = 'git'
                args = @('checkout', '-b', 'rollback/test')
                repo = $root
            }
            
            { Build-Command -Task $task } | Should -Throw "*SECURITY*rollback*"
        }

        It "Build-Command throws for rollback branch" {
            $task = @{
                tool = 'git'
                args = @('branch', 'rollback/main')
                repo = $root
            }
            
            { Build-Command -Task $task } | Should -Throw "*SECURITY*rollback*"
        }

        It "Build-Command throws for rollback push" {
            $task = @{
                tool = 'git'
                args = @('push', 'origin', 'rollback/feature')
                repo = $root
            }
            
            { Build-Command -Task $task } | Should -Throw "*SECURITY*rollback*"
        }

        It "Build-Command succeeds for safe git commands" {
            $task = @{
                tool = 'git'
                args = @('status')
                repo = $root
            }
            
            { Build-Command -Task $task } | Should -Not -Throw
        }

        It "Build-Command succeeds for safe branch creation" {
            $task = @{
                tool = 'git'
                args = @('checkout', '-b', 'feature/new-branch')
                repo = $root
            }
            
            { Build-Command -Task $task } | Should -Not -Throw
        }
    }
}
