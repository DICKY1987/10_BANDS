#!/usr/bin/env python3
from __future__ import annotations

import json
import numbers
import os
import platform
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PyQt6 import QtCore, QtGui, QtWidgets

try:
    from PyQt6 import QtCharts  # type: ignore[attr-defined]
except Exception:  # pragma: no cover - optional dependency
    QtCharts = None

try:  # pragma: no cover - optional dependency
    import psutil
except Exception:  # pragma: no cover - optional dependency
    psutil = None

APP_TITLE = "Headless Queue Manager (v2)"
REPO_ROOT = Path(__file__).resolve().parent
DEFAULT_REPO = REPO_ROOT
DEF_TASKS = Path(".tasks")
DEF_LOGS = Path("logs")
STATE_DIR = Path(".state")

# Optional template search path (auto-loaded if exists)
DEFAULT_TEMPLATES_REL = Path("Config") / "TaskTemplates.json"


class LogTailer(QtCore.QObject):
    new_lines = QtCore.pyqtSignal(list)

    def __init__(
        self,
        path: Path | str,
        poll_ms: int = 700,
        parent: QtCore.QObject | None = None,
    ) -> None:
        super().__init__(parent)
        self.path = Path(path)
        self.poll_ms = poll_ms
        self._timer = QtCore.QTimer(self)
        self._timer.timeout.connect(self._poll)
        self._pos = 0
        self._inode = None

    def start(self) -> None:
        self._timer.start(self.poll_ms)

    def stop(self) -> None:
        self._timer.stop()

    def _poll(self) -> None:
        try:
            if not self.path.exists():
                return
            st = self.path.stat()
            inode = (st.st_dev, getattr(st, "st_ino", st.st_size))
            if self._inode != inode or st.st_size < self._pos:
                self._pos = 0
                self._inode = inode
            with self.path.open("r", encoding="utf-8", errors="replace") as f:
                f.seek(self._pos)
                chunk = f.read()
                self._pos = f.tell()
            if not chunk:
                return
            lines = [ln.rstrip() for ln in chunk.splitlines() if ln.strip()]
            if lines:
                self.new_lines.emit(lines)
        except Exception:
            pass


def color_for_line(line: str) -> str:
    low = line.lower()
    if (
        "error" in low
        or "[error]" in low
        or " fail " in low
        or low.endswith(" fail")
        or "timeout" in low
    ):
        return "#ff4444"
    if "warn" in low:
        return "#ffaa00"
    if "ok" in low or "success" in low or "quality gate: ok" in low:
        return "#44bb44"
    return "#cccccc"


class RunningTasksModel(QtCore.QAbstractTableModel):
    headers = ["ID", "Tool", "Priority", "Started", "Source", "Repo"]

    def __init__(
        self,
        parent: QtCore.QObject | None = None,
    ) -> None:
        super().__init__(parent)
        self._rows: list[dict[str, Any]] = []

    def update_rows(self, rows: list[dict[str, Any]]) -> None:
        self.beginResetModel()
        self._rows = rows
        self.endResetModel()

    def rowCount(  # noqa: N802
        self,
        parent: QtCore.QModelIndex | None = None,
    ) -> int:
        if parent is None:
            parent = QtCore.QModelIndex()
        return 0 if parent.isValid() else len(self._rows)

    def columnCount(  # noqa: N802
        self,
        parent: QtCore.QModelIndex | None = None,
    ) -> int:
        if parent is None:
            parent = QtCore.QModelIndex()
        return 0 if parent.isValid() else len(self.headers)

    def headerData(  # noqa: N802
        self,
        section: int,
        orientation: QtCore.Qt.Orientation,
        role: int = QtCore.Qt.ItemDataRole.DisplayRole,
    ) -> str | None:
        if role != QtCore.Qt.ItemDataRole.DisplayRole:
            return None
        if orientation == QtCore.Qt.Orientation.Horizontal and 0 <= section < len(self.headers):
            return self.headers[section]
        return None

    def data(
        self,
        index: QtCore.QModelIndex,
        role: int = QtCore.Qt.ItemDataRole.DisplayRole,
    ) -> str | None:
        if not index.isValid() or role not in (
            QtCore.Qt.ItemDataRole.DisplayRole,
            QtCore.Qt.ItemDataRole.ToolTipRole,
        ):
            return None
        row = self._rows[index.row()]
        col = index.column()
        if col == 0:
            return row.get("id", "")
        if col == 1:
            return row.get("tool", "")
        if col == 2:
            return row.get("priority", "")
        if col == 3:
            started = row.get("started")
            if started:
                try:
                    dt = datetime.fromisoformat(str(started).replace("Z", "+00:00"))
                    return dt.astimezone().strftime("%Y-%m-%d %H:%M:%S")
                except Exception:
                    return started
            return ""
        if col == 4:
            return row.get("file", "")
        if col == 5:
            return row.get("repo", "")
        return None

    def active_count(self) -> int:
        return len(self._rows)


