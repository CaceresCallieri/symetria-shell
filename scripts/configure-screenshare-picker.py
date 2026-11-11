#!/usr/bin/env python3
"""Enable or restore the native Symmetria XDPH picker after shell activation."""

import argparse
import base64
import hashlib
import json
import os
import pwd
import re
import shlex
import subprocess
import tempfile
from pathlib import Path

from screenshare_picker import command, run_cli, shell_ipc

SOURCE = Path(__file__).resolve().parent
NATIVE_PICKER = SOURCE / "screenshare_picker.py"
DESKTOP_ENVIRONMENT_KEYS = ("HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME")


def desktop_environment():
    # The workspace overrides XDG paths. Read the portal's environment, or the
    # user manager's environment when the portal is stopped, instead of os.environ.
    pid = int(
        command(
            [
                "systemctl",
                "--user",
                "show",
                "xdg-desktop-portal-hyprland.service",
                "-p",
                "MainPID",
                "--value",
            ]
        )
        .decode()
        .strip()
    )
    if pid > 0:
        entries = Path(f"/proc/{pid}/environ").read_bytes().split(b"\0")
        raw_values = dict(entry.split(b"=", 1) for entry in entries if b"=" in entry)
        # Decode only desktop paths. Decoding all entries broke every action
        # when an unrelated environment variable contained non-UTF-8 bytes.
        values = {
            key: os.fsdecode(raw_values[key.encode()])
            for key in DESKTOP_ENVIRONMENT_KEYS
            if key.encode() in raw_values
        }
    else:
        environment = command(["systemctl", "--user", "show-environment"]).decode()
        values = dict(
            entry.split("=", 1) for entry in shlex.split(environment) if "=" in entry
        )
        values["HOME"] = pwd.getpwuid(os.getuid()).pw_dir
    return {key: values[key] for key in DESKTOP_ENVIRONMENT_KEYS if key in values}


def desktop_paths():
    desktop = desktop_environment()
    home = Path(desktop.get("HOME") or pwd.getpwuid(os.getuid()).pw_dir)
    install = (
        Path(desktop.get("XDG_DATA_HOME") or home / ".local/share")
        / "symmetria/screenshare-picker"
    )
    config = Path(desktop.get("XDG_CONFIG_HOME") or home / ".config") / "hypr/xdph.conf"
    return install, config


def digest(content):
    return hashlib.sha256(content).hexdigest()


def require_idle_portal():
    objects = json.loads(command(["pw-dump"]))
    clients = {
        str(item["id"])
        for item in objects
        if item.get("info", {}).get("props", {}).get("application.name")
        == "xdg-desktop-portal-hyprland"
    }
    for item in objects:
        props = item.get("info", {}).get("props", {})
        if (
            str(props.get("client.id")) in clients
            and props.get("media.class") == "Video/Source"
        ):
            raise RuntimeError(
                "A screen-share stream exists. Stop it before changing the picker."
            )


def write_file(path, content, mode=0o600):
    if content is None:
        path.unlink(missing_ok=True)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        dir=path.parent, prefix="." + path.name + "-", delete=False
    ) as temporary:
        temporary_path = Path(temporary.name)
        try:
            temporary.write(content)
            temporary.flush()
            temporary_path.chmod(mode)
            temporary_path.replace(path)
        finally:
            temporary_path.unlink(missing_ok=True)


def restart_portal():
    command(
        ["systemctl", "--user", "restart", "xdg-desktop-portal-hyprland.service"],
        timeout=20,
    )


def apply_configuration(config, state_path, content, mode, state):
    previous = config.read_bytes() if config.exists() else None
    previous_mode = config.stat().st_mode & 0o777 if previous is not None else 0o600
    config_written = False
    try:
        write_file(config, content, mode)
        config_written = True
        restart_portal()
        # Commit state last. Failed config writes and failed restarts must leave
        # the previous state intact, including when the rollback restart fails.
        write_file(
            state_path,
            (json.dumps(state, indent=2) + "\n").encode()
            if state is not None
            else None,
        )
    except Exception:
        if config_written:
            write_file(config, previous, previous_mode)
            restart_portal()
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["enable", "disable", "status"])
    action = parser.parse_args().action
    install, config = desktop_paths()
    state_path = install / "activation.json"
    current = config.read_bytes() if config.exists() else None
    current_mode = config.stat().st_mode & 0o777 if current is not None else 0o600
    state = json.loads(state_path.read_text()) if state_path.exists() else None
    managed = (
        state is not None
        and current is not None
        and digest(current) == state["active_config_sha256"]
    )
    enabled = managed and current is not None and str(NATIVE_PICKER).encode() in current
    if action == "status":
        print(
            json.dumps(
                {"enabled": enabled, "config": str(config), "install": str(install)}
            )
        )
        return
    if state and not managed:
        raise RuntimeError(
            "The portal config changed after activation. Keep those edits and restore the picker setting manually."
        )
    if action == "disable" and not state:
        print("The experimental picker is not active.")
        return
    if config.is_symlink():
        raise RuntimeError(
            "The portal config is managed through a symlink. Update its source instead of replacing the symlink."
        )
    if action == "enable":
        try:
            ready = json.loads(shell_ipc("status"))
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            raise RuntimeError(
                "The running shell does not contain the native picker. Restart Symmetria before enabling it."
            ) from error
        if not ready.get("ready") or ready.get("active"):
            raise RuntimeError("The native picker is unavailable or busy.")
    require_idle_portal()
    if action == "disable" and state is not None:
        original = (
            base64.b64decode(state["original_base64"])
            if state["original_exists"]
            else None
        )
        apply_configuration(
            config, state_path, original, state.get("original_mode", current_mode), None
        )
        print("Restored the previous picker.")
        return
    if state is None:
        text = (current or b"").decode()
        if re.search(r"(?m)^\s*(?:screencopy:)?custom_picker_binary\s*=", text):
            raise RuntimeError(
                "A custom picker is already configured. Do not replace it automatically."
            )
        state = {
            "original_exists": current is not None,
            "original_base64": base64.b64encode(current or b"").decode(),
            "original_mode": current_mode,
        }
        active = (
            text.rstrip()
            + "\n\n# Symmetria screen-share picker\nscreencopy {\n    custom_picker_binary = "
            + str(NATIVE_PICKER)
            + "\n}\n"
        ).encode()
    else:
        if current is None:
            raise RuntimeError("The managed portal config is missing.")
        active = re.sub(
            rb"(?m)^(\s*(?:screencopy:)?custom_picker_binary\s*=)[^\n]*",
            lambda match: match[1] + b" " + str(NATIVE_PICKER).encode(),
            current,
        )
    state["active_config_sha256"] = digest(active)
    apply_configuration(config, state_path, active, current_mode, state)
    print(json.dumps({"enabled": True, "config": str(config), "install": str(install)}))


if __name__ == "__main__":
    run_cli(main)
