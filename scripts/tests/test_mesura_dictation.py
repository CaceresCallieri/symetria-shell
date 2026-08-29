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
REPOSITORY_ROOT = Path(__file__).parents[2]
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

    def test_destinationless_mesura_injection_is_retired(self) -> None:
        inject_source = (REPOSITORY_ROOT / "scripts/stt-inject.sh").read_text()
        job_source = (REPOSITORY_ROOT / "services/SttJob.qml").read_text()
        transport_source = (
            REPOSITORY_ROOT / "services/MesuraDictation.qml"
        ).read_text()

        self.assertNotIn("STT_MESURA_PID", inject_source)
        self.assertNotIn("try_mesura_inject", inject_source)
        self.assertNotIn("symmetria-mesura-${", inject_source)
        self.assertNotIn("STT_MESURA_PID", job_source)
        self.assertNotIn("minor: 4", transport_source)
        self.assertEqual(transport_source.count("minor: 5"), 1)

    def test_disconnect_interrupts_only_delivery_and_confirmation(self) -> None:
        job_source = (REPOSITORY_ROOT / "services/SttJob.qml").read_text()
        service_source = (REPOSITORY_ROOT / "services/SttService.qml").read_text()
        handler = job_source.split("function handleMesuraPeerDisconnected", maxsplit=1)[
            1
        ].split("function", maxsplit=1)[0]

        self.assertIn('_state !== "delivering"', handler)
        self.assertIn('_state !== "confirming"', handler)
        self.assertIn("_failMesuraTargetUnavailable", handler)
        self.assertIn("function onPeerDisconnected", service_source)

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
                "protocolVersion": {"major": 1, "minor": 5},
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

    def test_normalizes_retryability_without_retrying_a_dispatched_failed_turn(
        self,
    ) -> None:
        for code, expected in (
            ("provider_start_failed", True),
            ("persistence_failed", True),
            ("deadline_exceeded", True),
            ("provider_turn_failed", False),
            ("renderer_lost", False),
        ):
            event = CLIENT.parse_server_message(
                41,
                json.dumps(
                    {
                        "type": "dictation.receipt",
                        "receipt": {"outcome": "failed", "code": code},
                    }
                ),
            )

            self.assertEqual(event["type"], "receipt")
            self.assertEqual(event["receipt"]["retryable"], expected)

    def test_rejects_a_malformed_receipt(self) -> None:
        event = CLIENT.parse_server_message(
            41,
            json.dumps({"type": "dictation.receipt", "receipt": None}),
        )

        self.assertEqual(event["type"], "client.error")
        self.assertEqual(event["code"], "malformed_input")

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
                        connection.sendall(
                            (
                                json.dumps(
                                    {
                                        "type": "dictation.snapshot",
                                        "session": {
                                            "sessionId": "session-later",
                                            "phase": "recording",
                                        },
                                    }
                                )
                                + "\n"
                            ).encode()
                        )

            server_thread = threading.Thread(target=serve)
            server_thread.start()
            self.assertTrue(ready.wait(1))

            peer = CLIENT.DictationPeer(77, socket_path)
            with peer:
                opening_event = peer.read_event()
                later_event = peer.read_event()

            server_thread.join(timeout=1)
            self.assertFalse(server_thread.is_alive())
            self.assertEqual(
                opening_event, {"type": "snapshot", "peerPid": 77, "session": None}
            )
            self.assertEqual(later_event["session"]["sessionId"], "session-later")
            self.assertEqual(received[0]["type"], "dictation.hello")
            self.assertEqual(received[0]["protocolVersion"], {"major": 1, "minor": 5})

    def test_peer_disconnect_is_explicit_after_its_opening_snapshot(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            socket_path = Path(directory) / "symmetria-mesura-dictation-88.sock"
            ready = threading.Event()

            def serve() -> None:
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
                    server.bind(str(socket_path))
                    server.listen(1)
                    ready.set()
                    connection, _ = server.accept()
                    with connection:
                        connection.sendall(
                            b'{"type":"dictation.snapshot","session":null}\n'
                        )

            server_thread = threading.Thread(target=serve)
            server_thread.start()
            self.assertTrue(ready.wait(1))
            output = io.StringIO()
            client = CLIENT.DictationClient(Path(directory))

            with contextlib.redirect_stdout(output):
                client._read_peer(88, socket_path)

            server_thread.join(timeout=1)
            events = [json.loads(line) for line in output.getvalue().splitlines()]
            self.assertEqual(
                [event["type"] for event in events],
                ["snapshot", "peer.connected", "peer.disconnected"],
            )

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
