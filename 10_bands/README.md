# 10_BANDS - Multi-Pane AI Development Environment

A sophisticated 10-pane Windows Terminal layout orchestrating multiple AI CLI tools (Claude, Codex, Aider) for parallel development workflows.

## 🎯 What This Does

Creates a **2x5 grid layout** in Windows Terminal with:

### Left Column (File Modification Lane)
1. **Claude CLI** - Top pane
2. **Codex-1** - Code generation
3. **aider-file_mod-1** - File editing
4. **aider-file_mod-2** - File editing
5. **aider-file_mod-3** - File editing

### Right Column (Error Fix Lane)
6. **Codex-2** - Code generation
7. **Codex-3** - Code generation
8. **aider-error_fix-1** - Bug fixing
9. **aider-error_fix-2** - Bug fixing
10. **aider-error_fix-3** - Bug fixing

All panes start in: `C:\Users\Richard Wilks\CLI_RESTART`

---

## 🚀 Quick Start (RECOMMENDED - New Profile Method)

### Step 1: One-Time Setup

**Option A: Double-click setup (easiest)**
```cmd
setup_profile.cmd
```

**Option B: PowerShell with options**
```powershell
# Basic setup
.\setup_profile.ps1

# Full setup with all options
.\setup_profile.ps1 -CreateShortcut -LaunchAfterSetup -EnablePersistedLayout

# Set as default Windows Terminal profile
.\setup_profile.ps1 -SetAsDefault
```

### Step 2: Launch Anytime

**Option A: Desktop shortcut** (if created during setup)
- Double-click the `10_Bands` shortcut on your desktop

**Option B: Command line**
```cmd
launch_10_bands_profile.cmd
```

**Option C: Direct Windows Terminal**
```cmd
wt -p "10_Bands" --fullscreen
```

**Option D: If set as default**
```cmd
wt
```

---

## 📂 Files Overview

### New Profile-Based Approach (Recommended)
| File | Purpose |
|------|---------|
| `setup_profile.ps1` | One-time setup - creates WT profile |
| `setup_profile.cmd` | Double-click setup with shortcut |
| `launch_10_bands_profile.ps1` | PowerShell launcher using profile |
| `launch_10_bands_profile.cmd` | Quick launcher (double-click) |
| `Modules\Update-WTProfile.ps1` | Profile generator/updater core |

### Legacy Command-Line Approach (Still Works)
| File | Purpose |
|------|---------|
| `launch_10_bands.ps1` | Original PowerShell launcher |
| `launch_10_bands.cmd` | Original double-click launcher |
| `Modules\WT-10Pane-Layout.ps1` | Layout builder with command-line args |
| `Orchestrator.ps1` | Advanced orchestrator with IPC |

---

## ⚡ Why Profile-Based is Better

### Old Approach (Command-Line Args)
```powershell
# Slow: Builds complex args every launch
wt --fullscreen -d "..." new-tab ... split-pane ... (1000+ chars)
```
❌ Slower startup
❌ Complex argument parsing
❌ Harder to maintain
❌ Can't version control layout easily

### New Approach (Windows Terminal Profile)
```powershell
# Fast: Native WT profile lookup
wt -p "10_Bands" --fullscreen
```
✅ **Instant startup** - No PowerShell overhead
✅ **Native WT feature** - Uses built-in profile system
✅ **Easy to modify** - Update once with `setup_profile.ps1`
✅ **Version controlled** - Profile stored in WT settings.json
✅ **Automatic backup** - Settings backed up before changes

---

## 🛠️ Advanced Usage

### Update Profile with New Repository Path
```powershell
.\Modules\Update-WTProfile.ps1 -Repo "D:\MyProject" -ProfileName "MyProject_10Bands"
```

### Enable Persisted Layout (Auto-Save)
```powershell
# Enables automatic layout saving/restoration
.\setup_profile.ps1 -EnablePersistedLayout
```

Now Windows Terminal will automatically:
- Save your pane layout on close
- Restore exact configuration on next launch
- Remember window position and size

