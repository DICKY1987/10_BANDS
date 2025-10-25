import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest

PyQt6 = pytest.importorskip("PyQt6")
from PyQt6 import QtWidgets  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from QueueManagerGUI_v2 import MainWindow, STATE_DIR  # noqa: E402


@pytest.fixture(scope="module")
def qt_app():
    app = QtWidgets.QApplication.instance()
    if app is None:
        app = QtWidgets.QApplication([])
    yield app


@pytest.fixture
def window(tmp_path, qt_app):
    win = MainWindow()
    win.tailer.stop()
    win.hbTimer.stop()
    win.repoEdit.setText(str(tmp_path))
    win.update_default_paths()
    yield win
    win.close()


def test_check_heartbeat_reads_timestamp(window, tmp_path):
    hb_dir = tmp_path / STATE_DIR
    hb_dir.mkdir(parents=True, exist_ok=True)
    payload = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "pid": 4321,
    }
    hb_file = hb_dir / "heartbeat.json"
    hb_file.write_text(json.dumps(payload), encoding="utf-8")

    window.check_heartbeat()

    status = window.lblStatus.text()
    assert status.startswith("Heartbeat:"), status
    assert "PID 4321" in status


def test_check_heartbeat_handles_missing_file(window):
    hb_file = Path(window.state_dir()) / "heartbeat.json"
    if hb_file.exists():
        hb_file.unlink()

    window.lblStatus.setText("Something else")
    window.check_heartbeat()

    assert window.lblStatus.text() == "No heartbeat"
