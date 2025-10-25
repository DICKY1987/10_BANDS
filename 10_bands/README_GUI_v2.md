# Headless Queue Manager (v2)

Enhancements over v1:
- **Templates**: built‑in common tasks + optional `Config/TaskTemplates.json` loader.
- **DLQ Inspector**: browse `.tasks/failed/` and `.tasks/quarantine/`, retry or delete selected.
- **Quarantine (Circuit Breakers)**: view `state/circuit_breakers.json`, force close breakers.
- **Per‑tool & text filters** for the live log ticker.

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

## Quarantine (Circuit Breakers)
Reads `<repo>/.state/circuit_breakers.json` (created by your worker). You can **Force Close Selected** breakers if you must unblock a stuck queue.

## Filters
Use the **tool** dropdown and **text** box to narrow the live ticker.