### Dry Run (Preview Changes)
```powershell
.\Modules\Update-WTProfile.ps1 -DryRun
```

Creates `Modules\settings_preview.json` to review before applying.

### Update Existing Profile
```powershell
# Profile already exists? Just re-run setup to update it
.\setup_profile.ps1
```

### Launch with Custom Options
```powershell
# Launch in existing window
.\launch_10_bands_profile.ps1 -UseExistingWindow

# Launch maximized instead of fullscreen
wt -p "10_Bands" --maximized

# Update profile then launch
.\launch_10_bands_profile.ps1 -UpdateProfile
```

---

## 📋 Requirements

### Required
- **Windows Terminal** (install from Microsoft Store or `winget install Microsoft.WindowsTerminal`)
- **PowerShell 7+** (`winget install Microsoft.PowerShell`)

### Optional (for full functionality)
- **Claude CLI** - `npm install -g @anthropics/claude-cli`
- **Codex CLI** - Install via your package manager
- **Aider** - `pip install aider-chat`

Missing tools will show warnings but won't prevent layout creation.

---

## 🔧 Troubleshooting

### Profile doesn't exist
```powershell
# Run setup first
.\setup_profile.cmd
```

### Layout not opening
```powershell
# Check tool availability
Get-Command wt, claude, codex, aider

# Validate profile exists
wt --list-profiles
```

### Want to reset to defaults
```powershell
# Backups are in:
# %LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_*\LocalState\backups\

# Restore from backup if needed
```

### Can't find settings.json
The script automatically searches:
1. `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json` (Stable)
2. `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json` (Preview)
3. `%LOCALAPPDATA%\Microsoft\Windows Terminal\settings.json` (Unpackaged)

---

## 📊 Comparison: Old vs New

| Feature | Old (CMD Args) | New (Profile) |
|---------|----------------|---------------|
| Startup Speed | ~2-3 seconds | ~0.5 seconds |
| Maintenance | Edit PS1 script | Run `setup_profile.ps1` |
| Launch Command | Complex args | `wt -p "10_Bands"` |
| Version Control | Script only | WT settings.json |
| Backups | Manual | Automatic |
| WT Integration | External | Native |

---

## 📖 Documentation

### Windows Terminal Docs
- [Command-Line Arguments](https://learn.microsoft.com/en-us/windows/terminal/command-line-arguments)
- [Startup Settings](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/startup)
- [GitHub Repository](https://github.com/microsoft/terminal)

### Project Files
- **Tests**: `Tests\WT-10Pane-Layout.Tests.ps1` (Pester tests)
- **Logs**: `C:\Automation\Logs\WT-10Pane-Layout-*.log`
- **Modules**: `AutomationSuite\`, `IpcUtils\` (advanced orchestration)

---

## 🎓 Examples

### Create Multiple Profiles for Different Projects
```powershell
# Project A
.\Modules\Update-WTProfile.ps1 -Repo "C:\ProjectA" -ProfileName "ProjectA_AI"

# Project B
.\Modules\Update-WTProfile.ps1 -Repo "D:\ProjectB" -ProfileName "ProjectB_AI"

# Launch specific project
wt -p "ProjectA_AI" --fullscreen
```

### Custom Tool Configuration
Edit `Modules\Update-WTProfile.ps1` and modify the `Build-StartupActions` function to change:
- Tool commands (claude, codex, aider)
- Pane titles
- Working directories
- Split sizes

Then re-run:
```powershell
.\setup_profile.ps1
```

---

## 🐛 Testing

```powershell
# Run Pester tests
$env:WT_LAYOUT_IMPORT='1'
Invoke-Pester -Path Tests\WT-10Pane-Layout.Tests.ps1
```

---

## 📝 License

Part of the CLI_RESTART project. See repository root for license information.

---

## 🙏 Credits

Built using Windows Terminal's native profile and startup actions features.

**References:**
- Microsoft Terminal Documentation
- Windows Terminal GitHub (microsoft/terminal)
