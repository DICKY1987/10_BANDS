# Tests/QueueWorker.GitBranchSafety.Tests.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe "QueueWorker Git Branch Safety" {
    BeforeAll {
        $root = Join-Path $PSScriptRoot '..'
        $workerScript = Join-Path $root 'scripts\QueueWorker.ps1'
        
        # Source the QueueWorker script to get access to Test-GitBranchSafety function
        # We need to extract just the function for testing
        $workerContent = Get-Content $workerScript -Raw
        
        # Extract and define the Test-GitBranchSafety function
        $functionMatch = $workerContent -match '(?ms)function Test-GitBranchSafety \{.*?\r?\n\}'
        if ($functionMatch) {
            $functionCode = $Matches[0]
            Invoke-Expression $functionCode
        } else {
            throw "Could not find Test-GitBranchSafety function in QueueWorker.ps1"
        }
    }

    Context "Safe git commands" {
        It "allows git status" {
            $result = Test-GitBranchSafety -GitArgs @('status')
            $result.Safe | Should -BeTrue
        }

        It "allows git add" {
            $result = Test-GitBranchSafety -GitArgs @('add', '.')
            $result.Safe | Should -BeTrue
        }

        It "allows git commit" {
            $result = Test-GitBranchSafety -GitArgs @('commit', '-m', 'test message')
            $result.Safe | Should -BeTrue
        }

        It "allows git checkout to existing branch" {
            $result = Test-GitBranchSafety -GitArgs @('checkout', 'main')
            $result.Safe | Should -BeTrue
        }

        It "allows git checkout -b with safe branch name" {
            $result = Test-GitBranchSafety -GitArgs @('checkout', '-b', 'feature/new-feature')
            $result.Safe | Should -BeTrue
        }

        It "allows git branch with safe branch name" {
            $result = Test-GitBranchSafety -GitArgs @('branch', 'feature/test')
            $result.Safe | Should -BeTrue
        }

        It "allows git branch deletion" {
            $result = Test-GitBranchSafety -GitArgs @('branch', '-d', 'rollback/test')
            $result.Safe | Should -BeTrue
        }

        It "allows git push to safe branch" {
            $result = Test-GitBranchSafety -GitArgs @('push', 'origin', 'main')
            $result.Safe | Should -BeTrue
        }

        It "allows git push with safe refspec" {
            $result = Test-GitBranchSafety -GitArgs @('push', 'origin', 'HEAD:refs/heads/feature/test')
            $result.Safe | Should -BeTrue
        }

        It "allows git pull" {
            $result = Test-GitBranchSafety -GitArgs @('pull', 'origin', 'main')
            $result.Safe | Should -BeTrue
        }

        It "allows git fetch" {
            $result = Test-GitBranchSafety -GitArgs @('fetch', 'origin')
            $result.Safe | Should -BeTrue
        }

        It "allows git log" {
            $result = Test-GitBranchSafety -GitArgs @('log', '--oneline')
            $result.Safe | Should -BeTrue
        }
    }

    Context "Dangerous git checkout commands" {
        It "blocks git checkout -b rollback/main/timestamp" {
            $result = Test-GitBranchSafety -GitArgs @('checkout', '-b', 'rollback/main/20251025_120000')
            $result.Safe | Should -BeFalse
            $result.Reason | Should -Match "rollback/"
            $result.Reason | Should -Match "not allowed"
        }

        It "blocks git checkout -b rollback/feature" {
            $result = Test-GitBranchSafety -GitArgs @('checkout', '-b', 'rollback/feature')
            $result.Safe | Should -BeFalse
            $result.Reason | Should -Match "rollback/"
        }

        It "blocks git checkout -b rollback" {
            $result = Test-GitBranchSafety -GitArgs @('checkout', '-b', 'rollback/test')
            $result.Safe | Should -BeFalse
        }
    }

    Context "Dangerous git branch commands" {
        It "blocks git branch rollback/main" {
            $result = Test-GitBranchSafety -GitArgs @('branch', 'rollback/main')
            $result.Safe | Should -BeFalse
            $result.Reason | Should -Match "rollback/"
            $result.Reason | Should -Match "not allowed"
        }

        It "blocks git branch rollback/feature/test" {
            $result = Test-GitBranchSafety -GitArgs @('branch', 'rollback/feature/test')
            $result.Safe | Should -BeFalse
        }
    }

    Context "Dangerous git push commands" {
        It "blocks git push origin rollback/main" {
            $result = Test-GitBranchSafety -GitArgs @('push', 'origin', 'rollback/main')
            $result.Safe | Should -BeFalse
            $result.Reason | Should -Match "rollback/"
            $result.Reason | Should -Match "not allowed"
        }

        It "blocks git push origin HEAD:refs/heads/rollback/test" {
            $result = Test-GitBranchSafety -GitArgs @('push', 'origin', 'HEAD:refs/heads/rollback/test')
            $result.Safe | Should -BeFalse
            $result.Reason | Should -Match "rollback/"
        }

        It "blocks git push origin refs/heads/rollback/main" {
            $result = Test-GitBranchSafety -GitArgs @('push', 'origin', 'refs/heads/rollback/main')
            $result.Safe | Should -BeFalse
            $result.Reason | Should -Match "rollback/"
        }

        It "blocks git push with rollback refspec from feature branch" {
            $result = Test-GitBranchSafety -GitArgs @('push', 'origin', 'feature:refs/heads/rollback/backup')
            $result.Safe | Should -BeFalse
        }

        It "blocks git push to rollback remote ref" {
            $result = Test-GitBranchSafety -GitArgs @('push', 'origin', 'HEAD:refs/remotes/origin/rollback/test')
            $result.Safe | Should -BeFalse
        }
    }

    Context "Edge cases" {
        It "allows empty args array" {
            $result = Test-GitBranchSafety -GitArgs @()
            $result.Safe | Should -BeTrue
        }

        It "allows branch name containing 'rollback' but not starting with it" {
            $result = Test-GitBranchSafety -GitArgs @('checkout', '-b', 'feature/rollback-support')
            $result.Safe | Should -BeTrue
        }

        It "allows branch name containing 'rollback' in middle" {
            $result = Test-GitBranchSafety -GitArgs @('branch', 'my-rollback-branch')
            $result.Safe | Should -BeTrue
        }

        It "blocks checkout -b with rollback even with additional flags" {
            $result = Test-GitBranchSafety -GitArgs @('checkout', '-b', 'rollback/test', '--track', 'origin/main')
            $result.Safe | Should -BeFalse
        }

        It "allows checkout without -b flag to rollback branch (switching to existing)" {
            $result = Test-GitBranchSafety -GitArgs @('checkout', 'rollback/existing')
            $result.Safe | Should -BeTrue
        }
    }
}
