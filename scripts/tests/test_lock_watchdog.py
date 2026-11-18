import importlib.util
import os
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
