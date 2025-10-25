Headless AI Orchestration Migration Blueprint
0) Scope & goals

Drop Windows Terminal dependencies and move to quiet, headless execution.

Run all tools (git, aider, Codex, Claude) via batch jobs from a durable task queue.

Add Ruff + pytest + Pester quality checks locally and in GitHub Actions.

Bake in self-healing (recovery, retries/backoff, circuit breaker, watchdog, git-lock repair).

Keep existing AutomationSuite module and shared config.

Why this change? Your repo is currently centered around WT pane orchestration (10_BANDS), including WT profiles and launchers, as reflected in your docs and preview settings .

1) What to retire vs keep

Retire/Remove (WT-specific):

WT-10Pane-Layout.ps1, Update-WTProfile.ps1, launch_10_bands*.{ps1,cmd}, setup_profile*.{ps1,cmd}, WT layout/profile docs. These are all tied to opening and managing panes/profiles rather than headless workers, per current README/Migration Guide and WT settings preview.

Keep:

AutomationSuite.psm1/.psd1 (core automation/exported functions),

SharedConfig.psd1 (shared logging/config). Confirmed in repo guidance.

Reference: Your existing docs describe the pane-based method and WT profile approach; we’re replacing those launch paths with headless orchestration while keeping the core automation module.

2) Final repo additions (this blueprint)

The ZIP includes these files (drop them at repo root as shown):

Orchestrator.Headless.ps1
Config/
  CliToolsConfig.psd1
  HeadlessPolicies.psd1
scripts/
  QueueWorker.ps1
  Supervisor.ps1
  RecoverProcessing.ps1
  run_quality.ps1
Tests/
  AutomationSuite.Tests.ps1
  QueueWorker.SelfHealing.Tests.ps1
PesterConfiguration.psd1
pyproject.toml
requirements-dev.txt
.github/workflows/quality.yml
.pre-commit-config.yaml (optional)
.tasks/
  inbox/
    example.tasks.jsonl
logs/   (created at runtime)

3) How the system works (headless)

Orchestrator.Headless.ps1 starts a set of background jobs from Config/CliToolsConfig.psd1 and writes a unified log plus per-tool logs.

QueueWorker.ps1 is the durable task runner:

