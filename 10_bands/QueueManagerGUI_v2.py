#!/usr/bin/env python3
from __future__ import annotations
import os, sys, json, subprocess, shutil
from datetime import datetime, timezone
from PyQt6 import QtCore, QtGui, QtWidgets

APP_TITLE = "Headless Queue Manager (v2)"
DEFAULT_REPO = r"C:\Users\Richard Wilks\CLI_RESTART"
DEF_TASKS = ".tasks"
DEF_LOGS = "logs"
STATE_DIR = ".state"

# Optional template search path (auto-loaded if exists)
DEFAULT_TEMPLATES_REL = os.path.join("Config", "TaskTemplates.json")


class LogTailer(QtCore.QObject):
    new_lines = QtCore.pyqtSignal(list)

    def __init__(self, path: str, poll_ms: int = 700, parent=None):
        super().__init__(parent)
        self.path = path
        self.poll_ms = poll_ms
        self._timer = QtCore.QTimer(self)
        self._timer.timeout.connect(self._poll)
        self._pos = 0
        self._inode = None

    def start(self):
        self._timer.start(self.poll_ms)

    def stop(self):
        self._timer.stop()

    def _poll(self):
        try:
            if not os.path.exists(self.path):
                return
            st = os.stat(self.path)
            inode = (st.st_dev, getattr(st, "st_ino", st.st_size))
            if self._inode != inode or st.st_size < self._pos:
                self._pos = 0
                self._inode = inode
            with open(self.path, "r", encoding="utf-8", errors="replace") as f:
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


