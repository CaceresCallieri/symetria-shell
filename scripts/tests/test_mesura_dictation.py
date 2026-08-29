from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import socket
import tempfile
import threading
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "mesura-dictation-client.py"
SPEC = importlib.util.spec_from_file_location("mesura_dictation_client", SCRIPT)
assert SPEC is not None
assert SPEC.loader is not None
CLIENT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CLIENT)


class MesuraDictationProtocolTests(unittest.TestCase):
    def test_discovers_only_pid_scoped_dictation_sockets(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            runtime_dir = Path(directory)
            valid = runtime_dir / "symmetria-mesura-dictation-41.sock"
            other = runtime_dir / "symmetria-mesura-41.sock"
            malformed = runtime_dir / "symmetria-mesura-dictation-nope.sock"
            for path in (valid, other, malformed):
                path.touch()

            self.assertEqual(CLIENT.discover_socket_paths(runtime_dir), {41: valid})

    def test_builds_a_stable_reservation_request(self) -> None:
        request = CLIENT.build_reservation_request(
            session_id="session-a",
            command_id="reserve-a",
            source="shell",
            created_at="2026-08-29T12:00:00.000Z",
        )

        self.assertEqual(
            request,
            {
                "type": "dictation.reserve.request",
                "protocolVersion": {"major": 1, "minor": 4},
                "sessionId": "session-a",
                "commandId": "reserve-a",
                "createdAt": "2026-08-29T12:00:00.000Z",
                "source": "shell",
            },
        )

    def test_rejects_an_unsupported_server_major(self) -> None:
        event = CLIENT.parse_server_message(
            41,
            json.dumps(
                {
                    "type": "dictation.hello",
                    "protocolVersion": {"major": 2, "minor": 0},
                    "capabilities": [],
                }
            ),
        )

        self.assertEqual(event["type"], "client.error")
        self.assertEqual(event["code"], "unsupported_protocol")
        self.assertEqual(event["peerPid"], 41)

    def test_reemits_control_until_an_exact_ack_clears_the_snapshot(self) -> None:
        tracker = CLIENT.SnapshotTracker()
        snapshot = {
            "type": "dictation.snapshot",
            "session": {
                "sessionId": "session-a",
                "phase": "recording",
                "lastControl": {"commandId": "restart-a", "action": "restart"},
            },
        }

        first = tracker.events_for(41, snapshot)
        replay = tracker.events_for(41, snapshot)

        self.assertEqual([event["type"] for event in first], ["snapshot", "control"])
        self.assertEqual(first[1]["action"], "restart")
        self.assertEqual([event["type"] for event in replay], ["snapshot", "control"])

    def test_reemits_vocabulary_until_an_exact_ack_clears_the_snapshot(self) -> None:
        tracker = CLIENT.SnapshotTracker()
        snapshot = {
            "type": "dictation.snapshot",
            "session": {
                "sessionId": "session-a",
                "phase": "recording",
                "lastVocabulary": {
                    "commandId": "vocabulary-a",
                    "action": "add",
                    "word": "Quickshell",
                },
            },
        }

        first = tracker.events_for(41, snapshot)
        replay = tracker.events_for(41, snapshot)

        self.assertEqual([event["type"] for event in first], ["snapshot", "vocabulary"])
        self.assertEqual(first[1]["word"], "Quickshell")
        self.assertEqual(
            [event["type"] for event in replay], ["snapshot", "vocabulary"]
        )

    def test_peer_sends_handshake_and_forwards_the_opening_snapshot(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            socket_path = Path(directory) / "symmetria-mesura-dictation-77.sock"
            ready = threading.Event()
            received: list[dict[str, object]] = []

            def serve() -> None:
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
                    server.bind(str(socket_path))
                    server.listen(1)
                    ready.set()
                    connection, _ = server.accept()
                    with connection:
                        connection.sendall(
                            (
                                json.dumps(
                                    {"type": "dictation.snapshot", "session": None}
                                )
                                + "\n"
                            ).encode()
                        )
                        line = connection.makefile("r", encoding="utf-8").readline()
                        received.append(json.loads(line))

            server_thread = threading.Thread(target=serve)
            server_thread.start()
            self.assertTrue(ready.wait(1))

            peer = CLIENT.DictationPeer(77, socket_path)
            with peer:
                event = peer.read_event()

            server_thread.join(timeout=1)
            self.assertFalse(server_thread.is_alive())
            self.assertEqual(
                event, {"type": "snapshot", "peerPid": 77, "session": None}
            )
            self.assertEqual(received[0]["type"], "dictation.hello")
            self.assertEqual(received[0]["protocolVersion"], {"major": 1, "minor": 4})

    def test_malformed_stdin_reports_an_explicit_error(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = io.StringIO()
            client = CLIENT.DictationClient(Path(directory))
            with contextlib.redirect_stdout(output):
                client._handle_stdin("not-json")

        event = json.loads(output.getvalue())
        self.assertEqual(event["type"], "client.error")
        self.assertEqual(event["code"], "shell_unavailable")


if __name__ == "__main__":
    unittest.main()
