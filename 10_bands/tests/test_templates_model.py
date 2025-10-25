import json
import sys
from pathlib import Path

import pytest

PyQt6 = pytest.importorskip("PyQt6")
from PyQt6 import QtWidgets  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from QueueManagerGUI_v2 import TemplatesModel  # noqa: E402


@pytest.fixture(scope="module")
def qt_app():
    app = QtWidgets.QApplication.instance()
    if app is None:
        app = QtWidgets.QApplication([])
    yield app


def test_templates_model_loads_list_structure(tmp_path, qt_app):
    payload = [
        {"name": "Custom", "task": {"tool": "git", "args": ["status"]}},
        {"task": {"tool": "pwsh", "flags": ["-NoProfile"]}},
    ]
    template_path = tmp_path / "templates.json"
    template_path.write_text(json.dumps(payload), encoding="utf-8")

    model = TemplatesModel()
    emitted = []
    model.changed.connect(lambda: emitted.append(True))

    model.load(str(template_path))

    assert emitted, "changed signal should fire when templates load"
    assert model.templates["Custom"]["tool"] == "git"
    assert model.templates["Template 2"]["tool"] == "pwsh"


def test_templates_model_loads_dict_structure(tmp_path, qt_app):
    payload = {
        "Git Fetch": {"tool": "git", "args": ["fetch", "--all"]},
        "Python": {"tool": "python", "args": ["-m", "pip", "list"]},
    }
    template_path = tmp_path / "templates.json"
    template_path.write_text(json.dumps(payload), encoding="utf-8")

    model = TemplatesModel()
    model.load(str(template_path))

    assert set(model.templates.keys()) == {"Git Fetch", "Python"}
    assert model.templates["Python"]["args"] == ["-m", "pip", "list"]


def test_templates_model_builtin_seed(qt_app):
    model = TemplatesModel()
    emitted = []
    model.changed.connect(lambda: emitted.append(True))

    model.builtin()

    assert emitted, "builtin should emit change notification"
    assert "Git: fetch + prune" in model.templates
    assert model.templates["Quality Gate"]["tool"] == "pwsh"
