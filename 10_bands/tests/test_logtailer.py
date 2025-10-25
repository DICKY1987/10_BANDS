import sys
from pathlib import Path

import pytest

PyQt6 = pytest.importorskip("PyQt6")
from PyQt6 import QtWidgets  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from QueueManagerGUI_v2 import LogTailer  # noqa: E402


@pytest.fixture(scope="module")
def qt_app():
    app = QtWidgets.QApplication.instance()
    if app is None:
        app = QtWidgets.QApplication([])
    yield app


def test_logtailer_reads_incrementally(tmp_path, qt_app):
    log_file = tmp_path / "worker.log"
    log_file.write_text("first line\nsecond line\n", encoding="utf-8")

    tailer = LogTailer(str(log_file), poll_ms=5)
    captured = []
    tailer.new_lines.connect(lambda lines: captured.extend(lines))

    tailer._poll()
    assert captured == ["first line", "second line"]

    with log_file.open("a", encoding="utf-8") as handle:
        handle.write("third line\n")

    tailer._poll()
    assert captured[-1] == "third line"
    assert captured.count("third line") == 1


def test_logtailer_detects_rotation(tmp_path, qt_app):
    log_file = tmp_path / "worker.log"
    log_file.write_text("alpha\n", encoding="utf-8")

    tailer = LogTailer(str(log_file), poll_ms=5)
    captured = []
    tailer.new_lines.connect(lambda lines: captured.extend(lines))

    tailer._poll()
    assert captured == ["alpha"]

    # Simulate rotation by truncating the file with new content
    log_file.write_text("beta\n", encoding="utf-8")
    tailer._poll()

    assert captured[-1] == "beta"
    assert captured.count("beta") == 1
