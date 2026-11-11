#!/usr/bin/env python3
"""XDPH custom picker adapter for Symmetria's native screen-sharing layer."""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import math
import os
import secrets
import signal
import socket
import struct
import subprocess
import sys
import tempfile
from collections.abc import Callable
from pathlib import Path
from typing import Any

SHELL_ROOT = Path(__file__).resolve().parents[1]
MAX_MESSAGE_BYTES = 1024 * 1024


def run_cli(entry_point: Callable[[], None]) -> None:
    try:
        entry_point()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Symmetria screen sharing: {error}", file=sys.stderr)
        sys.exit(1)


def command(arguments: list[str], timeout: float = 5, **kwargs: Any) -> bytes:
    # Desktop tools resolve through PATH on Arch and Nix. No shell interprets data.
    return subprocess.check_output(arguments, timeout=timeout, **kwargs)  # noqa: S603


def shell_ipc(function: str, *arguments: str) -> str:
    return (
        command(
            [
                "qs",
                "-p",
                str(SHELL_ROOT / "shell.qml"),
                "ipc",
                "--any-display",
                "call",
                "screenshare",
                function,
                *arguments,
            ]
        )
        .decode()
        .strip()
    )


class ByteReader:
    """Read XDPH's byte-length-prefixed UTF-8 fields without changing opaque IDs."""

    def __init__(self, text: str):
        self.data = text.encode()
        self.offset = 0

    def until(self, separator: bytes) -> str:
        end = self.data.find(separator, self.offset)
        if end < 0:
            raise ValueError("Incomplete portal source list")
        result = self.data[self.offset : end].decode()
        self.offset = end + len(separator)
        return result

    def expect(self, separator: bytes) -> None:
        if self.until(separator):
            raise ValueError("Invalid portal separator")

    def field(self) -> str:
        size = self.until(b":")
        if not size.isascii() or not size.isdecimal():
            raise ValueError("Invalid portal string length")
        end = self.offset + int(size)
        if end > len(self.data):
            raise ValueError("Truncated portal string")
        result = self.data[self.offset : end].decode()
        self.offset = end
        return result


def parse_outputs(text: str) -> list[dict[str, Any]]:
    reader = ByteReader(text)
    result = []
    while reader.offset < len(reader.data):
        name = reader.field()
        reader.expect(b":")
        x, y, width, height = (
            int(reader.until(separator)) for separator in (b":", b":", b":", b";")
        )
        if not name or width <= 0 or height <= 0:
            raise ValueError("Invalid portal output")
        result.append({"name": name, "x": x, "y": y, "width": width, "height": height})
    return result


def parse_workspaces(text: str, version: int = 3) -> list[dict[str, Any]]:
    reader = ByteReader(text)
    result = []
    while reader.offset < len(reader.data):
        outputs = []
        if version == 3:
            identifier = reader.until(b"[HN>]")
            name = reader.field()
            reader.expect(b"[HM>]")
            count = int(reader.until(b":"))
            if not 0 <= count <= 256:
                raise ValueError("Invalid workspace output count")
            outputs = [reader.field() for _ in range(count)]
            reader.expect(b"[HE>]")
        else:
            name = reader.field()
            reader.expect(b":")
            identifier = reader.until(b";")
        if (
            not identifier.isascii()
            or not identifier.isdecimal()
            or not 0 < int(identifier) <= 2**64 - 1
        ):
            raise ValueError("Invalid workspace identifier")
        result.append({"id": identifier, "name": name, "outputs": outputs})
    return result


def parse_windows(text: str) -> list[dict[str, str]]:
    result = []
    while text:
        fields = []
        for separator in ("[HC>]", "[HT>]", "[HE>]", "[HA>]"):
            field, found, text = text.partition(separator)
            if not found:
                raise ValueError("Incomplete portal window list")
            fields.append(field)
        identifier, app, title, address = fields
        if (
            identifier.isascii()
            and identifier.isdecimal()
            and int(identifier) <= 2**32 - 1
        ):
            result.append(
                {
                    "id": identifier,
                    "app": app,
                    "title": title or app,
                    "address": address,
                }
            )
    return result


def address_number(value: str) -> int:
    try:
        return int(value, 16 if value.startswith("0x") else 10)
    except ValueError:
        return 0