class MetricsTab(QtWidgets.QWidget):
    def __init__(self, parent: QtWidgets.QWidget | None = None) -> None:
        super().__init__(parent)
        self._logs_dir = REPO_ROOT
        self.summary = QtWidgets.QLabel("Metrics not loaded")
        self.summary.setWordWrap(True)
        self.systemUsage = QtWidgets.QLabel("System usage unavailable")
        self.systemUsage.setWordWrap(True)
        self.btnRefresh = QtWidgets.QPushButton("Refresh Metrics")
        self.btnExport = QtWidgets.QPushButton("Export CSV")
        self.btnRefresh.clicked.connect(self.refresh_metrics)
        self.btnExport.clicked.connect(self.export_csv)

        charts_layout = QtWidgets.QHBoxLayout()
        self.toolChartView = None
        self.histChartView = None
        if QtCharts:
            self.toolChartView = QtCharts.QChartView()
            self.toolChartView.setRenderHint(QtGui.QPainter.RenderHint.Antialiasing)
            self.histChartView = QtCharts.QChartView()
            self.histChartView.setRenderHint(QtGui.QPainter.RenderHint.Antialiasing)
            charts_layout.addWidget(self.toolChartView, 1)
            charts_layout.addWidget(self.histChartView, 1)
        else:
            charts_layout.addWidget(QtWidgets.QLabel("QtCharts not available"))

        layout = QtWidgets.QVBoxLayout(self)
        layout.addWidget(self.summary)
        layout.addWidget(self.systemUsage)
        btns = QtWidgets.QHBoxLayout()
        btns.addWidget(self.btnRefresh)
        btns.addWidget(self.btnExport)
        btns.addStretch(1)
        layout.addLayout(btns)
        layout.addLayout(charts_layout)
        layout.addStretch(1)

        self._last_metrics: dict[str, Any] = {}

    def set_logs_dir(self, logs_dir: Path) -> None:
        self._logs_dir = logs_dir

    def refresh_metrics(self) -> None:
        ledger = self._logs_dir / "ledger.jsonl"
        if not ledger.exists():
            self.summary.setText("ledger.jsonl not found")
            if self.toolChartView:
                self.toolChartView.setChart(QtCharts.QChart())
            if self.histChartView:
                self.histChartView.setChart(QtCharts.QChart())
            return
        tasks: dict[str, dict] = {}
        try:
            lines = ledger.read_text(encoding="utf-8", errors="replace").splitlines()
        except Exception as exc:  # pragma: no cover - disk error
            self.summary.setText(f"Error reading ledger: {exc}")
            return

        for ln in lines:
            ln = ln.strip()
            if not ln:
                continue
            try:
                obj = json.loads(ln)
            except Exception:
                continue
            tid = str(obj.get("id", "unknown"))
            tool = str(obj.get("tool", "unknown"))
            attempt = int(obj.get("attempt", 0))
            rec = tasks.setdefault(tid, {"tool": tool, "attempts": {}, "final": None})
            rec["tool"] = tool
            rec["attempts"][attempt] = obj

        total = len(tasks)
        success = 0
        durations: list[float] = []
        tool_stats: dict[str, dict[str, int]] = {}
        for rec in tasks.values():
            if not rec["attempts"]:
                continue
            last_attempt = max(rec["attempts"].keys())
            final = rec["attempts"][last_attempt]
            ok = bool(final.get("ok"))
            if ok:
                success += 1
            duration_ms = final.get("duration_ms")
            if isinstance(duration_ms, numbers.Real):
                durations.append(float(duration_ms) / 1000.0)
            tool = rec.get("tool", "unknown")
            stats = tool_stats.setdefault(tool, {"total": 0, "success": 0})
            stats["total"] += 1
            if ok:
                stats["success"] += 1

        success_rate = (success / total * 100) if total else 0.0
        avg_duration = (sum(durations) / len(durations)) if durations else 0.0
        summary_lines = [
            f"Total tasks: {total}",
            f"Success rate: {success_rate:.1f}%",
            f"Average duration: {avg_duration:.1f}s",
        ]
        self.summary.setText("\n".join(summary_lines))
        self._last_metrics = {"tool_stats": tool_stats, "durations": durations}

        if self.toolChartView:
            chart = QtCharts.QChart()
            chart.setTitle("Per-tool success rate")
            series = QtCharts.QBarSeries()
            categories = []
            success_set = QtCharts.QBarSet("Success %")
            for tool, stats in sorted(tool_stats.items()):
                categories.append(tool)
                pct = (stats["success"] / stats["total"] * 100) if stats["total"] else 0
                success_set << pct
            if categories:
                series.append(success_set)
                chart.addSeries(series)
                axis = QtCharts.QBarCategoryAxis()
                axis.append(categories)
                chart.createDefaultAxes()
                chart.setAxisX(axis, series)
                chart.axisY(series).setTitleText("Success %")
            self.toolChartView.setChart(chart)

        if self.histChartView:
            chart = QtCharts.QChart()
            chart.setTitle("Task duration histogram (seconds)")
            buckets = [0, 30, 60, 120, 300, 600]
            counts = [0 for _ in buckets]
            for duration in durations:
                placed = False
                for idx, limit in enumerate(buckets):
                    if duration <= limit:
                        counts[idx] += 1
                        placed = True
                        break
                if not placed:
                    counts[-1] += 1
            series = QtCharts.QBarSeries()
            labels = [
                "<=30s",
                "<=60s",
                "<=120s",
                "<=300s",
                "<=600s",
                ">600s",
            ]
            bar_set = QtCharts.QBarSet("Tasks")
            for c in counts:
                bar_set << c
            series.append(bar_set)
            chart.addSeries(series)
            axis = QtCharts.QBarCategoryAxis()
            axis.append(labels)
            chart.createDefaultAxes()
            chart.setAxisX(axis, series)
            chart.axisY(series).setTitleText("Count")
            self.histChartView.setChart(chart)

    def update_system_usage(self) -> None:
        if not psutil:
            self.systemUsage.setText("psutil not installed")
            return
        cpu = psutil.cpu_percent(interval=None)
        mem = psutil.virtual_memory()
        mem_used = mem.used // (1024**2)
        mem_total = mem.total // (1024**2)
        usage = (
            f"CPU: {cpu:.1f}%  |  Memory: {mem.percent:.1f}% "
            f"({mem_used} MiB / {mem_total} MiB)"
        )
        self.systemUsage.setText(usage)

    def export_csv(self) -> None:
        if not self._last_metrics:
            QtWidgets.QMessageBox.information(self, "Metrics", "Load metrics first")
            return
        tool_stats = self._last_metrics.get("tool_stats", {})
        durations = self._last_metrics.get("durations", [])
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        path = self._logs_dir / f"metrics_{ts}.csv"
        try:
            with path.open("w", encoding="utf-8", newline="") as fh:
                fh.write("tool,total,success\n")
                for tool, stats in tool_stats.items():
                    fh.write(f"{tool},{stats['total']},{stats['success']}\n")
                fh.write("duration_seconds\n")
                for duration in durations:
                    fh.write(f"{duration:.3f}\n")
        except Exception as exc:  # pragma: no cover - disk error
            QtWidgets.QMessageBox.critical(self, "Export failed", str(exc))
            return
        QtWidgets.QMessageBox.information(self, "Export", f"Metrics exported to {path}")

