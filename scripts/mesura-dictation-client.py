#!/usr/bin/env python3
"""Bridge Symmetria Shell to all local Mesura dictation sockets.

The helper speaks newline-delimited JSON on both sides. Mesura wire messages
stay inside each `message` sent on stdin. Events written to stdout add the
owning Mesura process id so QML can keep concurrent desktop processes apart.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import re
import signal
import socket
import sys
import threading
from pathlib import Path
from typing import Any, TextIO

PROTOCOL_VERSION = {"major": 1, "minor": 5}
SOCKET_NAME = re.compile(r"^symmetria-mesura-dictation-(\d+)\.sock$")
DISCOVERY_INTERVAL_SECONDS = 0.25
RETRYABLE_FAILURE_CODES = frozenset(
    {"provider_start_failed", "persistence_failed", "deadline_exceeded"}
)


def discover_socket_paths(runtime_dir: Path) -> dict[int, Path]:
    """Return exact PID-scoped Mesura dictation socket candidates."""
    discovered: dict[int, Path] = {}
    with contextlib.suppress(OSError):
        for path in runtime_dir.iterdir():
            match = SOCKET_NAME.fullmatch(path.name)
            if match is not None:
                discovered[int(match.group(1))] = path
    return discovered


def build_reservation_request(
    *, session_id: str, command_id: str, source: str, created_at: str
) -> dict[str, object]:
    """Build the reservation frame used before the Shell opens the mic."""
    return {
        "type": "dictation.reserve.request",
        "protocolVersion": dict(PROTOCOL_VERSION),
        "sessionId": session_id,
        "commandId": command_id,
        "createdAt": created_at,
        "source": source,
    }


def build_hello() -> dict[str, object]:
    return {
        "type": "dictation.hello",
        "protocolVersion": dict(PROTOCOL_VERSION),
        "capabilities": [
            "session-control",
            "mode-selection",
            "target-reservation",
            "delivery-receipts",
        ],
    }


def parse_server_message(peer_pid: int, line: str) -> dict[str, Any]:
    """Validate one Mesura frame and normalize it for QML."""
    try:
        message = json.loads(line)
    except (TypeError, json.JSONDecodeError) as error:
        return {
            "type": "client.error",
            "peerPid": peer_pid,
            "code": "malformed_input",
            "detail": str(error),
        }
    if not isinstance(message, dict) or not isinstance(message.get("type"), str):
        return {
            "type": "client.error",
            "peerPid": peer_pid,
            "code": "malformed_input",
            "detail": "Mesura sent a non-object frame",
        }

    message_type = message["type"]
    if message_type == "dictation.hello":
        version = message.get("protocolVersion")
        if (
            not isinstance(version, dict)
            or version.get("major") != PROTOCOL_VERSION["major"]
        ):
            return {
                "type": "client.error",
                "peerPid": peer_pid,
                "code": "unsupported_protocol",
                "detail": "Mesura announced an unsupported dictation protocol",
            }
        return {
            "type": "hello",
            "peerPid": peer_pid,
            "protocolVersion": version,
            "capabilities": message.get("capabilities", []),
        }
    if message_type == "dictation.snapshot":
        return {
            "type": "snapshot",
            "peerPid": peer_pid,
            "session": message.get("session"),
        }
    if message_type == "dictation.receipt":
        receipt = message.get("receipt")
        if not isinstance(receipt, dict):
            return {
                "type": "client.error",
                "peerPid": peer_pid,
                "code": "malformed_input",
                "detail": "Mesura sent an invalid dictation receipt",
            }
        normalized_receipt = dict(receipt)
        normalized_receipt["retryable"] = (
            receipt.get("outcome") == "failed"
            and receipt.get("code") in RETRYABLE_FAILURE_CODES
        )
        return {
            "type": "receipt",
            "peerPid": peer_pid,
            "receipt": normalized_receipt,
        }
    if message_type == "dictation.error":
        return {
            "type": "client.error",
            "peerPid": peer_pid,
            "code": message.get("code", "malformed_input"),
            "detail": message.get("detail", "Mesura rejected the dictation request"),
        }
    return {
        "type": "client.error",
        "peerPid": peer_pid,
        "code": "malformed_input",
        "detail": f"unknown Mesura frame {message_type}",
    }


class SnapshotTracker:
    """Expand every pending snapshot action until Mesura observes its exact ack."""

    def events_for(
        self, peer_pid: int, message: dict[str, Any]
    ) -> list[dict[str, Any]]:
        normalized = (
            parse_server_message(peer_pid, json.dumps(message))
            if str(message.get("type", "")).startswith("dictation.")
            else message
        )
        events = [normalized]
        if normalized.get("type") != "snapshot":
            return events
        session = normalized.get("session")
        if not isinstance(session, dict):
            return events
        control = session.get("lastControl")
        if isinstance(control, dict):
            command_id = control.get("commandId")
            action = control.get("action")
            if isinstance(command_id, str) and isinstance(action, str):
                events.append(
                    {
                        "type": "control",
                        "peerPid": peer_pid,
                        "sessionId": session.get("sessionId"),
                        "commandId": command_id,
                        "action": action,
                    }
                )
        vocabulary = session.get("lastVocabulary")
        if isinstance(vocabulary, dict):
            command_id = vocabulary.get("commandId")
            action = vocabulary.get("action")
            if isinstance(command_id, str) and isinstance(action, str):
                events.append(
                    {
                        "type": "vocabulary",
                        "peerPid": peer_pid,
                        "sessionId": session.get("sessionId"),
                        "commandId": command_id,
                        "action": action,
                        **({"word": vocabulary.get("word")} if action == "add" else {}),
                        **(
                            {"index": vocabulary.get("index")}
                            if action == "remove"
                            else {}
                        ),
                    }
                )
        return events


class DictationPeer:
    """One connected Mesura process."""

    def __init__(self, peer_pid: int, socket_path: Path) -> None:
        self.peer_pid = peer_pid
        self.socket_path = socket_path
        self._socket: socket.socket | None = None
        self._reader: TextIO | None = None
        self._write_lock = threading.Lock()

    def __enter__(self) -> DictationPeer:
        connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        connection.connect(str(self.socket_path))
        self._socket = connection
        self._reader = connection.makefile("r", encoding="utf-8")
        self.send(build_hello())
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def close(self) -> None:
        if self._reader is not None:
            self._reader.close()
            self._reader = None
        if self._socket is not None:
            self._socket.close()
            self._socket = None

    def send(self, message: dict[str, Any]) -> None:
        if self._socket is None:
            raise ConnectionError("the Mesura dictation socket is not connected")
        payload = (json.dumps(message, ensure_ascii=False) + "\n").encode()
        with self._write_lock:
            self._socket.sendall(payload)

    def read_event(self) -> dict[str, Any]:
        if self._reader is None:
            raise ConnectionError("the Mesura dictation socket is not connected")
        line = self._reader.readline()
        if line == "":
            raise ConnectionError("the Mesura dictation socket closed")
        return parse_server_message(self.peer_pid, line)


class DictationClient:
    """Discover Mesura peers and multiplex their sessions onto stdout."""

    def __init__(self, runtime_dir: Path) -> None:
        self._runtime_dir = runtime_dir
        self._peers: dict[int, DictationPeer] = {}
        self._peer_paths: dict[int, Path] = {}
        self._connecting: set[int] = set()
        self._lock = threading.Lock()
        self._output_lock = threading.Lock()
        self._stopping = threading.Event()
        self._tracker = SnapshotTracker()

    def emit(self, event: dict[str, Any]) -> None:
        with self._output_lock:
            sys.stdout.write(json.dumps(event, ensure_ascii=False) + "\n")
            sys.stdout.flush()

    def _read_peer(self, peer_pid: int, socket_path: Path) -> None:
        peer = DictationPeer(peer_pid, socket_path)
        try:
            with peer:
                with self._lock:
                    self._peers[peer_pid] = peer
                    self._peer_paths[peer_pid] = socket_path
                opening_event = peer.read_event()
                for tracked in self._tracker.events_for(peer_pid, opening_event):
                    self.emit(tracked)
                self.emit({"type": "peer.connected", "peerPid": peer_pid})
                while not self._stopping.is_set():
                    event = peer.read_event()
                    for tracked in self._tracker.events_for(peer_pid, event):
                        self.emit(tracked)
        except (ConnectionError, OSError) as error:
            if not self._stopping.is_set():
                self.emit(
                    {
                        "type": "peer.disconnected",
                        "peerPid": peer_pid,
                        "detail": str(error),
                    }
                )
        finally:
            with self._lock:
                self._connecting.discard(peer_pid)
                if self._peers.get(peer_pid) is peer:
                    self._peers.pop(peer_pid, None)
                    self._peer_paths.pop(peer_pid, None)

    def _discover(self) -> None:
        while not self._stopping.is_set():
            candidates = discover_socket_paths(self._runtime_dir)
            with self._lock:
                connected_paths = dict(self._peer_paths)
                connecting = set(self._connecting)
            for peer_pid, socket_path in candidates.items():
                if (
                    connected_paths.get(peer_pid) == socket_path
                    or peer_pid in connecting
                ):
                    continue
                with self._lock:
                    self._connecting.add(peer_pid)
                threading.Thread(
                    target=self._read_peer,
                    args=(peer_pid, socket_path),
                    daemon=True,
                    name=f"mesura-dictation-{peer_pid}",
                ).start()
            self._stopping.wait(DISCOVERY_INTERVAL_SECONDS)

    def _handle_stdin(self, raw_line: str) -> None:
        request: object = {}
        try:
            request = json.loads(raw_line)
            if not isinstance(request, dict):
                raise ValueError("expected a request object")
            peer_pid = int(request["peerPid"])
            request_id = request.get("requestId")
            message = request["message"]
            if request.get("type") != "send" or not isinstance(message, dict):
                raise ValueError("expected a send request with a message object")
            with self._lock:
                peer = self._peers.get(peer_pid)
            if peer is None:
                raise ConnectionError("the Mesura dictation broker is unavailable")
            peer.send(message)
            self.emit({"type": "sent", "peerPid": peer_pid, "requestId": request_id})
        except (KeyError, TypeError, ValueError, ConnectionError, OSError) as error:
            self.emit(
                {
                    "type": "client.error",
                    "peerPid": request.get("peerPid")
                    if isinstance(request, dict)
                    else None,
                    "requestId": request.get("requestId")
                    if isinstance(request, dict)
                    else None,
                    "code": "shell_unavailable",
                    "detail": str(error),
                }
            )

    def run(self) -> None:
        threading.Thread(
            target=self._discover, daemon=True, name="mesura-discovery"
        ).start()
        for line in sys.stdin:
            if self._stopping.is_set():
                break
            if line.strip():
                self._handle_stdin(line)
        self.stop()

    def stop(self) -> None:
        self._stopping.set()
        with self._lock:
            peers = list(self._peers.values())
            self._peers.clear()
            self._peer_paths.clear()
            self._connecting.clear()
        for peer in peers:
            peer.close()


def runtime_directory() -> Path:
    configured = os.environ.get("XDG_RUNTIME_DIR")
    return Path(configured) if configured else Path(f"/run/user/{os.getuid()}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-dir", type=Path, default=runtime_directory())
    args = parser.parse_args()
    client = DictationClient(args.runtime_dir)

    def stop_client(_signum: int, _frame: object) -> None:
        client.stop()

    signal.signal(signal.SIGTERM, stop_client)
    signal.signal(signal.SIGINT, stop_client)
    client.run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