def create_context(
    environment: dict[str, str],
    clients: list[dict[str, Any]],
    monitors: list[dict[str, Any]],
    allow_token: bool = False,
) -> dict[str, Any]:
    outputs = parse_outputs(environment.get("XDPH_OUTPUT_SHARING_LIST", ""))
    version = 3 if "XDPH_WORKSPACE_SHARING_LIST_V3" in environment else 2
    workspaces = parse_workspaces(
        environment.get(f"XDPH_WORKSPACE_SHARING_LIST_V{version}", ""), version
    )
    sources: dict[str, list[dict[str, Any]]] = {
        "windows": [],
        "screens": [],
        "workspaces": [],
    }
    for entry in parse_windows(environment.get("XDPH_WINDOW_SHARING_LIST", "")):
        address = address_number(entry["address"])
        client: dict[str, Any] = next(
            (
                item
                for item in clients
                if address and address_number(item.get("address", "")) == address
            ),
            {},
        )
        sources["windows"].append(
            {
                "id": "window:" + entry["id"],
                "title": entry["title"],
                "app": entry["app"],
                "detail": client.get("workspace", {}).get("name", ""),
                "icon": "select_window",
                "selection": "window:" + entry["id"],
                "capture": ["-T", str(client["stableId"])]
                if client.get("stableId")
                else [],
                "captureScale": min(0.25, 720 / max([1, *client.get("size", [])])),
            }
        )
    for output in outputs:
        monitor = next(
            (item for item in monitors if item["name"] == output["name"]), {}
        )
        sources["screens"].append(
            {
                "id": "screen:" + output["name"],
                "title": monitor.get("description", output["name"]),
                "app": output["name"],
                "detail": f"{output['width']} x {output['height']}",
                "icon": "monitor",
                "selection": "screen:" + output["name"],
                "capture": ["-o", output["name"]],
                "captureScale": min(1, 1600 / max(output["width"], output["height"])),
            }
        )
    for workspace in workspaces:
        count = sum(
            client.get("workspace", {}).get("name") == workspace["name"]
            for client in clients
        )
        sources["workspaces"].append(
            {
                "id": "workspace:" + workspace["id"],
                "title": workspace["name"],
                "app": f"{count} {'ventana' if count == 1 else 'ventanas'}",
                "detail": ", ".join(workspace["outputs"]),
                "icon": "workspaces",
                "selection": "workspace-id:" + workspace["id"],
                "capture": [],
            }
        )
    preferred = next(
        (monitor["name"] for monitor in monitors if monitor.get("focused")), ""
    )
    return {
        "sources": sources,
        "outputs": outputs,
        "preferredOutput": preferred,
        "rememberDefault": allow_token,
    }


def placement(monitors: list[dict[str, Any]], parent: dict[str, Any]) -> dict[str, Any]:
    monitor = next(
        (item for item in monitors if item["id"] == parent.get("monitor")), None
    )
    monitor = monitor or next((item for item in monitors if item.get("focused")), None)
    if not monitor:
        raise ValueError("No monitor is available for screen sharing")
    left, top, right, bottom = monitor.get("reserved", [0, 0, 0, 0])
    physical = [monitor["width"], monitor["height"]]
    if monitor.get("transform", 0) % 2:
        physical.reverse()
    width, height = (value / monitor["scale"] for value in physical)
    work_width, work_height = width - left - right, height - top - bottom
    size = parent.get("size", [0, 0])
    if parent.get("mapped") and min(size) > 0:
        x, y = parent["at"][0] - monitor["x"], parent["at"][1] - monitor["y"]
        area_width, area_height = size
    else:
        x, y, area_width, area_height = left, top, work_width, work_height
    dialog_width = min(work_width, max(360, round(area_width * 0.9)))
    dialog_height = min(work_height, max(400, round(area_height * 0.9)))
    return {
        "monitor": monitor["name"],
        "width": dialog_width,
        "height": dialog_height,
        "x": round(
            max(
                left,
                min(
                    left + work_width - dialog_width,
                    x + (area_width - dialog_width) / 2,
                ),
            )
        ),
        "y": round(
            max(
                top,
                min(
                    top + work_height - dialog_height,
                    y + (area_height - dialog_height) / 2,
                ),
            )
        ),
    }


def finite_coordinate(value: Any) -> float:
    if (
        isinstance(value, bool)
        or not isinstance(value, (int, float))
        or not math.isfinite(value)
    ):
        raise ValueError("Invalid region coordinate")
    return float(value)