Watches .tasks/inbox/*.jsonl (one JSON object per line).

Executes each task against a repo using the named tool (git/aider/codex/claude/any executable).

Writes ledger.jsonl, per-task logs, heartbeats, circuit-breaker state, and recovers stale processing.

Supervisor.ps1 restarts the worker if the process dies or the heartbeat goes stale.

Policies (retry/backoff/jitter, circuit breaker, queue recovery, git index.lock repair) are in Config/HeadlessPolicies.psd1.

Quality gate (scripts/run_quality.ps1) runs:

ruff format --check, ruff check, pytest, and Pester (PowerShell tests).

Same script is used locally and in GitHub Actions.

4) Install & prerequisites

PowerShell 7+ (pwsh).

Git on PATH.

Python 3.10+ with pip.

Optional CLIs: aider, codex, claude (or your actual executable names/entrypoints).

5) Step-by-step implementation
5.1 Add the headless orchestrator

File: Orchestrator.Headless.ps1 (included in ZIP; full code provided there)

Starts each configured tool as a background job via your AutomationSuite exports.

Drains job output to a unified log and per-tool logs.

Exits cleanly if STOP.HEADLESS file appears.

Run:

pwsh -NoProfile -ExecutionPolicy Bypass -File .\Orchestrator.Headless.ps1
# Stop:
New-Item -ItemType File .\STOP.HEADLESS | Out-Null

5.2 Configure headless tools (includes a git loop)

File: Config/CliToolsConfig.psd1 (included)

Adds a GitStatusLoop task running git fetch --all --prune and short status.

Includes stubs for Claude/Codex/Aider (replace with your non-interactive entrypoints).

5.3 Drop in the hardened QueueWorker (fully self-healing)

File: scripts/QueueWorker.ps1 (included)

Implements:

Inbox/Processing/Done/Failed/Quarantine folders, atomic moves.

Retries with exponential backoff + jitter.

Circuit breaker per tool (quarantine when open).

Heartbeat file and log rotation.

Git index.lock self-healing.

Append-only ledger of task attempts/outcomes.

Start it manually or via Supervisor (next step).

5.4 Supervisor (auto-restart on crash/hang)

File: scripts/Supervisor.ps1 (included)

Run at logon with Task Scheduler:

pwsh -NoProfile -File .\scripts\Supervisor.ps1

5.5 Recovery pass (stale processing → inbox)

File: scripts/RecoverProcessing.ps1 (included)

Called automatically by the worker at start.

You can run it manually if needed.

5.6 Quality gate (Ruff + pytest + Pester)

Files included:

scripts/run_quality.ps1

pyproject.toml

requirements-dev.txt

PesterConfiguration.psd1

Tests/AutomationSuite.Tests.ps1

Tests/QueueWorker.SelfHealing.Tests.ps1

Install Python dev deps:

pip install -r requirements-dev.txt


Run locally:

pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_quality.ps1

5.7 CI gate (GitHub Actions)

File: .github/workflows/quality.yml (included)

Runs on windows-latest (works on self-hosted Windows by changing runs-on).

Executes the same script scripts/run_quality.ps1.

Uploads logs as artifacts.

5.8 Example tasks (drop in to try now)

File: .tasks/inbox/example.tasks.jsonl (included)

{ "id":"git-001","tool":"git","repo":".","args":["fetch","--all","--prune"] }
{ "id":"git-002","tool":"git","repo":".","args":["status","-sb"] }
{ "id":"aider-001","tool":"aider","repo":".","prompt":"Refactor Modules/Orchestrator.ps1 to extract Start-Workers into a separate module with params.","files":["Modules\\Orchestrator.ps1"],"flags":["--yes"],"timeout_sec":1200 }
{ "id":"codex-001","tool":"codex","repo":".","prompt":"Write Pester tests for Modules/AutomationSuite.psm1 public functions.","flags":["--non-interactive"] }
{ "id":"claude-001","tool":"claude","repo":".","prompt":"Generate a migration plan to remove Windows Terminal panes and run headless.","flags":["--no-editor"] }
{ "id":"quality-001","tool":"pwsh","args":["-NoProfile","-File","scripts/run_quality.ps1"],"timeout_sec":1800 }

6) Operations guide
Start/stop

Start QueueWorker directly:
pwsh -NoProfile -File .\scripts\QueueWorker.ps1

Start via Supervisor (auto-restart, recommended):
pwsh -NoProfile -File .\scripts\Supervisor.ps1

Stop cleanly:
New-Item -ItemType File .\STOP.HEADLESS | Out-Null (both Orchestrator and Supervisor/Worker will honor this in their loops)

Logs & ledger

logs\queueworker.log – worker log.

logs\task_<id>.log – per-task output.

logs\ledger.jsonl – append-only record of every attempt (+ exit code).

Circuit breaker

If a tool fails repeatedly (WindowFailures), the breaker opens for OpenSeconds. Tasks are moved to quarantine. This prevents burn-in during outages, bad creds, or rate limits. Policy tunables in Config/HeadlessPolicies.psd1.

Self-healing features

RecoverProcessing: moves stale files back to inbox.

Retries/backoff/jitter: deterministic retry window without thundering herd.

Git lock repair: removes stale .git/index.lock if no git processes and lock is old.

Heartbeat & Watchdog: Supervisor restarts the worker if the heartbeat goes stale.

7) Mapping from the old 10-pane setup

Before: Windows Terminal opened 10 panes and you interacted manually (or via scripts that generated long wt arguments or profile startup actions). Your docs and settings preview reflect that approach.

Now: Drop JSONL tasks in .tasks\inbox\*.jsonl. The worker runs them headlessly, writes logs, and self-heals. The same quality gate used by CI can be triggered locally by a task (or pre-commit).

8) Customize CLI names & flags

In scripts/QueueWorker.ps1, edit Build-Command:

Change "aider", "codex", "claude" to the actual executable names you use (e.g., aider, codex-cli, claude-cli) and adjust how prompts/flags are passed (e.g., --message-file vs stdin).

Add more switch cases for other tools if needed.

9) Optional: pre-commit for quick local feedback

.pre-commit-config.yaml included with Ruff hooks.

pip install pre-commit
pre-commit install

10) Quick checklist

 Remove WT-specific launchers and helpers (keep AutomationSuite + SharedConfig).

 Add files from the Headless Migration Pack (above ZIP).

 pip install -r requirements-dev.txt

 pwsh -NoProfile -File scripts/run_quality.ps1 (verify green locally)

 Create Task Scheduler entries:

Supervisor at logon → pwsh -NoProfile -File scripts\Supervisor.ps1

(Optional) Orchestrator.Headless at logon if you want long-lived loops like GitStatusLoop.

 Drop .tasks/inbox/example.tasks.jsonl and watch logs roll.

 Push .github/workflows/quality.yml to enforce gates on PRs.