class AddTaskDialog(QtWidgets.QDialog):
    def __init__(
        self,
        repo_path: str,
        seed: dict[str, Any] | None = None,
        parent: QtWidgets.QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.setWindowTitle("Add Task (JSONL)")
        self.setModal(True)
        self.repo_path = repo_path
        layout = QtWidgets.QFormLayout(self)

        self.tool = QtWidgets.QComboBox()
        self.tool.addItems(["git", "aider", "codex", "claude", "pwsh", "python"])
        self.repo = QtWidgets.QLineEdit(repo_path)
        self.priority = QtWidgets.QComboBox()
        self.priority.addItems(["high", "normal", "low"])
        self.args = QtWidgets.QLineEdit()
        self.flags = QtWidgets.QLineEdit()
        self.files = QtWidgets.QLineEdit()
        self.prompt = QtWidgets.QPlainTextEdit()
        self.timeout = QtWidgets.QSpinBox()
        self.timeout.setRange(0, 86400)
        self.timeout.setValue(900)
        self.depends = QtWidgets.QLineEdit()
        self.recurring = QtWidgets.QSpinBox()
        self.recurring.setRange(0, 1440)
        self.recurring.setSuffix(" min")
        self.scheduleCheck = QtWidgets.QCheckBox("Enable scheduling")
        self.runAt = QtWidgets.QDateTimeEdit(QtCore.QDateTime.currentDateTime())
        self.runAt.setCalendarPopup(True)
        self.runAt.setDisplayFormat("yyyy-MM-dd HH:mm")
        self.runAt.setEnabled(False)
        self.scheduleCheck.toggled.connect(self.runAt.setEnabled)

        layout.addRow("Tool", self.tool)
        layout.addRow("Repo", self.repo)
        layout.addRow("Priority", self.priority)
        layout.addRow("Args (space-separated)", self.args)
        layout.addRow("Flags (space-separated)", self.flags)
        layout.addRow("Files (comma-separated)", self.files)
        layout.addRow("Prompt (optional)", self.prompt)
        layout.addRow("Timeout (sec, 0 = none)", self.timeout)
        layout.addRow("Depends on (comma IDs)", self.depends)
        layout.addRow("Recurring", self.recurring)
        layout.addRow(self.scheduleCheck, self.runAt)

        btns = QtWidgets.QDialogButtonBox(
            QtWidgets.QDialogButtonBox.StandardButton.Ok
            | QtWidgets.QDialogButtonBox.StandardButton.Cancel
        )
        btns.accepted.connect(self.accept)
        btns.rejected.connect(self.reject)
        layout.addRow(btns)

        if seed:
            self.apply_seed(seed)

    def apply_seed(self, seed: dict[str, Any]) -> None:
        def join_list(value: object) -> str:
            if isinstance(value, list):
                return " ".join(str(v) for v in value)
            return str(value or "")

        if "tool" in seed:
            self.tool.setCurrentText(str(seed["tool"]))
        if "repo" in seed:
            self.repo.setText(str(seed["repo"]))
        if "priority" in seed:
            self.priority.setCurrentText(str(seed["priority"]))
        if "args" in seed:
            self.args.setText(join_list(seed["args"]))
        if "flags" in seed:
            self.flags.setText(join_list(seed["flags"]))
        if "files" in seed:
            self.files.setText(
                ", ".join(seed["files"]) if isinstance(seed["files"], list) else str(seed["files"])
            )
        if "prompt" in seed:
            self.prompt.setPlainText(str(seed["prompt"]))
        if "timeout_sec" in seed:
            try:
                self.timeout.setValue(int(seed["timeout_sec"]))
            except Exception:
                pass
        if "depends_on" in seed:
            depends = seed["depends_on"]
            if isinstance(depends, list):
                text = ", ".join(str(item) for item in depends)
            else:
                text = str(depends)
            self.depends.setText(text)
        if seed.get("recurring_minutes"):
            try:
                self.recurring.setValue(int(seed["recurring_minutes"]))
            except Exception:
                pass
        run_at = seed.get("run_at")
        if run_at:
            try:
                ts = str(run_at).replace("Z", "")
                dt = QtCore.QDateTime.fromString(ts, "yyyy-MM-ddTHH:mm:ss")
                if dt.isValid():
                    self.scheduleCheck.setChecked(True)
                    self.runAt.setDateTime(dt)
            except Exception:
                pass

    def build_task(self) -> dict[str, Any]:
        task = {
            "id": datetime.now().strftime("%Y%m%d%H%M%S"),
            "tool": self.tool.currentText(),
            "repo": self.repo.text().strip() or self.repo_path,
            "timeout_sec": int(self.timeout.value()),
            "priority": self.priority.currentText(),
        }
        if self.args.text().strip():
            task["args"] = self.args.text().strip().split()
        if self.flags.text().strip():
            task["flags"] = self.flags.text().strip().split()
        if self.files.text().strip():
            task["files"] = [p.strip() for p in self.files.text().split(",") if p.strip()]
        ptxt = self.prompt.toPlainText().strip()
        if ptxt:
            task["prompt"] = ptxt
        if self.depends.text().strip():
            task["depends_on"] = [p.strip() for p in self.depends.text().split(",") if p.strip()]
        if int(self.recurring.value()) > 0:
            task["recurring_minutes"] = int(self.recurring.value())
        if self.scheduleCheck.isChecked():
            task["run_at"] = self.runAt.dateTime().toString("yyyy-MM-ddTHH:mm:ss")
        return task


class TemplatesModel(QtCore.QObject):
    changed = QtCore.pyqtSignal()

    def __init__(self, parent: QtCore.QObject | None = None) -> None:
        super().__init__(parent)
        self.templates: dict[str, dict[str, Any]] = {}

    def load(self, path: str) -> None:
        try:
            data = json.load(open(path, encoding="utf-8"))
            if isinstance(data, list):
                # list of {name, task}
                self.templates = {
                    item.get("name", f"Template {i + 1}"): item.get("task", {})
                    for i, item in enumerate(data)
                }
            elif isinstance(data, dict):
                self.templates = data
            self.changed.emit()
        except Exception:
            pass

    def builtin(self) -> None:
        self.templates = {
            "Git: fetch + prune": {"tool": "git", "args": ["fetch", "--all", "--prune"]},
            "Git: status -sb": {"tool": "git", "args": ["status", "-sb"]},
            "Quality Gate": {
                "tool": "pwsh",
                "args": ["-NoProfile", "-File", "scripts/run_quality.ps1"],
                "timeout_sec": 1800,
            },
            "Aider: refactor stub": {
                "tool": "aider",
                "flags": ["--yes"],
                "prompt": "Refactor module for better dependency injection.",
                "timeout_sec": 1200,
            },
        }
        self.changed.emit()


class MainWindow(QtWidgets.QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle(APP_TITLE)
        self.resize(1320, 860)

        # === Top paths & control ===
        self.repoEdit = QtWidgets.QLineEdit(str(DEFAULT_REPO))
        self.tasksEdit = QtWidgets.QLineEdit("")
        self.logsEdit = QtWidgets.QLineEdit("")
        self.btnRepo = QtWidgets.QPushButton("Repo…")
        self.btnRepo.clicked.connect(self.choose_repo)
        self.btnTasks = QtWidgets.QPushButton(".tasks…")
        self.btnTasks.clicked.connect(self.choose_tasks)
        self.btnLogs = QtWidgets.QPushButton("logs…")
        self.btnLogs.clicked.connect(self.choose_logs)
        self.btnStart = QtWidgets.QPushButton("Start Worker")
        self.btnStop = QtWidgets.QPushButton("Stop Worker")
        self.btnAdd = QtWidgets.QPushButton("Add Task")
        self.btnRetryFailed = QtWidgets.QPushButton("Retry Failed → Inbox")
        self.btnOpenTasks = QtWidgets.QPushButton("Open .tasks")
        self.btnOpenLogs = QtWidgets.QPushButton("Open logs")
        self.btnStart.clicked.connect(self.start_worker)
        self.btnStop.clicked.connect(self.stop_worker)
        self.btnAdd.clicked.connect(self.add_task)
        self.btnRetryFailed.clicked.connect(self.retry_failed)
        self.btnOpenTasks.clicked.connect(lambda: self.open_folder(self.tasks_dir_path()))
        self.btnOpenLogs.clicked.connect(lambda: self.open_folder(self.logs_dir_path()))
        self.chkTrayPref = QtWidgets.QCheckBox("Minimize to tray")

        # Filters
        self.filterTool = QtWidgets.QComboBox()
        self.filterTool.addItems(["All", "git", "aider", "codex", "claude", "pwsh", "python"])
        self.filterText = QtWidgets.QLineEdit()
        self.filterText.setPlaceholderText("Filter text…")

        # Templates
        self.templates = TemplatesModel(self)
        self.templates.builtin()  # start with built-ins
        self.templatePicker = QtWidgets.QComboBox()
        self.templates.changed.connect(self.refresh_templates)
        self.refresh_templates()
        self.btnEnqueueTemplate = QtWidgets.QPushButton("Enqueue Template")
        self.btnEditTemplate = QtWidgets.QPushButton("Open in Dialog")
        self.btnLoadTemplates = QtWidgets.QPushButton("Load Templates.json…")
        self.btnEnqueueTemplate.clicked.connect(self.enqueue_template)
        self.btnEditTemplate.clicked.connect(self.open_template_in_dialog)
        self.btnLoadTemplates.clicked.connect(self.load_templates_from_disk)

        top = QtWidgets.QWidget()
        g = QtWidgets.QGridLayout(top)
        r = 0
        g.addWidget(QtWidgets.QLabel("Repo"), r, 0)
        g.addWidget(self.repoEdit, r, 1)
        g.addWidget(self.btnRepo, r, 2)
        r += 1
        g.addWidget(QtWidgets.QLabel(".tasks"), r, 0)
        g.addWidget(self.tasksEdit, r, 1)
        g.addWidget(self.btnTasks, r, 2)
        r += 1
        g.addWidget(QtWidgets.QLabel("logs"), r, 0)
        g.addWidget(self.logsEdit, r, 1)
        g.addWidget(self.btnLogs, r, 2)
        r += 1

        bar = QtWidgets.QWidget()
        hb = QtWidgets.QHBoxLayout(bar)
        hb.addWidget(self.btnStart)
        hb.addWidget(self.btnStop)
        hb.addSpacing(15)
        hb.addWidget(self.btnAdd)
        hb.addWidget(self.btnRetryFailed)
        hb.addStretch(1)
        hb.addWidget(self.btnOpenTasks)
        hb.addWidget(self.btnOpenLogs)
        hb.addSpacing(20)
        hb.addWidget(QtWidgets.QLabel("Filter:"))
        hb.addWidget(self.filterTool)
        hb.addWidget(self.filterText)
        hb.addSpacing(10)
        hb.addWidget(self.chkTrayPref)

        tbar = QtWidgets.QWidget()
        tb = QtWidgets.QHBoxLayout(tbar)
        tb.addWidget(QtWidgets.QLabel("Templates:"))
        tb.addWidget(self.templatePicker, 2)
        tb.addWidget(self.btnEnqueueTemplate)
        tb.addWidget(self.btnEditTemplate)
        tb.addStretch(1)
        tb.addWidget(self.btnLoadTemplates)

        # === Center: tabs ===
        self.liveLog = QtWidgets.QTextEdit()
        self.liveLog.setReadOnly(True)
        self.liveLog.setLineWrapMode(QtWidgets.QTextEdit.LineWrapMode.NoWrap)

        # Errors/ledger tab remains as before
        self.errorsList = QtWidgets.QListWidget()
        self.errorsList.itemDoubleClicked.connect(self.open_selected_log)
        self.ledgerList = QtWidgets.QListWidget()
        self.refreshLedgerBtn = QtWidgets.QPushButton("Refresh Ledger")
        self.refreshLedgerBtn.clicked.connect(self.load_ledger)
        left_tabs = QtWidgets.QTabWidget()
        page_log = QtWidgets.QWidget()
        vv = QtWidgets.QVBoxLayout(page_log)
        vv.addWidget(self.liveLog)
        left_tabs.addTab(page_log, "Live Log")

        # Right panel: Errors, Ledger, DLQ, Quarantine
        right_tabs = QtWidgets.QTabWidget()

        self.runningModel = RunningTasksModel(self)
        self.runningView = QtWidgets.QTableView()
        self.runningView.setModel(self.runningModel)
        self.runningView.horizontalHeader().setStretchLastSection(True)
        self.runningView.setSelectionBehavior(QtWidgets.QAbstractItemView.SelectionBehavior.SelectRows)
        self.runningView.setEditTriggers(QtWidgets.QAbstractItemView.EditTrigger.NoEditTriggers)
        self.btnRunningRefresh = QtWidgets.QPushButton("Refresh")
        self.btnRunningRefresh.clicked.connect(self.refresh_running_tasks)
        self.lblActiveTasks = QtWidgets.QLabel("Active tasks: 0")
        running_tab = QtWidgets.QWidget()
        running_layout = QtWidgets.QVBoxLayout(running_tab)
        run_header = QtWidgets.QHBoxLayout()
        run_header.addWidget(self.btnRunningRefresh)
        run_header.addStretch(1)
        run_header.addWidget(self.lblActiveTasks)
        running_layout.addLayout(run_header)
        running_layout.addWidget(self.runningView)
        right_tabs.addTab(running_tab, "Running")
        errors_tab = QtWidgets.QWidget()
        v1 = QtWidgets.QVBoxLayout(errors_tab)
        v1.addWidget(QtWidgets.QLabel("Recent errors (double‑click to open folder):"))
        v1.addWidget(self.errorsList)
        right_tabs.addTab(errors_tab, "Errors")

        ledger_tab = QtWidgets.QWidget()
        v2 = QtWidgets.QVBoxLayout(ledger_tab)
        v2.addWidget(self.refreshLedgerBtn)
        v2.addWidget(self.ledgerList)
        right_tabs.addTab(ledger_tab, "Ledger")

        # DLQ tab (failed + quarantine)
        self.failedList = QtWidgets.QListWidget()
        self.quarantineList = QtWidgets.QListWidget()
        self.btnDLQRefresh = QtWidgets.QPushButton("Refresh")
        self.btnDLQRetry = QtWidgets.QPushButton("Retry Selected")
        self.btnDLQDelete = QtWidgets.QPushButton("Delete Selected")
        self.btnDLQEdit = QtWidgets.QPushButton("Edit && Retry")
        self.btnDLQRefresh.clicked.connect(self.refresh_dlq)
        self.btnDLQRetry.clicked.connect(self.retry_selected_dlq)
        self.btnDLQDelete.clicked.connect(self.delete_selected_dlq)
        self.btnDLQEdit.clicked.connect(self.edit_retry_selected_dlq)
        dlq_tab = QtWidgets.QWidget()
        v3 = QtWidgets.QVBoxLayout(dlq_tab)
        hdlq = QtWidgets.QHBoxLayout()
        hdlq.addWidget(QtWidgets.QLabel("failed/"))
        hdlq.addStretch(1)
        hdlq.addWidget(QtWidgets.QLabel("quarantine/"))
        lists = QtWidgets.QHBoxLayout()
        lists.addWidget(self.failedList)
        lists.addWidget(self.quarantineList)
        v3.addLayout(hdlq)
        v3.addLayout(lists)
        hbtn = QtWidgets.QHBoxLayout()
        hbtn.addWidget(self.btnDLQRefresh)
        hbtn.addStretch(1)
        hbtn.addWidget(self.btnDLQRetry)
        hbtn.addWidget(self.btnDLQEdit)
        hbtn.addWidget(self.btnDLQDelete)
        v3.addLayout(hbtn)
        right_tabs.addTab(dlq_tab, "DLQ")

        # Quarantine breakers tab (view/force-close)
        self.breakerView = QtWidgets.QTableWidget(0, 4)
        self.breakerView.setHorizontalHeaderLabels(["Tool", "State", "Fails", "Until"])
        self.breakerView.horizontalHeader().setStretchLastSection(True)
        self.btnCBRefresh = QtWidgets.QPushButton("Refresh")
        self.btnCBForceClose = QtWidgets.QPushButton("Force Close Selected")
        self.btnCBRefresh.clicked.connect(self.refresh_breakers)
        self.btnCBForceClose.clicked.connect(self.force_close_breaker)
        q_tab = QtWidgets.QWidget()
        v4 = QtWidgets.QVBoxLayout(q_tab)
        v4.addWidget(self.btnCBRefresh)
        v4.addWidget(self.breakerView)
        v4.addWidget(self.btnCBForceClose)
        right_tabs.addTab(q_tab, "Quarantine")

        self.metricsTab = MetricsTab(self)
        right_tabs.addTab(self.metricsTab, "Metrics")

        splitter = QtWidgets.QSplitter()
        splitter.setOrientation(QtCore.Qt.Orientation.Horizontal)
        splitter.addWidget(left_tabs)
        splitter.addWidget(right_tabs)
        splitter.setStretchFactor(0, 3)
        splitter.setStretchFactor(1, 2)

        # Central layout
        central = QtWidgets.QWidget()
        layout = QtWidgets.QVBoxLayout(central)
        layout.addWidget(top)
        layout.addWidget(bar)
        layout.addWidget(tbar)
        layout.addWidget(splitter)
        self.setCentralWidget(central)

        # Status bar
        self.status = self.statusBar()
        self.lblStatus = QtWidgets.QLabel("Stopped")
        self.status.addPermanentWidget(self.lblStatus)

        # Timers
        self.tailer = LogTailer("", poll_ms=700, parent=self)
        self.tailer.new_lines.connect(self.on_new_log_lines)
        self.hbTimer = QtWidgets.QTimer(self)
        self.hbTimer.setInterval(1000)
        self.hbTimer.timeout.connect(self.on_timer_tick)

        # Tray icon
        self._build_tray_icons()
        self.tray = QtWidgets.QSystemTrayIcon(self._trayIconInactive, self)
        tray_menu = QtWidgets.QMenu(self)
        act_show = tray_menu.addAction("Open")
        act_show.triggered.connect(self.showNormal)
        tray_menu.addSeparator()
        act_start = tray_menu.addAction("Start Worker")
        act_start.triggered.connect(self.start_worker)
        act_stop = tray_menu.addAction("Stop Worker")
        act_stop.triggered.connect(self.stop_worker)
        tray_menu.addSeparator()
        act_exit = tray_menu.addAction("Exit")
        act_exit.triggered.connect(QtWidgets.QApplication.instance().quit)
        self.tray.setContextMenu(tray_menu)
        self.tray.activated.connect(self._on_tray_activated)
        self.tray.show()
        self.trayPreference = False
        self.chkTrayPref.toggled.connect(self.on_tray_pref_changed)

        self.update_default_paths()
        self.tailer.start()
        self.hbTimer.start()
        # Try load templates from default Config path
        self.try_load_default_templates()
        self.load_settings()

    # ===== Paths/helpers =====
    def repo_dir_path(self) -> Path:
        text = self.repoEdit.text().strip()
        return Path(text).expanduser() if text else DEFAULT_REPO

    def tasks_dir_path(self) -> Path:
        text = self.tasksEdit.text().strip()
        if text:
            return Path(text).expanduser()
        return self.repo_dir_path() / DEF_TASKS

    def logs_dir_path(self) -> Path:
        text = self.logsEdit.text().strip()
        if text:
            return Path(text).expanduser()
        return self.repo_dir_path() / DEF_LOGS

    def state_dir_path(self) -> Path:
        return self.repo_dir_path() / STATE_DIR

    def update_default_paths(self) -> None:
        repo = self.repo_dir_path()
        self.tasksEdit.setPlaceholderText(str(repo / DEF_TASKS))
        self.logsEdit.setPlaceholderText(str(repo / DEF_LOGS))
        for path in [self.tasks_dir_path(), self.logs_dir_path(), self.state_dir_path()]:
            path.mkdir(parents=True, exist_ok=True)
        self.tailer.path = self.logs_dir_path() / "queueworker.log"
        self.metricsTab.set_logs_dir(self.logs_dir_path())
        self.refresh_breakers()
        self.refresh_running_tasks()

    # ===== UI actions =====
    def choose_repo(self) -> None:
        d = QtWidgets.QFileDialog.getExistingDirectory(
            self, "Choose Repo", str(self.repo_dir_path())
        )
        if d:
            self.repoEdit.setText(d)
            self.update_default_paths()
            self.try_load_default_templates()
            self.load_settings()

    def choose_tasks(self) -> None:
        d = QtWidgets.QFileDialog.getExistingDirectory(
            self, "Choose .tasks", str(self.tasks_dir_path())
        )
        if d:
            self.tasksEdit.setText(d)

    def choose_logs(self) -> None:
        d = QtWidgets.QFileDialog.getExistingDirectory(
            self, "Choose logs", str(self.logs_dir_path())
        )
        if d:
            self.logsEdit.setText(d)
            self.tailer.path = Path(d) / "queueworker.log"

    def start_worker(self) -> None:
        sup = self.repo_dir_path() / "scripts" / "Supervisor.ps1"
        if not sup.exists():
            QtWidgets.QMessageBox.warning(self, "Missing", f"Supervisor not found:\n{sup}")
            return
        try:
            if platform.system() == "Windows":
                cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(sup)]
                subprocess.Popen(
                    cmd,
                    creationflags=subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP,
                )
            else:
                candidates = [
                    shutil.which("pwsh"),
                    shutil.which("powershell"),
                    shutil.which("pwsh-preview"),
                ]
                exe = next((c for c in candidates if c), None)
                if not exe:
                    raise RuntimeError("pwsh not available on PATH")
                subprocess.Popen([exe, "-NoProfile", "-File", str(sup)])
            self.lblStatus.setText("Worker: starting…")
            self._show_tray_message("Worker", "Start requested")
        except Exception as e:
            QtWidgets.QMessageBox.critical(self, "Error", str(e))

    def stop_worker(self) -> None:
        stopfile = self.repo_dir_path() / "STOP.HEADLESS"
        try:
            stopfile.write_text("stop", encoding="utf-8")
            self.lblStatus.setText("Stop requested")
            self._show_tray_message("Worker", "Stop requested")
        except Exception as e:
            QtWidgets.QMessageBox.critical(self, "Error", str(e))

    # ===== Templates =====
    def refresh_templates(self) -> None:
        self.templatePicker.clear()
        for name in sorted(self.templates.templates.keys()):
            self.templatePicker.addItem(name)

    def get_selected_template_task(self) -> dict[str, Any] | None:
        name = self.templatePicker.currentText().strip()
        return self.templates.templates.get(name)

    def enqueue_template(self) -> None:
        task = self.get_selected_template_task()
        if not task:
            QtWidgets.QMessageBox.information(self, "No template", "Select a template first")
            return
        # Respect current repo if not set
        task = dict(task)  # shallow copy
        task.setdefault("repo", str(self.repo_dir_path()))
        self.enqueue_task_dict(task)

    def open_template_in_dialog(self) -> None:
        task = self.get_selected_template_task()
        if not task:
            QtWidgets.QMessageBox.information(self, "No template", "Select a template first")
            return
        task = dict(task)
        task.setdefault("repo", str(self.repo_dir_path()))
        dlg = AddTaskDialog(str(self.repo_dir_path()), seed=task, parent=self)
        if dlg.exec() == QtWidgets.QDialog.DialogCode.Accepted:
            self.enqueue_task_dict(dlg.build_task())

    def load_templates_from_disk(self) -> None:
        path, _ = QtWidgets.QFileDialog.getOpenFileName(
            self, "Load Templates JSON", str(self.repo_dir_path()), "JSON (*.json)"
        )
        if not path:
            return
        self.templates.load(path)

    def try_load_default_templates(self) -> None:
        path = self.repo_dir_path() / DEFAULT_TEMPLATES_REL
        if path.exists():
            self.templates.load(str(path))

    # ===== Task enqueue & retry =====
    def add_task(self) -> None:
        dlg = AddTaskDialog(str(self.repo_dir_path()), parent=self)
        if dlg.exec() == QtWidgets.QDialog.DialogCode.Accepted:
            self.enqueue_task_dict(dlg.build_task())

    def enqueue_task_dict(self, task: dict[str, Any]) -> None:
        inbox = self.tasks_dir_path() / "inbox"
        inbox.mkdir(parents=True, exist_ok=True)
        tid = task.get("id") or datetime.now().strftime("%Y%m%d%H%M%S")
        task["id"] = tid
        path = inbox / f"task_{tid}.jsonl"
        path.write_text(json.dumps(task, ensure_ascii=False) + "\n", encoding="utf-8")
        QtWidgets.QMessageBox.information(self, "Queued", f"Task enqueued:\n{path}")

    def retry_failed(self) -> None:
        self.refresh_dlq()  # loads lists
        inbox = self.tasks_dir_path() / "inbox"
        inbox.mkdir(parents=True, exist_ok=True)
        moved = 0
        for lst in (self.failedList, self.quarantineList):
            for i in range(lst.count()):
                item = lst.item(i)
                if not item:
                    continue
                p = item.data(QtCore.Qt.ItemDataRole.UserRole)
                if p and Path(p).is_file():
                    try:
                        shutil.move(p, str(inbox / Path(p).name))
                        moved += 1
                    except Exception:
                        pass
        QtWidgets.QMessageBox.information(self, "Retry", f"Moved {moved} files back to inbox.")

    # ===== DLQ inspector =====
    def refresh_dlq(self) -> None:
        self.failedList.clear()
        self.quarantineList.clear()
        failed = self.tasks_dir_path() / "failed"
        quarant = self.tasks_dir_path() / "quarantine"
        for folder, widget in [(failed, self.failedList), (quarant, self.quarantineList)]:
            if folder.is_dir():
                for path in sorted(folder.glob("*.jsonl")):
                    modified = datetime.fromtimestamp(path.stat().st_mtime)
                    stamp = modified.strftime("%Y-%m-%d %H:%M:%S")
                    label = f"{path.name}  ({stamp})"
                    it = QtWidgets.QListWidgetItem(label)
                    it.setData(QtCore.Qt.ItemDataRole.UserRole, str(path))
                    widget.addItem(it)

    def delete_selected_dlq(self) -> None:
        total = 0
        for lst in (self.failedList, self.quarantineList):
            for it in lst.selectedItems():
                p = it.data(QtCore.Qt.ItemDataRole.UserRole)
                try:
                    Path(p).unlink()
                    total += 1
                except Exception:
                    pass
        self.refresh_dlq()
        QtWidgets.QMessageBox.information(self, "Delete", f"Deleted {total} file(s).")

    def retry_selected_dlq(self) -> None:
        inbox = self.tasks_dir_path() / "inbox"
        inbox.mkdir(parents=True, exist_ok=True)
        moved = 0
        for lst in (self.failedList, self.quarantineList):
            for it in lst.selectedItems():
                p = it.data(QtCore.Qt.ItemDataRole.UserRole)
                try:
                    shutil.move(p, str(inbox / Path(p).name))
                    moved += 1
                except Exception:
                    pass
        self.refresh_dlq()
        QtWidgets.QMessageBox.information(self, "Retry", f"Moved {moved} file(s) to inbox.")

    def edit_retry_selected_dlq(self) -> None:
        items: list[QtWidgets.QListWidgetItem] = []
        for lst in (self.failedList, self.quarantineList):
            items.extend(lst.selectedItems())
        if not items:
            QtWidgets.QMessageBox.information(self, "Edit", "Select a task file first")
            return
        path = Path(items[0].data(QtCore.Qt.ItemDataRole.UserRole) or "")
        if not path.exists():
            QtWidgets.QMessageBox.warning(self, "Missing", f"File not found: {path}")
            return

        editor = QtWidgets.QDialog(self)
        editor.setWindowTitle(f"Edit {path.name}")
        layout = QtWidgets.QVBoxLayout(editor)
        layout.addWidget(QtWidgets.QLabel("Modify JSON lines below. Each line must be valid JSON."))
        edit = QtWidgets.QPlainTextEdit()
        edit.setPlainText(path.read_text(encoding="utf-8"))
        layout.addWidget(edit)
        btns = QtWidgets.QDialogButtonBox(
            QtWidgets.QDialogButtonBox.StandardButton.Save
            | QtWidgets.QDialogButtonBox.StandardButton.Cancel
        )
        layout.addWidget(btns)
        btns.accepted.connect(editor.accept)
        btns.rejected.connect(editor.reject)

        if editor.exec() != QtWidgets.QDialog.DialogCode.Accepted:
            return

        text = edit.toPlainText().strip()
        if not text:
            QtWidgets.QMessageBox.warning(self, "Edit", "Cannot enqueue empty file")
            return

        lines = [ln for ln in text.splitlines() if ln.strip()]
        try:
            for ln in lines:
                json.loads(ln)
        except Exception as exc:
            QtWidgets.QMessageBox.critical(self, "Invalid JSON", str(exc))
            return

        inbox = self.tasks_dir_path() / "inbox"
        inbox.mkdir(parents=True, exist_ok=True)
        ts = datetime.now().strftime("%Y%m%d%H%M%S")
        new_path = inbox / f"edited_{ts}_{path.name}"
        new_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

        backup = path.with_suffix(path.suffix + ".bak")
        try:
            path.rename(backup)
        except Exception:
            path.unlink(missing_ok=True)

        self.refresh_dlq()
        QtWidgets.QMessageBox.information(
            self,
            "Edit",
            f"Edited task enqueued to {new_path.name}. Original saved as {backup.name}.",
        )

    # ===== Quarantine breakers =====
    def breakers_path(self) -> Path:
        return self.state_dir_path() / "circuit_breakers.json"

    def refresh_breakers(self) -> None:
        path = self.breakers_path()
        self.breakerView.setRowCount(0)
        if not path.exists():
            return
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(data, dict):
                return
            for tool, rec in sorted(data.items()):
                r = self.breakerView.rowCount()
                self.breakerView.insertRow(r)
                state = rec.get("state", "?")
                fails = rec.get("fails", "?")
                until = rec.get("until", "")
                for c, val in enumerate([tool, state, str(fails), until]):
                    self.breakerView.setItem(r, c, QtWidgets.QTableWidgetItem(val))
        except Exception:
            pass

    def force_close_breaker(self) -> None:
        path = self.breakers_path()
        if not path.exists():
            QtWidgets.QMessageBox.information(self, "No file", "circuit_breakers.json not found")
            return
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            sel = self.breakerView.selectedItems()
            if not sel:
                QtWidgets.QMessageBox.information(self, "Select", "Select a row first")
                return
            tools = sorted({self.breakerView.item(it.row(), 0).text() for it in sel})
            for t in tools:
                if t in data:
                    data[t]["state"] = "closed"
                    data[t]["fails"] = 0
                    data[t]["until"] = datetime.now().isoformat()
            path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
            self.refresh_breakers()
        except Exception as e:
            QtWidgets.QMessageBox.critical(self, "Error", str(e))

    # ===== Live log & filters =====
    def on_new_log_lines(self, lines: list[str]) -> None:
        at_end = (
            self.liveLog.verticalScrollBar().value() == self.liveLog.verticalScrollBar().maximum()
        )
        tool_filter = self.filterTool.currentText().lower()
        text_filter = self.filterText.text().strip().lower()

        for line in lines:
            low = line.lower()
            # tool filter
            if tool_filter != "all":
                # heuristic: include when tool name appears in the log line
                # examples: "[git]", "git:", or " git " tokens
                if (
                    f"[{tool_filter}]" not in low
                    and (tool_filter + ":") not in low
                    and (" " + tool_filter + " ") not in low
                ):
                    continue
            # text filter
            if text_filter and text_filter not in low:
                continue

            self.liveLog.append(f'<span style="color:{color_for_line(line)}">{line}</span>')

            if "error" in low or "fail" in low or "timeout" in low:
                hint_log = None
                for tok in line.split():
                    if tok.startswith("task_") and tok.endswith(".log"):
                        hint_log = str(self.logs_dir_path() / tok)
                        break
                it = QtWidgets.QListWidgetItem(line)
                if hint_log:
                    it.setData(QtCore.Qt.ItemDataRole.UserRole, hint_log)
                it.setForeground(QtGui.QBrush(QtGui.QColor("#ff4444")))
                self.errorsList.addItem(it)
                if self.errorsList.count() > 200:
                    self.errorsList.takeItem(0)

        if at_end:
            self.liveLog.verticalScrollBar().setValue(self.liveLog.verticalScrollBar().maximum())

    # ===== Ledger & heartbeat =====
    def load_ledger(self) -> None:
        self.ledgerList.clear()
        ledger = self.logs_dir_path() / "ledger.jsonl"
        if not ledger.exists():
            self.ledgerList.addItem("ledger.jsonl not found")
            return
        try:
            lines = ledger.read_text(encoding="utf-8", errors="replace").splitlines()[-500:]
            for ln in lines:
                ln = ln.strip()
                if not ln:
                    continue
                try:
                    obj = json.loads(ln)
                    ts = obj.get("ts", "")
                    tid = obj.get("id", "")
                    tool = obj.get("tool", "")
                    ok = obj.get("ok", False)
                    exitc = obj.get("exit", "")
                    txt = f"{ts}  [{tool}] id={tid}  {'OK' if ok else 'FAIL'} (code={exitc})"
                    it = QtWidgets.QListWidgetItem(txt)
                    it.setForeground(QtGui.QBrush(QtGui.QColor("#44bb44" if ok else "#ff4444")))
                    self.ledgerList.addItem(it)
                except Exception:
                    self.ledgerList.addItem(ln)
        except Exception as e:
            self.ledgerList.addItem(f"Error reading ledger: {e}")
        self.metricsTab.refresh_metrics()

    def check_heartbeat(self) -> None:
        hb = self.state_dir_path() / "heartbeat.json"
        if not hb.exists():
            self.lblStatus.setText("No heartbeat")
            self._update_tray_icon(active=False)
            return
        try:
            data = json.loads(hb.read_text(encoding="utf-8"))
            ts_raw = data.get("timestamp", "")
            if not ts_raw:
                self.lblStatus.setText("Heartbeat: unreadable")
                self._update_tray_icon(active=False)
                return
            ts = datetime.fromisoformat(ts_raw.replace("Z", "+00:00"))
            age = (datetime.now(timezone.utc) - ts.astimezone(timezone.utc)).total_seconds()
            pid = data.get("pid", "?")
            self.lblStatus.setText(f"Heartbeat: {int(age)}s ago  |  PID {pid}")
            self._update_tray_icon(active=age <= 10)
        except Exception:
            self.lblStatus.setText("Heartbeat: unreadable")
            self._update_tray_icon(active=False)

    # ===== Misc helpers =====
    def open_folder(self, path: Path | str) -> None:
        folder = Path(path)
        folder.mkdir(parents=True, exist_ok=True)
        path_str = str(folder)
        if sys.platform.startswith("win"):
            os.startfile(path_str)
        elif sys.platform == "darwin":
            subprocess.call(["open", path_str])
        else:
            subprocess.call(["xdg-open", path_str])

    def open_selected_log(self) -> None:
        item = self.errorsList.currentItem()
        if not item:
            return
        path = item.data(QtCore.Qt.ItemDataRole.UserRole)
        if path and Path(path).is_file():
            self.open_folder(Path(path).parent)

    def refresh_running_tasks(self) -> None:
        path = self.state_dir_path() / "running_tasks.json"
        rows: list[dict[str, Any]] = []
        if path.exists():
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
                if isinstance(data, list):
                    for item in data:
                        if isinstance(item, dict):
                            rows.append(
                                {
                                    "id": str(item.get("id", "")),
                                    "tool": str(item.get("tool", "")),
                                    "priority": str(item.get("priority", "")),
                                    "started": item.get("started", ""),
                                    "file": str(item.get("file", "")),
                                    "repo": str(item.get("repo", "")),
                                }
                            )
            except Exception:
                pass
        self.runningModel.update_rows(rows)
        count = self.runningModel.active_count()
        self.lblActiveTasks.setText(f"Active tasks: {count}")
        if hasattr(self, "tray"):
            self.tray.setToolTip(f"{APP_TITLE} – {count} running task(s)")

    def on_timer_tick(self) -> None:
        self.check_heartbeat()
        self.refresh_running_tasks()
        self.metricsTab.update_system_usage()

    def _build_tray_icons(self) -> None:
        active = QtGui.QPixmap(16, 16)
        active.fill(QtGui.QColor("#4caf50"))
        inactive = QtGui.QPixmap(16, 16)
        inactive.fill(QtGui.QColor("#e53935"))
        self._trayIconActive = QtGui.QIcon(active)
        self._trayIconInactive = QtGui.QIcon(inactive)

    def _update_tray_icon(self, *, active: bool) -> None:
        if hasattr(self, "tray"):
            self.tray.setIcon(self._trayIconActive if active else self._trayIconInactive)

    def _show_tray_message(self, title: str, message: str) -> None:
        if hasattr(self, "tray"):
            self.tray.showMessage(
                title,
                message,
                QtWidgets.QSystemTrayIcon.MessageIcon.Information,
                3000,
            )

    def _on_tray_activated(self, reason: QtWidgets.QSystemTrayIcon.ActivationReason) -> None:
        if reason in (
            QtWidgets.QSystemTrayIcon.ActivationReason.Trigger,
            QtWidgets.QSystemTrayIcon.ActivationReason.DoubleClick,
        ):
            self.showNormal()
            self.raise_()
            self.activateWindow()

    def on_tray_pref_changed(self, checked: bool) -> None:
        if getattr(self, "_loading_settings", False):
            self.trayPreference = checked
            return
        self.trayPreference = checked
        self.save_settings()

    def load_settings(self) -> None:
        self._loading_settings = True
        try:
            path = self.state_dir_path() / "gui_settings.json"
            pref = False
            if path.exists():
                try:
                    data = json.loads(path.read_text(encoding="utf-8"))
                    pref = bool(data.get("minimize_to_tray", False))
                except Exception:
                    pref = False
            self.trayPreference = pref
            self.chkTrayPref.setChecked(pref)
        finally:
            self._loading_settings = False

    def save_settings(self) -> None:
        path = self.state_dir_path() / "gui_settings.json"
        try:
            payload = json.dumps(
                {"minimize_to_tray": bool(self.trayPreference)},
                ensure_ascii=False,
                indent=2,
            )
            path.write_text(payload, encoding="utf-8")
        except Exception:
            pass

    def closeEvent(self, event: QtGui.QCloseEvent) -> None:  # type: ignore[override]  # noqa: N802
        if getattr(self, "trayPreference", False):
            event.ignore()
            self.hide()
            self._show_tray_message(APP_TITLE, "Application minimized to tray")
        else:
            super().closeEvent(event)


def main() -> None:
    app = QtWidgets.QApplication(sys.argv)
    w = MainWindow()
    w.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
