import importlib.util
import os
import subprocess
from pathlib import Path
from unittest.mock import Mock

import pytest

spec = importlib.util.spec_from_file_location(
    "lock_watchdog", Path(__file__).resolve().parents[1] / "lock-watchdog.py"
)
assert spec and spec.loader
watchdog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watchdog)


@pytest.mark.parametrize(
    "unlocked, expected", [(True, []), (False, ["screencopy_blank"])]
)
def test_unreadable_heartbeat_does_not_rearm_alarm(monkeypatch, unlocked, expected):
    sample = {"locked": True, "pid": os.getpid(), "screencopyHealthy": False}
    samples = iter([sample, sample, None, sample, sample])
    now = iter(range(100, 200))
    monkeypatch.setattr(watchdog.time, "sleep", lambda _: None)
    monkeypatch.setattr(watchdog.time, "time", lambda: next(now))
    monkeypatch.setattr(watchdog, "read_heartbeat", lambda: (next(samples), 100))
    monkeypatch.setattr(watchdog, "STALE_SECS", 100)
    monkeypatch.setattr(watchdog, "UNHEALTHY_SECS", 0)
    monkeypatch.setattr(watchdog, "compositor_unlocked", lambda: unlocked)
    monkeypatch.setattr(watchdog, "log_event", Mock())
    alerts = []
    monkeypatch.setattr(watchdog, "notify", alerts.append)
    with pytest.raises(StopIteration):
        watchdog.main()
    assert alerts == expected


@pytest.mark.parametrize(
    "output, expected",
    [
        (b'{"locked":false}', True),
        (b'{"locked":true}', False),
        (b'{"locked":0}', False),
        (b"garbage", False),
    ],
)
def test_compositor_response(monkeypatch, output, expected):
    run = Mock(return_value=Mock(stdout=output))
    monkeypatch.setattr(watchdog.subprocess, "run", run)
    assert watchdog.compositor_unlocked() is expected
    run.assert_called_once_with(
        ["hyprctl", "-j", "locked"], capture_output=True, timeout=2, check=True
    )


@pytest.mark.parametrize(
    "error",
    [
        subprocess.TimeoutExpired("hyprctl", 2),
        subprocess.CalledProcessError(1, "hyprctl"),
    ],
)
def test_unavailable_compositor_preserves_alarm(monkeypatch, error):
    monkeypatch.setattr(watchdog.subprocess, "run", Mock(side_effect=error))
    assert not watchdog.compositor_unlocked()


def test_confirmed_unlock_rearms_for_later_crash(monkeypatch):
    sample = {"locked": True, "pid": os.getpid(), "screencopyHealthy": False}
    samples = iter([sample, sample, None, sample, dict(sample, pid=-1)])
    compositor = iter([False, True, False])
    monkeypatch.setattr(watchdog, "compositor_unlocked", lambda: next(compositor))
    monkeypatch.setattr(watchdog, "read_heartbeat", lambda: (next(samples), 100))
    monkeypatch.setattr(watchdog.time, "sleep", lambda _: None)
    monkeypatch.setattr(watchdog.time, "time", lambda: 100)
    monkeypatch.setattr(watchdog, "UNHEALTHY_SECS", -1)
    monkeypatch.setattr(watchdog, "log_event", Mock())
    alerts = []
    monkeypatch.setattr(watchdog, "notify", alerts.append)
    with pytest.raises(StopIteration):
        watchdog.main()
    assert alerts == ["screencopy_blank", "qs_dead"]