class AddTaskDialog(QtWidgets.QDialog):
    def __init__(self, repo_path: str, seed: dict | None = None, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Add Task (JSONL)")
        self.setModal(True)
        self.repo_path = repo_path
        layout = QtWidgets.QFormLayout(self)

        self.tool = QtWidgets.QComboBox()
        self.tool.addItems(["git", "aider", "codex", "claude", "pwsh", "python"])
        self.repo = QtWidgets.QLineEdit(repo_path)
        self.args = QtWidgets.QLineEdit()
        self.flags = QtWidgets.QLineEdit()
        self.files = QtWidgets.QLineEdit()
        self.prompt = QtWidgets.QPlainTextEdit()
        self.timeout = QtWidgets.QSpinBox()
        self.timeout.setRange(0, 86400)
        self.timeout.setValue(900)

        layout.addRow("Tool", self.tool)
        layout.addRow("Repo", self.repo)
        layout.addRow("Args (space-separated)", self.args)
        layout.addRow("Flags (space-separated)", self.flags)
        layout.addRow("Files (comma-separated)", self.files)
        layout.addRow("Prompt (optional)", self.prompt)
        layout.addRow("Timeout (sec, 0 = none)", self.timeout)

        btns = QtWidgets.QDialogButtonBox(
            QtWidgets.QDialogButtonBox.StandardButton.Ok
            | QtWidgets.QDialogButtonBox.StandardButton.Cancel
        )
        btns.accepted.connect(self.accept)
        btns.rejected.connect(self.reject)
        layout.addRow(btns)

        if seed:
            self.apply_seed(seed)

    def apply_seed(self, seed: dict):
        def join_list(v):
            return " ".join(v) if isinstance(v, list) else (v or "")

        if "tool" in seed:
            self.tool.setCurrentText(str(seed["tool"]))
        if "repo" in seed:
            self.repo.setText(str(seed["repo"]))
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
            except:
                pass

    def build_task(self) -> dict:
        task = {
            "id": datetime.now().strftime("%Y%m%d%H%M%S"),
            "tool": self.tool.currentText(),
            "repo": self.repo.text().strip() or self.repo_path,
            "timeout_sec": int(self.timeout.value()),
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
        return task


class TemplatesModel(QtCore.QObject):
    changed = QtCore.pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.templates = {}  # name -> dict

    def load(self, path: str):
        try:
            data = json.load(open(path, "r", encoding="utf-8"))
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

    def builtin(self):
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
    def __init__(self):
        super().__init__()
        self.setWindowTitle(APP_TITLE)
        self.resize(1320, 860)

        # === Top paths & control ===
        self.repoEdit = QtWidgets.QLineEdit(DEFAULT_REPO)
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
        self.btnOpenTasks.clicked.connect(lambda: self.open_folder(self.tasks_dir()))
        self.btnOpenLogs.clicked.connect(lambda: self.open_folder(self.logs_dir()))

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
        leftTabs = QtWidgets.QTabWidget()
        pageLog = QtWidgets.QWidget()
        vv = QtWidgets.QVBoxLayout(pageLog)
        vv.addWidget(self.liveLog)
        leftTabs.addTab(pageLog, "Live Log")

        # Right panel: Errors, Ledger, DLQ, Quarantine
        rightTabs = QtWidgets.QTabWidget()
        errorsTab = QtWidgets.QWidget()
        v1 = QtWidgets.QVBoxLayout(errorsTab)
        v1.addWidget(QtWidgets.QLabel("Recent errors (double‑click to open folder):"))
        v1.addWidget(self.errorsList)
        rightTabs.addTab(errorsTab, "Errors")

        ledgerTab = QtWidgets.QWidget()
        v2 = QtWidgets.QVBoxLayout(ledgerTab)
        v2.addWidget(self.refreshLedgerBtn)
        v2.addWidget(self.ledgerList)
        rightTabs.addTab(ledgerTab, "Ledger")

        # DLQ tab (failed + quarantine)
        self.failedList = QtWidgets.QListWidget()
        self.quarantineList = QtWidgets.QListWidget()
        self.btnDLQRefresh = QtWidgets.QPushButton("Refresh")
        self.btnDLQRetry = QtWidgets.QPushButton("Retry Selected")
        self.btnDLQDelete = QtWidgets.QPushButton("Delete Selected")
        self.btnDLQRefresh.clicked.connect(self.refresh_dlq)
        self.btnDLQRetry.clicked.connect(self.retry_selected_dlq)
        self.btnDLQDelete.clicked.connect(self.delete_selected_dlq)
        dlqTab = QtWidgets.QWidget()
        v3 = QtWidgets.QVBoxLayout(dlqTab)
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
        hbtn.addWidget(self.btnDLQDelete)
        v3.addLayout(hbtn)
        rightTabs.addTab(dlqTab, "DLQ")

        # Quarantine breakers tab (view/force-close)
        self.breakerView = QtWidgets.QTableWidget(0, 4)
        self.breakerView.setHorizontalHeaderLabels(["Tool", "State", "Fails", "Until"])
        self.breakerView.horizontalHeader().setStretchLastSection(True)
        self.btnCBRefresh = QtWidgets.QPushButton("Refresh")
        self.btnCBForceClose = QtWidgets.QPushButton("Force Close Selected")
        self.btnCBRefresh.clicked.connect(self.refresh_breakers)
        self.btnCBForceClose.clicked.connect(self.force_close_breaker)
        qTab = QtWidgets.QWidget()
        v4 = QtWidgets.QVBoxLayout(qTab)
        v4.addWidget(self.btnCBRefresh)
        v4.addWidget(self.breakerView)
        v4.addWidget(self.btnCBForceClose)
        rightTabs.addTab(qTab, "Quarantine")

        splitter = QtWidgets.QSplitter()
        splitter.setOrientation(QtCore.Qt.Orientation.Horizontal)
        splitter.addWidget(leftTabs)
        splitter.addWidget(rightTabs)
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
        self.hbTimer.timeout.connect(self.check_heartbeat)

        self.update_default_paths()
        self.tailer.start()
        self.hbTimer.start()
        # Try load templates from default Config path
        self.try_load_default_templates()

    # ===== Paths/helpers =====
    def repo_dir(self) -> str:
        return self.repoEdit.text().strip() or DEFAULT_REPO

    def tasks_dir(self) -> str:
        p = self.tasksEdit.text().strip()
        if not p:
            p = os.path.join(self.repo_dir(), DEF_TASKS)
        return p

    def logs_dir(self) -> str:
        p = self.logsEdit.text().strip()
        if not p:
            p = os.path.join(self.repo_dir(), DEF_LOGS)
        return p

    def state_dir(self) -> str:
        return os.path.join(self.repo_dir(), STATE_DIR)

    def update_default_paths(self):
        self.tasksEdit.setPlaceholderText(os.path.join(self.repo_dir(), DEF_TASKS))
        self.logsEdit.setPlaceholderText(os.path.join(self.repo_dir(), DEF_LOGS))
        for p in [self.tasks_dir(), self.logs_dir(), self.state_dir()]:
            os.makedirs(p, exist_ok=True)
        self.tailer.path = os.path.join(self.logs_dir(), "queueworker.log")
        self.refresh_breakers()

    # ===== UI actions =====
    def choose_repo(self):
        d = QtWidgets.QFileDialog.getExistingDirectory(self, "Choose Repo", self.repo_dir())
        if d:
            self.repoEdit.setText(d)
            self.update_default_paths()
            self.try_load_default_templates()

    def choose_tasks(self):
        d = QtWidgets.QFileDialog.getExistingDirectory(self, "Choose .tasks", self.tasks_dir())
        if d:
            self.tasksEdit.setText(d)

    def choose_logs(self):
        d = QtWidgets.QFileDialog.getExistingDirectory(self, "Choose logs", self.logs_dir())
        if d:
            self.logsEdit.setText(d)
            self.tailer.path = os.path.join(self.logs_dir(), "queueworker.log")

    def start_worker(self):
        sup = os.path.join(self.repo_dir(), "scripts", "Supervisor.ps1")
        if not os.path.exists(sup):
            QtWidgets.QMessageBox.warning(self, "Missing", f"Supervisor not found:\n{sup}")
            return
        try:
            if os.name == "nt":
                cmd = f'powershell -NoProfile -ExecutionPolicy Bypass -File "{sup}"'
                subprocess.Popen(
                    cmd,
                    shell=True,
                    creationflags=subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP,
                )
            else:
                subprocess.Popen(["pwsh", "-NoProfile", "-File", sup])
            self.lblStatus.setText("Worker: starting…")
        except Exception as e:
            QtWidgets.QMessageBox.critical(self, "Error", str(e))

    def stop_worker(self):
        stopfile = os.path.join(self.repo_dir(), "STOP.HEADLESS")
        try:
            with open(stopfile, "w", encoding="utf-8") as f:
                f.write("stop")
            self.lblStatus.setText("Stop requested")
        except Exception as e:
            QtWidgets.QMessageBox.critical(self, "Error", str(e))

    # ===== Templates =====
    def refresh_templates(self):
        self.templatePicker.clear()
        for name in sorted(self.templates.templates.keys()):
            self.templatePicker.addItem(name)

    def get_selected_template_task(self) -> dict | None:
        name = self.templatePicker.currentText().strip()
        return self.templates.templates.get(name)

    def enqueue_template(self):
        task = self.get_selected_template_task()
        if not task:
            QtWidgets.QMessageBox.information(self, "No template", "Select a template first")
            return
        # Respect current repo if not set
        task = dict(task)  # shallow copy
        task.setdefault("repo", self.repo_dir())
        self.enqueue_task_dict(task)

    def open_template_in_dialog(self):
        task = self.get_selected_template_task()
        if not task:
            QtWidgets.QMessageBox.information(self, "No template", "Select a template first")
            return
        task = dict(task)
        task.setdefault("repo", self.repo_dir())
        dlg = AddTaskDialog(self.repo_dir(), seed=task, parent=self)
        if dlg.exec() == QtWidgets.QDialog.DialogCode.Accepted:
            self.enqueue_task_dict(dlg.build_task())

    def load_templates_from_disk(self):
        path, _ = QtWidgets.QFileDialog.getOpenFileName(
            self, "Load Templates JSON", self.repo_dir(), "JSON (*.json)"
        )
        if not path:
            return
        self.templates.load(path)

    def try_load_default_templates(self):
        path = os.path.join(self.repo_dir(), DEFAULT_TEMPLATES_REL)
        if os.path.exists(path):
            self.templates.load(path)

    # ===== Task enqueue & retry =====
    def add_task(self):
        dlg = AddTaskDialog(self.repo_dir(), parent=self)
        if dlg.exec() == QtWidgets.QDialog.DialogCode.Accepted:
            self.enqueue_task_dict(dlg.build_task())

    def enqueue_task_dict(self, task: dict):
        inbox = os.path.join(self.tasks_dir(), "inbox")
        os.makedirs(inbox, exist_ok=True)
        tid = task.get("id") or datetime.now().strftime("%Y%m%d%H%M%S")
        task["id"] = tid
        path = os.path.join(inbox, f"task_{tid}.jsonl")
        with open(path, "w", encoding="utf-8") as f:
            f.write(json.dumps(task, ensure_ascii=False) + "\n")
        QtWidgets.QMessageBox.information(self, "Queued", f"Task enqueued:\n{path}")

    def retry_failed(self):
        self.refresh_dlq()  # loads lists
        inbox = os.path.join(self.tasks_dir(), "inbox")
        os.makedirs(inbox, exist_ok=True)
        moved = 0
        for lst in (self.failedList, self.quarantineList):
            for i in range(lst.count()):
                item = lst.item(i)
                if not item:
                    continue
                p = item.data(QtCore.Qt.ItemDataRole.UserRole)
                if p and os.path.isfile(p):
                    try:
                        shutil.move(p, os.path.join(inbox, os.path.basename(p)))
                        moved += 1
                    except Exception:
                        pass
        QtWidgets.QMessageBox.information(self, "Retry", f"Moved {moved} files back to inbox.")

    # ===== DLQ inspector =====
    def refresh_dlq(self):
        self.failedList.clear()
        self.quarantineList.clear()
        failed = os.path.join(self.tasks_dir(), "failed")
        quarant = os.path.join(self.tasks_dir(), "quarantine")
        for folder, widget in [(failed, self.failedList), (quarant, self.quarantineList)]:
            if os.path.isdir(folder):
                for name in sorted(os.listdir(folder)):
                    if name.endswith(".jsonl"):
                        p = os.path.join(folder, name)
                        it = QtWidgets.QListWidgetItem(
                            name
                            + "  ("
                            + datetime.fromtimestamp(os.path.getmtime(p)).strftime(
                                "%Y-%m-%d %H:%M:%S"
                            )
                            + ")"
                        )
                        it.setData(QtCore.Qt.ItemDataRole.UserRole, p)
                        widget.addItem(it)

    def delete_selected_dlq(self):
        total = 0
        for lst in (self.failedList, self.quarantineList):
            for it in lst.selectedItems():
                p = it.data(QtCore.Qt.ItemDataRole.UserRole)
                try:
                    os.remove(p)
                    total += 1
                except Exception:
                    pass
        self.refresh_dlq()
        QtWidgets.QMessageBox.information(self, "Delete", f"Deleted {total} file(s).")

    def retry_selected_dlq(self):
        inbox = os.path.join(self.tasks_dir(), "inbox")
        os.makedirs(inbox, exist_ok=True)
        moved = 0
        for lst in (self.failedList, self.quarantineList):
            for it in lst.selectedItems():
                p = it.data(QtCore.Qt.ItemDataRole.UserRole)
                try:
                    shutil.move(p, os.path.join(inbox, os.path.basename(p)))
                    moved += 1
                except Exception:
                    pass
        self.refresh_dlq()
        QtWidgets.QMessageBox.information(self, "Retry", f"Moved {moved} file(s) to inbox.")

    # ===== Quarantine breakers =====
    def breakers_path(self) -> str:
        return os.path.join(self.state_dir(), "circuit_breakers.json")

    def refresh_breakers(self):
        path = self.breakers_path()
        self.breakerView.setRowCount(0)
        if not os.path.exists(path):
            return
        try:
            data = json.load(open(path, "r", encoding="utf-8"))
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

    def force_close_breaker(self):
        path = self.breakers_path()
        if not os.path.exists(path):
            QtWidgets.QMessageBox.information(self, "No file", "circuit_breakers.json not found")
            return
        try:
            data = json.load(open(path, "r", encoding="utf-8"))
            rows = {
                self.breakerView.item(i, 0).text(): i for i in range(self.breakerView.rowCount())
            }
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
            with open(path, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False)
            self.refresh_breakers()
        except Exception as e:
            QtWidgets.QMessageBox.critical(self, "Error", str(e))

    # ===== Live log & filters =====
    def on_new_log_lines(self, lines: list[str]):
        at_end = (
            self.liveLog.verticalScrollBar().value() == self.liveLog.verticalScrollBar().maximum()
        )
        tool_filter = self.filterTool.currentText().lower()
        text_filter = self.filterText.text().strip().lower()

        for line in lines:
            low = line.lower()
            # tool filter
            if tool_filter != "all":
                # heuristic: include if tool name appears in line, e.g., "[git]" or "git:" or " [git] "
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
                        hint_log = os.path.join(self.logs_dir(), tok)
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
    def load_ledger(self):
        self.ledgerList.clear()
        ledger = os.path.join(self.logs_dir(), "ledger.jsonl")
        if not os.path.exists(ledger):
            self.ledgerList.addItem("ledger.jsonl not found")
            return
        try:
            with open(ledger, "r", encoding="utf-8", errors="replace") as f:
                lines = f.readlines()[-500:]
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

    def check_heartbeat(self):
        hb = os.path.join(self.state_dir(), "heartbeat.json")
        if not os.path.exists(hb):
            self.lblStatus.setText("No heartbeat")
            return
        try:
            data = json.load(open(hb, "r", encoding="utf-8"))
            ts_raw = data.get("timestamp", "")
            if not ts_raw:
                self.lblStatus.setText("Heartbeat: unreadable")
                return
            ts = datetime.fromisoformat(ts_raw.replace("Z", "+00:00"))
            age = (datetime.now(timezone.utc) - ts.astimezone(timezone.utc)).total_seconds()
            pid = data.get("pid", "?")
            self.lblStatus.setText(f"Heartbeat: {int(age)}s ago  |  PID {pid}")
        except Exception:
            self.lblStatus.setText("Heartbeat: unreadable")

    # ===== Misc helpers =====
    def open_folder(self, path: str):
        if not os.path.isdir(path):
            os.makedirs(path, exist_ok=True)
        if sys.platform.startswith("win"):
            os.startfile(path)
        elif sys.platform == "darwin":
            subprocess.call(["open", path])
        else:
            subprocess.call(["xdg-open", path])

    def open_selected_log(self):
        item = self.errorsList.currentItem()
        if not item:
            return
        path = item.data(QtCore.Qt.ItemDataRole.UserRole)
        if path and os.path.isfile(path):
            self.open_folder(os.path.dirname(path))


def main():
    app = QtWidgets.QApplication(sys.argv)
    w = MainWindow()
    w.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
