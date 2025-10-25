Describe "Headless policies" {
  It "defines MaxConcurrentTasks" {
    $root = Join-Path $PSScriptRoot '..'
    $policy = Import-PowerShellDataFile (Join-Path $root 'Config/HeadlessPolicies.psd1')
    $policy.Queue.MaxConcurrentTasks | Should -BeGreaterThan 0
  }
}
