# 10_bands Test Suite

Comprehensive unit tests for the 10_bands multi-pane development environment.

## Test Files

### Core Layout Tests
- **WT-10Pane-Layout.Tests.ps1** - Tests for the core 10-pane layout builder
  - Validates pane count, titles, and splitting logic
  - Tests move-focus choreography
  - Verifies tool command integration
  - Validates argument quoting and path handling

### Profile Management Tests
- **Update-WTProfile.Tests.ps1** - Tests for Windows Terminal profile management
  - Settings.json location detection
  - Backup functionality
  - Startup actions generation
  - Profile creation and updates
  - JSON validation

### Setup Tests
- **setup_profile.Tests.ps1** - Tests for one-time profile setup script
  - Parameter validation
  - Tool availability detection
  - Desktop shortcut creation
  - Integration workflow

### Launch Tests
- **launch_10_bands_profile.Tests.ps1** - Tests for profile-based launcher
  - Windows Terminal detection
  - Argument building
  - Profile update integration
  - Error handling and troubleshooting

### AutomationSuite Tests
- **AutomationSuite.Tests.ps1** - Tests for background job management module
  - Job creation and lifecycle
  - Output tagging and monitoring
  - Color-coded logging
  - Multi-job concurrency

## Running Tests

### Run All Tests
```powershell
Invoke-Pester -Path "C:\Users\Richard Wilks\CLI_RESTART\10_bands\Tests"
```

### Run Specific Test File
```powershell
Invoke-Pester -Path "C:\Users\Richard Wilks\CLI_RESTART\10_bands\Tests\WT-10Pane-Layout.Tests.ps1"
```

### Run with Coverage
```powershell
$config = New-PesterConfiguration
$config.Run.Path = "C:\Users\Richard Wilks\CLI_RESTART\10_bands\Tests"
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = "C:\Users\Richard Wilks\CLI_RESTART\10_bands\**\*.ps1", "C:\Users\Richard Wilks\CLI_RESTART\10_bands\**\*.psm1"
Invoke-Pester -Configuration $config
```

### Run with Detailed Output
```powershell
Invoke-Pester -Path "C:\Users\Richard Wilks\CLI_RESTART\10_bands\Tests" -Output Detailed
```

## Test Coverage

| Component | Test File | Coverage |
|-----------|-----------|----------|
| WT-10Pane-Layout.ps1 | WT-10Pane-Layout.Tests.ps1 | Full |
| Update-WTProfile.ps1 | Update-WTProfile.Tests.ps1 | Full |
| setup_profile.ps1 | setup_profile.Tests.ps1 | Full |
| launch_10_bands_profile.ps1 | launch_10_bands_profile.Tests.ps1 | Full |
| AutomationSuite.psm1 | AutomationSuite.Tests.ps1 | Full |

## Test Categories

### Unit Tests
- Function-level testing with mocks
- Parameter validation
- Error handling
- Edge cases

### Integration Tests
- End-to-end workflow validation
- Multi-component interaction
- Real command execution (where safe)

### Structural Tests
- Code structure validation
- Best practices compliance
- Script metadata verification

## Prerequisites

- **Pester 5.0+**: PowerShell testing framework
  ```powershell
  Install-Module -Name Pester -Force -SkipPublisherCheck
  ```

## CI/CD Integration

These tests are designed to run in CI/CD pipelines:

```yaml
# Example GitHub Actions
- name: Run Pester Tests
  shell: pwsh
  run: |
    Invoke-Pester -Path "10_bands/Tests" -Output Detailed -CI
```

## Troubleshooting

### Tests Fail to Import Functions
Ensure import flags are set correctly:
```powershell
$env:WT_LAYOUT_IMPORT = '1'
$env:WT_PROFILE_IMPORT = '1'
```

### Mock Issues
If mocks aren't working, ensure Pester version is 5.0+:
```powershell
Get-Module Pester -ListAvailable
```

### Path Issues
Tests use `$TestDrive` for isolated temporary files. Ensure Pester can create temp directories.

## Contributing

When adding new components to 10_bands:

1. Create corresponding test file in `Tests/` directory
2. Follow naming convention: `ComponentName.Tests.ps1`
3. Include unit, integration, and structural tests
4. Aim for 80%+ code coverage
5. Update this README with test file information
