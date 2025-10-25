from __future__ import annotations

import json
import os
import shutil
import subprocess
from typing import Optional


DEF_TASKS = ".tasks"
DEF_LOGS = "logs"
STATE_DIR = ".state"


def get_tool_names_from_config(repo_path: str) -> list[str]:
    """Parse simple Name fields from Config/CliToolsConfig.psd1.

    This uses a lightweight regex approach tailored for the expected file format.
    """
    config_path = os.path.join(repo_path, "Config", "CliToolsConfig.psd1")
    if not os.path.exists(config_path):
        return []
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            content = f.read()
        import re

        tool_names = re.findall(r"Name\s*=\s*\'(.*?)\'", content)
        return tool_names
    except Exception:
        return []


def _which(exe: str) -> Optional[str]:
    try:
        return shutil.which(exe)
    except Exception:
        return None


def _read_shared_paths_from_ps(repo_path: str) -> Optional[dict]:
    """Attempt to import SharedConfig.psd1 via PowerShell and return Paths as dict.

    Prefers pwsh, falls back to Windows powershell if available.
    """
    psd1 = os.path.join(repo_path, "SharedConfig.psd1")
    if not os.path.exists(psd1):
        return None
    pwsh = _which("pwsh")
    ps5 = _which("powershell")
    shell = pwsh or ps5
    if not shell:
        return None
    cmd = [
        shell,
        "-NoProfile",
        "-Command",
        f"$x=Import-PowerShellDataFile -Path '{psd1}'; $x.Paths | ConvertTo-Json -Compress",
    ]
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
        data = json.loads(out.decode("utf-8", "ignore"))
        if isinstance(data, dict):
            return data
    except Exception:
        return None
    return None


def _read_shared_paths_fallback(repo_path: str) -> Optional[dict]:
    """Very small regex-based parser for the Paths block in SharedConfig.psd1.

    Handles single-quoted string values for TasksRoot/LogsRoot/StateRoot.
    """
    psd1 = os.path.join(repo_path, "SharedConfig.psd1")
    if not os.path.exists(psd1):
        return None
    try:
        txt = open(psd1, "r", encoding="utf-8").read()
    except Exception:
        return None
    import re

    paths_block = {}
    for key in ("TasksRoot", "LogsRoot", "StateRoot"):
        m = re.search(rf"{key}\s*=\s*'([^']+)'", txt)
        if m:
            paths_block[key] = m.group(1)
    return paths_block or None


def get_shared_paths(repo_path: str) -> dict:
    """Return a dict with TasksRoot/LogsRoot/StateRoot resolved to absolute paths."""
    paths = (
        _read_shared_paths_from_ps(repo_path)
        or _read_shared_paths_fallback(repo_path)
        or {}
    )
    tasks = paths.get("TasksRoot", DEF_TASKS)
    logs = paths.get("LogsRoot", DEF_LOGS)
    state = paths.get("StateRoot", STATE_DIR)
    # Resolve relative to repo root if needed
    if not os.path.isabs(tasks):
        tasks = os.path.join(repo_path, tasks)
    if not os.path.isabs(logs):
        logs = os.path.join(repo_path, logs)
    if not os.path.isabs(state):
        state = os.path.join(repo_path, state)
    return {"TasksRoot": tasks, "LogsRoot": logs, "StateRoot": state}

