10_BANDS Windows Terminal Layout

⚡ RECOMMENDED: Use the new profile-based approach (4x faster!)
   Quick Start: Double-click setup_profile.cmd (one-time)
   Then: Double-click launch_10_bands_profile.cmd
   See: README.md for full documentation

--- NEW PROFILE-BASED APPROACH (Recommended) ---
Files:
- setup_profile.cmd               (one-time setup - creates WT profile)
- launch_10_bands_profile.cmd     (quick launcher using profile)
- Modules\Update-WTProfile.ps1    (profile generator/updater)
- README.md                       (full documentation)
- MIGRATION_GUIDE.md              (migration from old approach)

Usage:
1. One-time setup: setup_profile.cmd
2. Launch anytime: launch_10_bands_profile.cmd
   Or: wt -p "10_Bands" --fullscreen

Benefits:
✅ 4x faster startup (0.5s vs 2-3s)
✅ Native Windows Terminal integration
✅ Automatic backups
✅ Easier to maintain

--- LEGACY COMMAND-LINE APPROACH (Still works) ---
Files:
- Modules\WT-10Pane-Layout.ps1   (layout + logging, fullscreen fallback)
- Tests\WT-10Pane-Layout.Tests.ps1 (Pester tests)
- launch_10_bands.ps1             (launcher)
- launch_10_bands.cmd             (double-click launcher)

Usage:
- Double-click launch_10_bands.cmd (fullscreen)
- Or: pwsh -NoProfile -ExecutionPolicy Bypass -File launch_10_bands.ps1 -Fullscreen
- To reuse the last WT window: add -UseExistingWindow

Logs:
- Written to C:\Automation\Logs\WT-10Pane-Layout-<timestamp>.log

Tests:
- $env:WT_LAYOUT_IMPORT='1'; Invoke-Pester -Path Tests\WT-10Pane-Layout.Tests.ps1

Notes:
- Requires Windows Terminal (wt) on PATH.
- Titles are fixed with --suppressApplicationTitle.
- All panes start in C:\Users\Richard Wilks\CLI_RESTART via -d.