def serialize_selection(context: dict[str, Any], request: dict[str, Any]) -> str:
    if type(request.get("remember")) is not bool:
        raise ValueError("Invalid remember flag")
    if request.get("mode") == "region":
        output = next(
            (
                item
                for item in context["outputs"]
                if item["name"] == request.get("output")
            ),
            None,
        )
        region = request.get("region")
        if output is None or not isinstance(region, dict):
            raise ValueError("Elegí una pantalla y marcá una región.")
        x, y, width, height = (
            finite_coordinate(region.get(key)) for key in ("x", "y", "width", "height")
        )
        if (
            min(x, y) < 0
            or min(width, height) <= 0
            or x + width > 1.000001
            or y + height > 1.000001
        ):
            raise ValueError("La región está fuera de la pantalla.")
        # Match XDPH's positive half-up pixel rounding, not Python's ties-to-even.
        across, down = output["width"], output["height"]
        left, top = math.floor(x * across + 0.5), math.floor(y * down + 0.5)
        across = min(across - left, math.floor(width * across + 0.5))
        down = min(down - top, math.floor(height * down + 0.5))
        if min(across, down) < 1:
            raise ValueError("La región es demasiado pequeña.")
        selection = f"region:{output['name']}@{left},{top},{across},{down}"
    else:
        sources = context["sources"].get(request.get("mode"), [])
        source = next(
            (item for item in sources if item["id"] == request.get("id")), None
        )
        if source is None:
            raise ValueError("La fuente ya no está disponible.")
        selection = source["selection"]
    return f"[SELECTION]{'r' if request['remember'] else ''}/{selection}\n"


def capture(source: dict[str, Any], directory: Path) -> str:
    if not source.get("capture"):
        return ""
    destination = directory / (secrets.token_hex(12) + ".png")
    try:
        command(
            [
                "grim",
                "-s",
                str(source["captureScale"]),
                *source["capture"],
                str(destination),
            ],
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.SubprocessError):
        destination.unlink(missing_ok=True)
        return ""
    return destination.as_uri()


def send(connection: socket.socket, message: dict[str, Any]) -> None:
    connection.sendall(
        (json.dumps(message, ensure_ascii=False, allow_nan=False) + "\n").encode()
    )


def serve(
    connection: socket.socket, context: dict[str, Any], token: str, directory: Path
) -> str:
    peer = struct.unpack(
        "3i", connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12)
    )
    if peer[1] != os.getuid():
        raise PermissionError("The shell connection belongs to another user")
    connection.settimeout(0.1)
    send(connection, {"type": "context", "token": token, "context": context})
    buffer = b""
    pending: dict[str, concurrent.futures.Future[str]] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
        while True:
            for identifier, future in list(pending.items()):
                if future.done():
                    send(
                        connection,
                        {
                            "type": "thumbnail",
                            "token": token,
                            "id": identifier,
                            "url": future.result(),
                        },
                    )
                    del pending[identifier]
            try:
                data = connection.recv(65536)
            except TimeoutError:
                continue
            if not data:
                return ""
            buffer += data
            if len(buffer) > MAX_MESSAGE_BYTES:
                raise ValueError("Shell message exceeds the limit")
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                message = json.loads(line)
                if not isinstance(message, dict):
                    raise ValueError("Invalid shell message")
                if message.get("token") != token:
                    raise ValueError("Invalid screen-sharing request token")
                if message.get("type") in ("cancel", "confirm"):
                    try:
                        result = (
                            serialize_selection(context, message)
                            if message["type"] == "confirm"
                            else ""
                        )
                    except (ValueError, TypeError, KeyError) as error:
                        send(
                            connection,
                            {"type": "error", "token": token, "message": str(error)},
                        )
                        continue
                    send(connection, {"type": "done", "token": token})
                    for future in pending.values():
                        future.cancel()
                    return result
                if message.get("type") == "thumbnail":
                    source = next(
                        (
                            item
                            for item in context["sources"]["windows"]
                            if item["id"] == message.get("id")
                        ),
                        None,
                    )
                    if source and source["id"] not in pending:
                        pending[source["id"]] = executor.submit(
                            capture, source, directory
                        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--allow-token", action="store_true")
    arguments = parser.parse_args()
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    monitors = json.loads(command(["hyprctl", "monitors", "-j"]))
    clients = json.loads(command(["hyprctl", "clients", "-j"]))
    parent = json.loads(command(["hyprctl", "activewindow", "-j"]))
    context = create_context(dict(os.environ), clients, monitors, arguments.allow_token)
    context["placement"] = placement(monitors, parent)
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    with tempfile.TemporaryDirectory(
        prefix="symmetria-share-", dir=runtime
    ) as temporary:
        directory = Path(temporary)
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
            # Capture screens before the native layer maps to avoid self-capture.
            for source, url in zip(
                context["sources"]["screens"],
                executor.map(
                    lambda item: capture(item, directory), context["sources"]["screens"]
                ),
                strict=True,
            ):
                source["thumbnail"] = url
        token = secrets.token_hex(32)
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
            path = directory / "request.sock"
            server.bind(str(path))
            path.chmod(0o600)
            server.listen(1)
            server.settimeout(10)
            if shell_ipc("open", str(path), token) != "accepted":
                raise RuntimeError(
                    "Symmetria cannot open another screen-sharing request"
                )
            connection, _ = server.accept()
            with connection:
                selection = serve(connection, context, token, directory)
            if selection:
                sys.stdout.write(selection)
                sys.stdout.flush()


if __name__ == "__main__":
    run_cli(main)
