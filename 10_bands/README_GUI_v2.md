# Headless Queue Manager (v2)

Enhancements over v1:
- **Templates**: built‑in common tasks + optional `Config/TaskTemplates.json` loader.
- **DLQ Inspector**: browse `.tasks/failed/` and `.tasks/quarantine/`, retry or delete selected.
- **Quarantine (Circuit Breakers)**: view `state/circuit_breakers.json`, force close breakers.
- **Per‑tool & text filters** for the live log ticker.
- **Running Tasks**: live table backed by `.state/running_tasks.json`.
- **Metrics Dashboard**: success rate, per-tool chart, duration histogram, CSV export.
- **Edit & Retry**: modify failed task JSON before re-enqueueing.
- **Tray Mode**: optional minimize-to-tray with status indicator.

## Install
```
py -m pip install PyQt6
```

## Run
```
py QueueManagerGUI_v2.py
```

## Templates
The app provides a few built‑ins. To add your own, create:
```
<repo>/Config/TaskTemplates.json
```
Supported formats:
```json
{
  "Git: fetch & prune": { "tool":"git","args":["fetch","--all","--prune"] },
  "Quality Gate": { "tool":"pwsh","args":["-NoProfile","-File","scripts/run_quality.ps1"], "timeout_sec": 1800 }
}
```
or
```json
[
  {"name":"Git: status","task":{"tool":"git","args":["status","-sb"]}},
  {"name":"Aider: fix","task":{"tool":"aider","flags":["--yes"],"prompt":"Fix failing tests"}} 
]
```

## DLQ Inspector
- **Refresh** lists `failed/*.jsonl` and `quarantine/*.jsonl`.
- **Retry Selected** moves them back to `inbox/`.
- **Delete Selected** removes the files.
- **Edit & Retry** opens an inline JSON editor before sending a task back to `inbox/`.

## Quarantine (Circuit Breakers)
Reads `<repo>/.state/circuit_breakers.json` (created by your worker). You can **Force Close Selected** breakers if you must unblock a stuck queue.

## Filters
Use the **tool** dropdown and **text** box to narrow the live ticker.

## Running Tasks
Shows every active job the worker reported (with per-tool locking applied). Click **Refresh** or let the automatic refresh handle it.

## Metrics
The **Metrics** tab parses `logs/ledger.jsonl` and displays totals, success rate, per-tool bars, a duration histogram, and live CPU/memory usage (via `psutil` when available). Use **Export CSV** for offline analysis.

## Scheduling & Priorities
When adding or editing tasks you can set:

- **Priority** (high/normal/low)
- **Dependencies** (comma-separated task IDs)
- **Recurring cadence** in minutes
- **Run at** a specific timestamp

Recurring tasks re-queue automatically after successful completion.

## Tray Mode
Enable *Minimize to tray* to keep the GUI running in the background. The tray icon turns green when the heartbeat is fresh and red when stale. Tray menu options allow starting/stopping the worker quickly.

## Cross-Platform Notes
- Uses `pathlib` to resolve repos/tasks/logs across Windows, macOS, and Linux.
- Folder actions rely on `os.startfile`, `open`, or `xdg-open` depending on the OS.
- Starting/stopping the worker invokes `pwsh` (PowerShell 7+). Ensure it is on the `PATH` for Linux/macOS.

