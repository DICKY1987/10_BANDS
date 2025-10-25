#!/usr/bin/env python3
from __future__ import annotations
import logging
import os
import re
import shutil
import subprocess
import sys
import json
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from PyQt6 import QtCore, QtGui, QtWidgets

APP_TITLE = "Headless Queue Manager (v2)"
DEFAULT_REPO = r"C:\Users\Richard Wilks\CLI_RESTART"
DEF_TASKS = ".tasks"
DEF_LOGS = "logs"
STATE_DIR = ".state"

# Optional template search path (auto-loaded if exists)
DEFAULT_TEMPLATES_REL = os.path.join("Config", "TaskTemplates.json")

GUI_LOG_NAME = "QueueManagerGUI.log"
GUI_LOG_MAX_FILES = 10
GUI_LOG_MAX_SIZE = 50 * 1024 * 1024  # 50 MB

DEFAULT_TOOL_FALLBACK = ["git", "aider", "codex", "claude", "pwsh", "python"]

BASE_DIR = Path(__file__).resolve().parent

CONFIG_TOOL_FILES = (
    os.path.join("Config", "CliToolsConfig.psd1"),
    "SharedConfig.psd1",
)


def setup_logging(base_dir: Path) -> Path:
    """Initialise a simple rotating log for the GUI."""

    logs_root = base_dir / STATE_DIR
    logs_root.mkdir(parents=True, exist_ok=True)
    log_path = logs_root / GUI_LOG_NAME

    # Rotate if too large
    if log_path.exists() and log_path.stat().st_size > GUI_LOG_MAX_SIZE:
        for idx in range(GUI_LOG_MAX_FILES - 1, 0, -1):
            older = logs_root / f"{GUI_LOG_NAME}.{idx}"
            newer = logs_root / (f"{GUI_LOG_NAME}.{idx - 1}" if idx - 1 else GUI_LOG_NAME)
            if older.exists():
                older.unlink(missing_ok=True)
            if newer.exists():
                newer.rename(older)
        log_path = logs_root / GUI_LOG_NAME

    logging.basicConfig(
        filename=str(log_path),
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
    )
    logging.getLogger().addHandler(logging.StreamHandler(sys.stdout))
    logging.info("GUI logging initialised at %s", log_path)
    return log_path


def parse_tool_whitelist(text: str) -> set[str]:
    names = set()
    for match in re.finditer(r"Name\s*=\s*'([^']+)'", text):
        names.add(match.group(1).strip())
    # Support simple arrays: ToolWhitelist = @('git','pwsh')
    array_match = re.findall(r"@\(([^)]*)\)", text, re.MULTILINE | re.DOTALL)
    for segment in array_match:
        for raw in re.findall(r"'([^']+)'", segment):
            if re.match(r"^[A-Za-z0-9_\-]+$", raw):
                names.add(raw.strip())
    return names


def load_tool_whitelist(base_dir: Path) -> tuple[list[str], list[str]]:
    """Return (tools, errors)."""

    discovered: set[str] = set()
    errors: list[str] = []
    for rel in CONFIG_TOOL_FILES:
        path = base_dir / rel
        if not path.exists():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except Exception as exc:
            errors.append(f"{path.name}: {exc}")
            logging.error("Failed to read %s: %s", path, exc)
            continue
        parsed = parse_tool_whitelist(text)
        if not parsed:
            errors.append(f"{path.name}: no tool names detected")
        discovered.update(parsed)
    tools = sorted(discovered) if discovered else list(DEFAULT_TOOL_FALLBACK)
    return tools, errors


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


@dataclass
class TemplateRecord:
    name: str
    task: dict
    category: str = "General"
    description: str = ""
    source: str = "builtin"  # builtin | custom | external

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "category": self.category,
            "description": self.description,
            "task": self.task,
            "source": self.source,
        }


