# Repository Guidelines

## Project Structure & Module Organization
- `AutomationSuite/`: Core PowerShell module (`AutomationSuite.psm1|psd1`).
- `Modules/`: Windows Terminal helpers (e.g., `Update-WTProfile.ps1`, `WT-10Pane-Layout.ps1`).
- `IpcUtils/`: Inter‑process utilities (`IpcUtils.psm1|psd1`).
- `Config/`: Policies, templates, and shared settings (`*.psd1`, `TaskTemplates.json`).
- `scripts/`: Operational helpers (e.g., `QueueWorker.ps1`, `Supervisor.ps1`).
- `Tests/`: Pester tests (`*.Tests.ps1`); see `Tests/README.md`.
- Python: `QueueManagerGUI_v2.py`, `pyproject.toml` (Ruff/PyTest config).

## Build, Test, and Development Commands
- PowerShell (PS 7+): start `pwsh`. If needed: `Set-ExecutionPolicy -Scope Process Bypass`.
- Run suite locally: `./launch_10_bands.ps1` (profile setup: `./setup_profile.ps1`).
- Import module: `Import-Module ./AutomationSuite/AutomationSuite.psd1 -Force`.
- Pester tests: `Invoke-Pester -Path ./Tests -Output Detailed`.
- Lint PowerShell: `Invoke-ScriptAnalyzer -Path .` (if installed).
- Python dev (optional): `python -m venv .venv; .\\.venv\\Scripts\\Activate.ps1; pip install -r requirements-dev.txt`.
- Ruff: `ruff check . --fix`; PyTest (if tests exist): `pytest`.

## Coding Style & Naming Conventions
- PowerShell: 2‑space indent, UTF‑8; one public function per file when practical.
- Functions: `Verb-Noun` PascalCase (approved verbs: Get/Set/New/Invoke/Update/Remove/Start/Stop).
- Variables: camelCase; constants ALL_CAPS; private helpers may prefix `_`.
- Files: modules `.psm1`, manifests `.psd1`, tests end with `.Tests.ps1`.
- Python: follow Ruff; line length 100; import order managed by Ruff/isort.

## Testing Guidelines
- PowerShell: Pester v5 with `Describe`/`Context`/`It`. Mirror features in `Tests/`.
- Use Arrange‑Act‑Assert; mock external effects (`Mock`) to keep tests deterministic.
- Run focused sets via tags if present (e.g., `Invoke-Pester -Tag Unit`).
- Python (optional): place tests under `tests/`, name `test_*.py`.

## Commit & Pull Request Guidelines
- Commits: imperative, present tense; subject ≤ 72 chars. Conventional style encouraged.
  - Example: `fix(AutomationSuite): handle empty WT profiles`
- PRs: clear description, linked issues, before/after behavior, risks/rollbacks, and test evidence (Pester output; screenshots for GUI).
- All tests must pass; lint should be clean or justified.

## Security & Configuration Tips
- Scripts can modify Windows Terminal settings. Review `SharedConfig.psd1` and `Modules/Update-WTProfile.ps1` before running.
- Prefer non‑admin shells; use `-WhatIf`/`-Confirm` when available; test in a throwaway profile first.

