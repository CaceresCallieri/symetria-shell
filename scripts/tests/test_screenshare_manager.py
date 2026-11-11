import contextlib
import importlib.util
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from scripts import screenshare_picker

MODULE_PATH = Path(__file__).parents[1] / "configure-screenshare-picker.py"
SPEC = importlib.util.spec_from_file_location("screenshare_manager", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
manager = importlib.util.module_from_spec(SPEC)
with (
    patch(
        "subprocess.check_output",
        side_effect=AssertionError("Import must not contact the desktop"),
    ),
    patch.dict(sys.modules, {"screenshare_picker": screenshare_picker}),
):
    SPEC.loader.exec_module(manager)


class ManagerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.install = self.root / "install"
        self.config = self.root / "config" / "xdph.conf"
        self.state = self.install / "activation.json"
        self.addCleanup(patch.stopall)
        patch.object(
            manager, "desktop_paths", return_value=(self.install, self.config)
        ).start()
        self.ready = patch.object(
            manager, "shell_ipc", return_value='{"ready": true, "active": false}'
        ).start()
        self.restart = patch.object(manager, "restart_portal").start()
        self.graph = patch.object(
            manager.subprocess, "check_output", return_value=b"[]"
        ).start()

    def action(self, action):
        with (
            patch.object(sys, "argv", [str(MODULE_PATH), action]),
            contextlib.redirect_stdout(io.StringIO()) as output,
        ):
            manager.main()
        return output.getvalue()

    def original_config(self, mode=0o640):
        self.config.parent.mkdir(parents=True)
        original = b"# Existing portal settings\nscreencopy {\n    max_fps = 60\n}\n"
        self.config.write_bytes(original)
        self.config.chmod(mode)
        return original

    def assert_mode(self, mode):
        self.assertEqual(self.config.stat().st_mode & 0o777, mode)

    def test_enable_repeat_and_restore_existing_content_and_mode(self):
        original = self.original_config()
        self.action("enable")
        active = self.config.read_bytes()
        self.assertIn(b"custom_picker_binary", active)
        self.assert_mode(0o640)
        self.assertEqual(json.loads(self.state.read_text())["original_mode"], 0o640)
        self.action("enable")
        self.assertEqual(self.config.read_bytes(), active)
        self.assertIn(str(manager.NATIVE_PICKER).encode(), active)
        self.action("disable")
        self.assertEqual(self.config.read_bytes(), original)
        self.assert_mode(0o640)
        self.assertFalse(self.state.exists())

    def test_restore_missing_original_and_legacy_activation_state(self):
        self.action("enable")
        state = json.loads(self.state.read_text())
        state.pop("original_mode")
        self.state.write_text(json.dumps(state))
        self.action("disable")
        self.assertFalse(self.config.exists())
        self.assertFalse(self.state.exists())

    def test_refuse_modified_owned_config(self):
        self.action("enable")
        changed = self.config.read_bytes() + b"# User edit\n"
        self.config.write_bytes(changed)
        self.restart.reset_mock()
        for action in ["enable", "disable"]:
            with (
                self.subTest(action=action),
                self.assertRaisesRegex(RuntimeError, "config changed"),
            ):
                self.action(action)
        self.assertEqual(self.config.read_bytes(), changed)
        self.restart.assert_not_called()

    def test_refuse_symlink_without_replacing_it(self):
        target = self.root / "owned.conf"
        target.write_bytes(b"# Managed elsewhere\n")
        self.config.parent.mkdir()
        self.config.symlink_to(target)
        with self.assertRaisesRegex(RuntimeError, "symlink"):
            self.action("enable")
        self.assertTrue(self.config.is_symlink())
        self.assertEqual(target.read_bytes(), b"# Managed elsewhere\n")
        self.restart.assert_not_called()

    def test_refuse_both_existing_picker_syntaxes(self):
        self.config.parent.mkdir()
        for value in [
            b"screencopy {\n custom_picker_binary = /existing\n}\n",
            b"screencopy:custom_picker_binary = /existing\n",
        ]:
            with self.subTest(value=value):
                self.config.write_bytes(value)
                with self.assertRaisesRegex(RuntimeError, "already configured"):
                    self.action("enable")
                self.assertEqual(self.config.read_bytes(), value)
        self.assertFalse(self.state.exists())
        self.restart.assert_not_called()

    def test_active_video_source_blocks_enable_before_any_write(self):
        self.graph.return_value = json.dumps(
            [
                {
                    "id": 7,
                    "info": {
                        "props": {"application.name": "xdg-desktop-portal-hyprland"}
                    },
                },
                {
                    "id": 8,
                    "info": {"props": {"client.id": 7, "media.class": "Video/Source"}},
                },
            ]
        ).encode()
        with self.assertRaisesRegex(RuntimeError, "stream exists"):
            self.action("enable")
        self.graph.assert_called_once_with(["pw-dump"], timeout=5)
        self.assertFalse(self.config.exists())
        self.assertFalse(self.install.exists())
        self.restart.assert_not_called()

    def test_failed_restart_restores_content_mode_and_previous_state(self):
        original = self.original_config()
        self.restart.side_effect = [RuntimeError("restart failed"), None]
        with self.assertRaisesRegex(RuntimeError, "restart failed"):
            self.action("enable")
        self.assertEqual(self.config.read_bytes(), original)
        self.assert_mode(0o640)
        self.assertFalse(self.state.exists())
        self.assertEqual(self.restart.call_count, 2)

    def test_failed_rollback_restart_does_not_leave_stale_state(self):
        self.restart.side_effect = RuntimeError("all restarts failed")
        with self.assertRaisesRegex(RuntimeError, "all restarts failed"):
            self.action("enable")
        self.assertFalse(self.config.exists())
        self.assertFalse(self.state.exists())

    def test_config_write_failure_leaves_state_and_config_unchanged(self):
        original = self.original_config()
        write_file = manager.write_file

        def fail_config(path, content, mode=0o600):
            if path == self.config:
                raise OSError("config write failed")
            return write_file(path, content, mode)

        with (
            patch.object(manager, "write_file", side_effect=fail_config),
            self.assertRaisesRegex(OSError, "config write failed"),
        ):
            self.action("enable")
        self.assertEqual(self.config.read_bytes(), original)
        self.assertFalse(self.state.exists())
        self.restart.assert_not_called()

    def test_state_write_failure_rolls_back_the_config(self):
        original = self.original_config()
        write_file = manager.write_file

        def fail_state(path, content, mode=0o600):
            if path == self.state:
                raise OSError("state write failed")
            return write_file(path, content, mode)

        with (
            patch.object(manager, "write_file", side_effect=fail_state),
            self.assertRaisesRegex(OSError, "state write failed"),
        ):
            self.action("enable")
        self.assertEqual(self.config.read_bytes(), original)
        self.assert_mode(0o640)
        self.assertFalse(self.state.exists())
        self.assertEqual(self.restart.call_count, 2)

    def test_disable_restart_failure_keeps_previous_activation(self):
        self.action("enable")
        active = self.config.read_bytes()
        state = self.state.read_bytes()
        self.restart.side_effect = [RuntimeError("disable restart failed"), None]
        with self.assertRaisesRegex(RuntimeError, "disable restart failed"):
            self.action("disable")
        self.assertEqual(self.config.read_bytes(), active)
        self.assertEqual(self.state.read_bytes(), state)

    def test_stopped_portal_uses_manager_xdg_paths_and_account_home(self):
        self.graph.side_effect = [
            b"0\n",
            b'HOME=/wrong\nXDG_CONFIG_HOME="/desktop config"\nXDG_DATA_HOME=/desktop-data\n',
        ]
        with patch.object(
            manager.pwd,
            "getpwuid",
            return_value=SimpleNamespace(pw_dir="/account-home"),
        ):
            desktop = manager.desktop_environment()
        self.assertEqual(
            desktop,
            {
                "HOME": "/account-home",
                "XDG_CONFIG_HOME": "/desktop config",
                "XDG_DATA_HOME": "/desktop-data",
            },
        )

    def test_running_portal_uses_its_process_environment(self):
        self.graph.return_value = b"123\n"
        with patch.object(
            Path,
            "read_bytes",
            return_value=b"HOME=/desktop-home\0XDG_CONFIG_HOME=/desktop-config\0XDG_DATA_HOME=/desktop-data\0",
        ):
            desktop = manager.desktop_environment()
        self.assertEqual(desktop["HOME"], "/desktop-home")
        self.assertEqual(desktop["XDG_CONFIG_HOME"], "/desktop-config")

    def test_running_portal_ignores_unrelated_non_utf8_environment(self):
        self.graph.return_value = b"123\n"
        with patch.object(
            Path,
            "read_bytes",
            return_value=b"HOME=/desktop-home\0LEGACY=caf\xe9\0XDG_CONFIG_HOME=/desktop-config\0XDG_DATA_HOME=/desktop-data\0",
        ):
            desktop = manager.desktop_environment()
        self.assertEqual(
            desktop,
            {
                "HOME": "/desktop-home",
                "XDG_CONFIG_HOME": "/desktop-config",
                "XDG_DATA_HOME": "/desktop-data",
            },
        )

    def test_migrate_owned_electron_config_and_keep_original_backup(self):
        original = self.original_config()
        self.action("enable")
        state = json.loads(self.state.read_text())
        legacy = self.config.read_bytes().replace(
            str(manager.NATIVE_PICKER).encode(), b"/old/screenshare-picker"
        )
        self.config.write_bytes(legacy)
        state["active_config_sha256"] = manager.digest(legacy)
        self.state.write_text(json.dumps(state))
        original_record = state["original_base64"]
        self.action("enable")
        self.assertNotIn(b"/old/screenshare-picker", self.config.read_bytes())
        self.assertEqual(
            json.loads(self.state.read_text())["original_base64"], original_record
        )
        self.action("disable")
        self.assertEqual(self.config.read_bytes(), original)

    def test_native_shell_must_be_ready_before_any_change(self):
        self.ready.side_effect = OSError("target not loaded")
        with self.assertRaisesRegex(RuntimeError, "Restart Symmetria"):
            self.action("enable")
        self.assertFalse(self.config.exists())
        self.assertFalse(self.state.exists())
        self.restart.assert_not_called()

    def test_busy_native_shell_blocks_activation(self):
        self.ready.return_value = '{"ready": true, "active": true}'
        with self.assertRaisesRegex(RuntimeError, "unavailable or busy"):
            self.action("enable")
        self.assertFalse(self.config.exists())
        self.restart.assert_not_called()


if __name__ == "__main__":
    unittest.main()