class TemplateMetaDialog(QtWidgets.QDialog):
    def __init__(self, categories: list[str], metadata: dict | None = None, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Template Details")
        layout = QtWidgets.QFormLayout(self)

        self.nameEdit = QtWidgets.QLineEdit()
        self.categoryEdit = QtWidgets.QComboBox()
        self.categoryEdit.setEditable(True)
        self.categoryEdit.addItems(sorted({*categories, "General"}))
        self.descEdit = QtWidgets.QPlainTextEdit()
        self.descEdit.setPlaceholderText("Describe what this template does…")

        layout.addRow("Name", self.nameEdit)
        layout.addRow("Category", self.categoryEdit)
        layout.addRow("Description", self.descEdit)

        buttons = QtWidgets.QDialogButtonBox(
            QtWidgets.QDialogButtonBox.StandardButton.Ok
            | QtWidgets.QDialogButtonBox.StandardButton.Cancel
        )
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addRow(buttons)

        if metadata:
            self.nameEdit.setText(metadata.get("name", ""))
            self.categoryEdit.setCurrentText(metadata.get("category", "General"))
            self.descEdit.setPlainText(metadata.get("description", ""))

    def metadata(self) -> dict:
        return {
            "name": self.nameEdit.text().strip(),
            "category": self.categoryEdit.currentText().strip() or "General",
            "description": self.descEdit.toPlainText().strip(),
        }


class TemplateManagerDialog(QtWidgets.QDialog):
    def __init__(
        self,
        manager: TemplatesModel,
        tools: list[str],
        repo_provider,
        parent=None,
    ):
        super().__init__(parent)
        self.setWindowTitle("Manage Templates")
        self.manager = manager
        self.tools = tools
        self.repo_provider = repo_provider

        layout = QtWidgets.QVBoxLayout(self)
        self.tree = QtWidgets.QTreeWidget()
        self.tree.setHeaderLabels(["Template", "Description", "Source"])
        self.tree.header().setSectionResizeMode(0, QtWidgets.QHeaderView.ResizeMode.Stretch)
        self.tree.header().setSectionResizeMode(1, QtWidgets.QHeaderView.ResizeMode.Stretch)
        self.tree.header().setSectionResizeMode(2, QtWidgets.QHeaderView.ResizeMode.ResizeToContents)
        layout.addWidget(self.tree, 1)

        btn_box = QtWidgets.QHBoxLayout()
        self.btnNew = QtWidgets.QPushButton("New")
        self.btnEdit = QtWidgets.QPushButton("Edit")
        self.btnDelete = QtWidgets.QPushButton("Delete")
        self.btnClose = QtWidgets.QPushButton("Close")
        btn_box.addWidget(self.btnNew)
        btn_box.addWidget(self.btnEdit)
        btn_box.addWidget(self.btnDelete)
        btn_box.addStretch(1)
        btn_box.addWidget(self.btnClose)
        layout.addLayout(btn_box)

        self.btnClose.clicked.connect(self.accept)
        self.btnNew.clicked.connect(self.create_template)
        self.btnEdit.clicked.connect(self.edit_template)
        self.btnDelete.clicked.connect(self.delete_template)

        self.manager.changed.connect(self.populate)
        self.populate()

    def populate(self):
        self.tree.clear()
        for category, templates in self.manager.grouped().items():
            cat_item = QtWidgets.QTreeWidgetItem([category])
            cat_item.setFirstColumnSpanned(True)
            self.tree.addTopLevelItem(cat_item)
            for rec in templates:
                child = QtWidgets.QTreeWidgetItem(
                    [rec.name, rec.description or "", rec.source.title()]
                )
                child.setData(0, QtCore.Qt.ItemDataRole.UserRole, (rec.name, rec.category))
                cat_item.addChild(child)
            cat_item.setExpanded(True)

    def selected_record(self) -> TemplateRecord | None:
        item = self.tree.currentItem()
        if not item or not item.parent():
            return None
        key = item.data(0, QtCore.Qt.ItemDataRole.UserRole)
        if not key:
            return None
        name, category = key
        return self.manager.get(name, category)

    def create_template(self):
        self.launch_editor(None)

    def edit_template(self):
        rec = self.selected_record()
        if not rec:
            QtWidgets.QMessageBox.information(
                self,
                "Select Template",
                "Choose a template to edit.",
            )
            return
        self.launch_editor(rec)

    def launch_editor(self, record: TemplateRecord | None):
        seed = record.task if record else None
        dlg = AddTaskDialog(
            repo_path=self.repo_provider() or "",
            tools=self.tools,
            save_template_cb=self.manager,
            seed=seed,
            parent=self,
        )
        if record:
            dlg.setWindowTitle(f"Edit Template: {record.name}")
        if dlg.exec() == QtWidgets.QDialog.DialogCode.Accepted:
            task = dlg.build_task()
            meta = TemplateMetaDialog(
                self.manager.available_categories(),
                metadata={
                    "name": record.name if record else "",
                    "category": record.category if record else "General",
                    "description": record.description if record else "",
                }
                if record
                else None,
                parent=self,
            )
            if meta.exec() == QtWidgets.QDialog.DialogCode.Accepted:
                details = meta.metadata()
                if record and record.source != "custom":
                    details["name"] = f"{record.name} (Custom Copy)"
                self.manager.save_template(details, task)

    def delete_template(self):
        rec = self.selected_record()
        if not rec:
            QtWidgets.QMessageBox.information(
                self,
                "Select Template",
                "Choose a custom template to delete.",
            )
            return
        if rec.source != "custom":
            QtWidgets.QMessageBox.information(
                self,
                "Read-only Template",
                "Built-in and external templates cannot be deleted."
                " Create a copy instead.",
            )
            return
        confirm = QtWidgets.QMessageBox.question(
            self,
            "Confirm Deletion",
            f"Delete template '{rec.name}' from {rec.category}?",
        )
        if confirm == QtWidgets.QMessageBox.StandardButton.Yes:
            self.manager.delete_template(rec.name, rec.category)

class AddTaskDialog(QtWidgets.QDialog):
    def __init__(
        self,
        repo_path: str,
        tools: list[str],
        save_template_cb=None,
        seed: dict | None = None,
        parent=None,
    ):
        super().__init__(parent)
        self.setWindowTitle("Add Task (JSONL)")
        self.setModal(True)
        self.repo_path = repo_path
        self.save_template_cb = save_template_cb
        layout = QtWidgets.QFormLayout(self)

        self.tool = QtWidgets.QComboBox()
        if tools:
            self.tool.addItems(tools)
        else:
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

        if self.save_template_cb:
            self.btnSaveTemplate = btns.addButton(
                "Save as Template", QtWidgets.QDialogButtonBox.ButtonRole.ActionRole
            )
            self.btnSaveTemplate.clicked.connect(self.save_as_template)

        if seed:
            self.apply_seed(seed)

    def save_as_template(self):
        if not self.save_template_cb:
            return
        task = self.build_task()
        if not task:
            return
        meta = TemplateMetaDialog(
            self.save_template_cb.available_categories(),
            parent=self,
        )
        if meta.exec() == QtWidgets.QDialog.DialogCode.Accepted:
            details = meta.metadata()
            if not details["name"]:
                QtWidgets.QMessageBox.warning(
                    self,
                    "Template Name Required",
                    "Please provide a descriptive template name before saving.",
                )
                return
            try:
                self.save_template_cb.save_template(details, task)
                QtWidgets.QMessageBox.information(
                    self,
                    "Template Saved",
                    f"Template '{details['name']}' saved under {details['category']}.",
                )
            except Exception as exc:
                logging.exception("Failed saving template")
                QtWidgets.QMessageBox.critical(
                    self,
                    "Save Failed",
                    f"Unable to save template: {exc}\n"
                    "Check file permissions for the state templates directory.",
                )

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

    def __init__(self, state_dir: Path, parent=None):
        super().__init__(parent)
        self.state_dir = state_dir
        self.custom_path = self.state_dir / "CustomTemplates.json"
        self.records: list[TemplateRecord] = []
        self.load_builtin_defaults()
        self.load_custom()

    # ----- Loading & persistence -----
    def load_builtin_defaults(self):
        defaults = [
            TemplateRecord(
                name="Git: fetch + prune",
                category="Git",
                description="Fetch all remotes, prune stale refs.",
                task={"tool": "git", "args": ["fetch", "--all", "--prune"]},
                source="builtin",
            ),
            TemplateRecord(
                name="Git: status -sb",
                category="Git",
                description="Compact status overview for active repo.",
                task={"tool": "git", "args": ["status", "-sb"]},
                source="builtin",
            ),
            TemplateRecord(
                name="Quality Gate",
                category="Quality",
                description="Run PowerShell quality checks.",
                task={
                    "tool": "pwsh",
                    "args": ["-NoProfile", "-File", "scripts/run_quality.ps1"],
                    "timeout_sec": 1800,
                },
                source="builtin",
            ),
            TemplateRecord(
                name="Aider: refactor stub",
                category="AI",
                description="Invoke aider with a boilerplate refactor prompt.",
                task={
                    "tool": "aider",
                    "flags": ["--yes"],
                    "prompt": "Refactor module for better dependency injection.",
                    "timeout_sec": 1200,
                },
                source="builtin",
            ),
        ]
        self.records = defaults
        self.changed.emit()

    def load_external_json(self, path: Path):
        if not path.exists():
            return
        try:
            with open(path, "r", encoding="utf-8") as handle:
                data = json.load(handle)
        except Exception as exc:
            logging.error("Unable to load templates from %s: %s", path, exc)
            return

        new_records: list[TemplateRecord] = []
        if isinstance(data, dict) and "templates" in data:
            source_entries = data["templates"]
        else:
            source_entries = data

        if isinstance(source_entries, dict):
            for name, task in source_entries.items():
                new_records.append(
                    TemplateRecord(name=name, task=task, category="General", source="external")
                )
        elif isinstance(source_entries, list):
            for item in source_entries:
                if not isinstance(item, dict):
                    continue
                task = item.get("task", {})
                name = item.get("name") or item.get("title") or "Template"
                new_records.append(
                    TemplateRecord(
                        name=name,
                        task=task,
                        category=item.get("category", "General"),
                        description=item.get("description", ""),
                        source="external",
                    )
                )

        # Remove previous external records and extend
        self.records = [rec for rec in self.records if rec.source != "external"] + new_records
        self.changed.emit()

    def load_custom(self):
        if not self.custom_path.exists():
            return
        try:
            with open(self.custom_path, "r", encoding="utf-8") as handle:
                data = json.load(handle)
        except Exception as exc:
            logging.error("Unable to load custom templates: %s", exc)
            return

        new_records: list[TemplateRecord] = []
        items = data.get("templates") if isinstance(data, dict) else data
        if isinstance(items, list):
            for item in items:
                if not isinstance(item, dict):
                    continue
                name = item.get("name")
                task = item.get("task", {})
                if not name or not isinstance(task, dict):
                    continue
                new_records.append(
                    TemplateRecord(
                        name=name,
                        task=task,
                        category=item.get("category", "General"),
                        description=item.get("description", ""),
                        source="custom",
                    )
                )
        self.records = [rec for rec in self.records if rec.source != "custom"] + new_records
        self.changed.emit()

    def save_custom(self):
        payload = {
            "templates": [rec.to_dict() for rec in self.records if rec.source == "custom"],
        }
        try:
            self.custom_path.parent.mkdir(parents=True, exist_ok=True)
            with open(self.custom_path, "w", encoding="utf-8") as handle:
                json.dump(payload, handle, indent=2, ensure_ascii=False)
        except Exception as exc:
            logging.error("Unable to persist custom templates: %s", exc)

    # ----- Queries -----
    def available_categories(self) -> list[str]:
        return sorted({rec.category for rec in self.records} or {"General"})

    def grouped(self) -> dict[str, list[TemplateRecord]]:
        groups: dict[str, list[TemplateRecord]] = defaultdict(list)
        for rec in self.records:
            groups[rec.category].append(rec)
        for recs in groups.values():
            recs.sort(key=lambda r: r.name.lower())
        return dict(sorted(groups.items(), key=lambda kv: kv[0].lower()))

    def get(self, name: str, category: str) -> TemplateRecord | None:
        for rec in self.records:
            if rec.name == name and rec.category == category:
                return rec
        return None

    # ----- Mutations -----
    def save_template(self, metadata: dict, task: dict):
        rec = TemplateRecord(
            name=metadata.get("name", "Unnamed"),
            task=task,
            category=metadata.get("category", "General") or "General",
            description=metadata.get("description", ""),
            source="custom",
        )
        self.records = [
            existing
            for existing in self.records
            if not (existing.name == rec.name and existing.category == rec.category)
            or existing.source != "custom"
        ]
        self.records.append(rec)
        self.save_custom()
        self.changed.emit()

    def delete_template(self, name: str, category: str):
        removed = False
        filtered: list[TemplateRecord] = []
        for rec in self.records:
            if rec.name == name and rec.category == category and rec.source == "custom":
                removed = True
                continue
            filtered.append(rec)
        if removed:
            self.records = filtered
            self.save_custom()
            self.changed.emit()

    def set_state_dir(self, state_dir: Path):
        if self.state_dir == state_dir:
            return
        self.state_dir = state_dir
        self.custom_path = self.state_dir / "CustomTemplates.json"
        self.load_custom()



class MainWindow(QtWidgets.QMainWindow):
    def __init__(self):
        super().__init__()
        self.baseDir = BASE_DIR
        self.settings = QtCore.QSettings("10_Bands", "QueueManagerGUI")
        self.toolList, self.toolErrors = load_tool_whitelist(self.baseDir)
        self.configWatcher = QtCore.QFileSystemWatcher(self)
        self.configWatcher.fileChanged.connect(self.reload_tool_list)
        self.configWatcher.directoryChanged.connect(self.reload_tool_list)
        watch_paths = []
        for rel in CONFIG_TOOL_FILES:
            p = (self.baseDir / rel).resolve()
            if p.exists():
                watch_paths.append(str(p))
        if watch_paths:
            self.configWatcher.addPaths(watch_paths)

        self.setWindowTitle(APP_TITLE)
        self.resize(1320, 860)

        # === Top paths & control ===
        repo_default = self.settings.value("paths/repo", DEFAULT_REPO)
        tasks_default = self.settings.value("paths/tasks", "")
        logs_default = self.settings.value("paths/logs", "")
        self.repoEdit = QtWidgets.QLineEdit(str(repo_default))
        self.tasksEdit = QtWidgets.QLineEdit(str(tasks_default))
        self.logsEdit = QtWidgets.QLineEdit(str(logs_default))
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
        self.btnLaunchTerminal = QtWidgets.QPushButton("Launch Terminal Layout")
        self.btnStart.clicked.connect(self.start_worker)
        self.btnStop.clicked.connect(self.stop_worker)
        self.btnAdd.clicked.connect(self.add_task)
        self.btnRetryFailed.clicked.connect(self.retry_failed)
        self.btnOpenTasks.clicked.connect(lambda: self.open_folder(self.tasks_dir()))
        self.btnOpenLogs.clicked.connect(lambda: self.open_folder(self.logs_dir()))
        self.btnLaunchTerminal.clicked.connect(self.launch_terminal_layout)

        # Filters
        self.filterTool = QtWidgets.QComboBox()
        self.filterTool.addItems(["All", *self.toolList])
        self.filterText = QtWidgets.QLineEdit()
        self.filterText.setPlaceholderText("Filter text…")

        # Templates
        self.templates = TemplatesModel(Path(repo_default) / STATE_DIR, self)
        self.templateTree = QtWidgets.QTreeWidget()
        self.templateTree.setColumnCount(1)
        self.templateTree.setHeaderHidden(True)
        self.templateTree.setSelectionMode(
            QtWidgets.QAbstractItemView.SelectionMode.SingleSelection
        )
        self.templates.changed.connect(self.refresh_templates)
        self.refresh_templates()
        self.btnEnqueueTemplate = QtWidgets.QPushButton("Enqueue Template")
        self.btnEditTemplate = QtWidgets.QPushButton("Open in Dialog")
        self.btnLoadTemplates = QtWidgets.QPushButton("Load Templates.json…")
        self.btnManageTemplates = QtWidgets.QPushButton("Manage…")
        self.btnEnqueueTemplate.clicked.connect(self.enqueue_template)
        self.btnEditTemplate.clicked.connect(self.open_template_in_dialog)
        self.btnLoadTemplates.clicked.connect(self.load_templates_from_disk)
        self.btnManageTemplates.clicked.connect(self.manage_templates)

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
        hb.addWidget(self.btnLaunchTerminal)
        hb.addSpacing(20)
        hb.addWidget(QtWidgets.QLabel("Filter:"))
        hb.addWidget(self.filterTool)
        hb.addWidget(self.filterText)

        tbar = QtWidgets.QWidget()
        tb = QtWidgets.QHBoxLayout(tbar)
        tb.addWidget(QtWidgets.QLabel("Templates:"))
        tb.addWidget(self.templateTree, 2)
        tb.addWidget(self.btnEnqueueTemplate)
        tb.addWidget(self.btnEditTemplate)
        tb.addStretch(1)
        tb.addWidget(self.btnLoadTemplates)
        tb.addWidget(self.btnManageTemplates)

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
        geometry = self.settings.value("window/geometry")
        if geometry is not None:
            self.restoreGeometry(QtCore.QByteArray(geometry))
        win_state = self.settings.value("window/state")
        if win_state is not None:
            self.restoreState(QtCore.QByteArray(win_state))
        self.reload_tool_list()

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
            try:
                os.makedirs(p, exist_ok=True)
            except Exception as exc:
                logging.error("Unable to create directory %s: %s", p, exc)
        self.tailer.path = os.path.join(self.logs_dir(), "queueworker.log")
        self.refresh_breakers()
        try:
            self.templates.set_state_dir(Path(self.state_dir()))
            self.try_load_default_templates()
        except Exception as exc:
            logging.error("Template state update failed: %s", exc)

    # ===== UI actions =====
    def choose_repo(self):
        d = QtWidgets.QFileDialog.getExistingDirectory(self, "Choose Repo", self.repo_dir())
        if d:
            self.repoEdit.setText(d)
            self.settings.setValue("paths/repo", d)
            self.update_default_paths()

    def choose_tasks(self):
        d = QtWidgets.QFileDialog.getExistingDirectory(self, "Choose .tasks", self.tasks_dir())
        if d:
            self.tasksEdit.setText(d)
            self.settings.setValue("paths/tasks", d)

    def choose_logs(self):
        d = QtWidgets.QFileDialog.getExistingDirectory(self, "Choose logs", self.logs_dir())
        if d:
            self.logsEdit.setText(d)
            self.tailer.path = os.path.join(self.logs_dir(), "queueworker.log")
            self.settings.setValue("paths/logs", d)

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
        self.templateTree.clear()
        for category, records in self.templates.grouped().items():
            cat_item = QtWidgets.QTreeWidgetItem([category])
            cat_item.setFirstColumnSpanned(True)
            self.templateTree.addTopLevelItem(cat_item)
            for rec in records:
                label = rec.name
                child = QtWidgets.QTreeWidgetItem([label])
                child.setToolTip(0, rec.description or rec.name)
                child.setData(0, QtCore.Qt.ItemDataRole.UserRole, (rec.name, rec.category))
                cat_item.addChild(child)
            cat_item.setExpanded(True)

    def current_template_record(self) -> TemplateRecord | None:
        item = self.templateTree.currentItem()
        if not item or not item.parent():
            return None
        key = item.data(0, QtCore.Qt.ItemDataRole.UserRole)
        if not key:
            return None
        name, category = key
        return self.templates.get(name, category)

    def enqueue_template(self):
        rec = self.current_template_record()
        if not rec:
            QtWidgets.QMessageBox.information(self, "No template", "Select a template first")
            return
        # Respect current repo if not set
        task = dict(rec.task)
        task.setdefault("repo", self.repo_dir())
        self.enqueue_task_dict(task)

    def open_template_in_dialog(self):
        rec = self.current_template_record()
        if not rec:
            QtWidgets.QMessageBox.information(self, "No template", "Select a template first")
            return
        task = dict(rec.task)
        task.setdefault("repo", self.repo_dir())
        dlg = AddTaskDialog(
            self.repo_dir(),
            self.toolList,
            self.templates,
            seed=task,
            parent=self,
        )
        if dlg.exec() == QtWidgets.QDialog.DialogCode.Accepted:
            self.enqueue_task_dict(dlg.build_task())

    def load_templates_from_disk(self):
        path, _ = QtWidgets.QFileDialog.getOpenFileName(
            self, "Load Templates JSON", self.repo_dir(), "JSON (*.json)"
        )
        if not path:
            return
        self.templates.load_external_json(Path(path))

    def try_load_default_templates(self):
        path = Path(self.repo_dir()) / DEFAULT_TEMPLATES_REL
        if path.exists():
            self.templates.load_external_json(path)

    def manage_templates(self):
        dlg = TemplateManagerDialog(self.templates, self.toolList, self.repo_dir, self)
        dlg.exec()

    def reload_tool_list(self, *_):
        tools, errors = load_tool_whitelist(self.baseDir)
        self.toolList = tools
        self.toolErrors = errors
        if hasattr(self, "filterTool"):
            current = self.filterTool.currentText()
            self.filterTool.blockSignals(True)
            self.filterTool.clear()
            self.filterTool.addItems(["All", *self.toolList])
            if current in self.toolList or current == "All":
                self.filterTool.setCurrentText(current)
            else:
                self.filterTool.setCurrentIndex(0)
            self.filterTool.blockSignals(False)
        if errors and hasattr(self, "status"):
            self.status.showMessage(
                "Tool config issues detected; using fallback list.",
                5000,
            )

    # ===== Task enqueue & retry =====
    def add_task(self):
        dlg = AddTaskDialog(self.repo_dir(), self.toolList, self.templates, parent=self)
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

    def closeEvent(self, event: QtGui.QCloseEvent):
        self.settings.setValue("window/geometry", self.saveGeometry())
        self.settings.setValue("window/state", self.saveState())
        super().closeEvent(event)

    def launch_terminal_layout(self):
        if os.name != "nt":
            QtWidgets.QMessageBox.information(
                self,
                "Windows Terminal Required",
                "The terminal layout shortcut requires Windows Terminal (wt).",
            )
            return
        try:
            subprocess.Popen(["wt", "-p", "10_Bands"])
        except FileNotFoundError:
            QtWidgets.QMessageBox.warning(
                self,
                "wt not found",
                "Windows Terminal (wt) was not found on PATH. Install it or update PATH.",
            )
        except Exception as exc:
            QtWidgets.QMessageBox.critical(
                self,
                "Failed to launch",
                f"Unable to launch Windows Terminal: {exc}",
            )


def main():
    setup_logging(BASE_DIR)
    app = QtWidgets.QApplication(sys.argv)
    w = MainWindow()
    w.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()

