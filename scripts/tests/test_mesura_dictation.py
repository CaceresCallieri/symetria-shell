from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import re
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
            process_root = runtime_dir / "proc"
            (process_root / "41").mkdir(parents=True)
            valid = runtime_dir / "symmetria-mesura-dictation-41.sock"
            stale = runtime_dir / "symmetria-mesura-dictation-42.sock"
            other = runtime_dir / "symmetria-mesura-41.sock"
            malformed = runtime_dir / "symmetria-mesura-dictation-nope.sock"
            for path in (valid, stale, other, malformed):
                path.touch()

            self.assertEqual(
                CLIENT.discover_socket_paths(runtime_dir, process_root), {41: valid}
            )

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

    def test_shell_starts_while_reservation_is_pending_and_only_hands_off_ui(
        self,
    ) -> None:
        service_source = (REPOSITORY_ROOT / "services/SttService.qml").read_text()
        manager_source = (
            REPOSITORY_ROOT / "services/RecordingSessionManager.qml"
        ).read_text()
        recorder_root_source = (
            REPOSITORY_ROOT / "modules/recorder/RecorderRoot.qml"
        ).read_text()
        mesura_start = service_source.split(
            "if (job._isMesuraClass(job._targetWindowClass)", maxsplit=1
        )[1].split("return;\n        }", maxsplit=1)[0]

        self.assertIn("MesuraDictation.reserve", mesura_start)
        self.assertIn('_activatePreparedJob(job, "recording");', mesura_start)
        self.assertLess(
            mesura_start.index('_activatePreparedJob(job, "recording");'),
            mesura_start.index("MesuraDictation.reserve"),
        )
        self.assertIn("return SttService.job;", manager_source)
        self.assertNotIn(
            "return shellOwnsSttPresentation ? SttService.job : null;",
            manager_source,
        )
        # The drawer is the only recorder surface. The bar embed that used to
        # carry this handoff went out with the merged agent bar.
        self.assertIn(
            "RecordingSessionManager.shellOwnsSttPresentation", recorder_root_source
        )

        job_source = (REPOSITORY_ROOT / "services/SttJob.qml").read_text()
        delivery_gate = job_source.split(
            "function _beginDeliveryAfterTranscription", maxsplit=1
        )[1].split("function sendNow", maxsplit=1)[0]
        restart_gate = service_source.split("function restart", maxsplit=1)[1].split(
            "function retry", maxsplit=1
        )[0]
        accept_handler = service_source.split(
            "function _acceptMesuraSession", maxsplit=1
        )[1].split("function _startExternalMesuraSession", maxsplit=1)[0]
        failure_handler = service_source.split(
            "function _failMesuraReservation", maxsplit=1
        )[1].split("function _acceptMesuraSession", maxsplit=1)[0]
        clipboard_handler = job_source.split(
            "readonly property Process clipboardProcess", maxsplit=1
        )[1].split(
            "readonly property Process mesuraRecoveryClipboardProcess", maxsplit=1
        )[0]

        self.assertIn("mesuraReservationPending(sessionId)", delivery_gate)
        self.assertLess(
            delivery_gate.index("mesuraReservationPending(sessionId)"),
            delivery_gate.index("if (!_mesuraIntegrated)"),
        )
        self.assertIn("_pendingMesuraJob === _activeRecording", restart_gate)
        self.assertIn(
            "_createJob(pendingJob.sessionId, pendingJob.activeDeliveryChoice)",
            restart_gate,
        )
        self.assertIn("if (!alreadyActive)", accept_handler)
        self.assertIn(
            "MesuraDictation.setMode(pendingJob.activeDeliveryChoice)", accept_handler
        )
        self.assertIn("pending._manualClipboardFallback = true", failure_handler)
        self.assertIn('pending.setDeliveryChoice("clipboard")', failure_handler)
        self.assertNotIn("pending.cancel()", failure_handler)
        self.assertIn("job._manualClipboardFallback", clipboard_handler)
        self.assertIn("TranscriptionStore.add(job._transcribedText)", clipboard_handler)
        self.assertIn('session.phase !== "recording"', accept_handler)
        self.assertLess(
            accept_handler.index('session.phase !== "recording"'),
            accept_handler.index("MesuraDictation.acceptSession"),
        )
        self.assertIn("if (!terminalPhase)", accept_handler)
        self.assertIn(
            'MesuraDictation.sendControlTo(peerPid, session, "cancel")', accept_handler
        )
        self.assertLess(
            accept_handler.index('if (pendingJob.state === "transcribed")'),
            accept_handler.index("MesuraDictation.updateState(pendingJob)"),
        )

        self.assertIn("readonly property string _tempFilePrefix", job_source)
        self.assertIn("${_tempFilePrefix}_segment_", job_source)
        self.assertIn("${_tempFilePrefix}_combined.wav", job_source)
        self.assertIn("`${_tempFilePrefix}_*`", job_source)

    def test_shell_session_controls_target_the_running_instance(self) -> None:
        service_source = (REPOSITORY_ROOT / "services/SttService.qml").read_text()
        drawer_source = (REPOSITORY_ROOT / "modules/recorder/Content.qml").read_text()
        recorder_root_source = (
            REPOSITORY_ROOT / "modules/recorder/RecorderRoot.qml"
        ).read_text()

        session_bind_block = service_source.split(
            "readonly property var _sessionBinds", maxsplit=1
        )[1].split("onActiveChanged", maxsplit=1)[0]
        registration_block = service_source.split(
            "function _registerSessionBinds", maxsplit=1
        )[1].split("function _unregisterSessionBinds", maxsplit=1)[0]

        self.assertIn('["X", "cancel"]', session_bind_block)
        self.assertIn('["R", "restart"]', session_bind_block)
        self.assertIn('["space", "pause"]', session_bind_block)
        self.assertIn("Quickshell.processId", service_source)
        self.assertIn("qs ipc --pid", service_source)
        self.assertNotIn("qs -c symmetria", registration_block)
        unregister_block = service_source.split(
            "function _unregisterSessionBinds", maxsplit=1
        )[1].split("// ── Job lifecycle", maxsplit=1)[0]
        self.assertIn("Pause/Resume recording", unregister_block)
        self.assertIn("Cancel recording", unregister_block)
        self.assertIn('_ipcCommand("recorder")', unregister_block)
        # Asserted on the drawer alone. These ran against the bar embed too until
        # that surface went out with the merged agent bar; the drawer is now the
        # only recorder presentation.
        self.assertNotIn("projectName", drawer_source)
        self.assertIn("mesuraReservationPending", drawer_source)
        self.assertIn("manualClipboardFallback", drawer_source)

        cancel_handler = service_source.split("function cancel", maxsplit=1)[1].split(
            "function restart", maxsplit=1
        )[0]
        self.assertIn("_sessionVocabHints = [];", cancel_handler)
        self.assertIn("vocabHintsVisible = false;", cancel_handler)

        # The shell drops its own recorder surface when Mesura takes presentation.
        # Bar.qml carried an onShellOwnsSttPresentationChanged handler for the bar
        # embed; with that surface gone, RecorderRoot reacts through the Mesura
        # session change that shellOwnsSttPresentation itself derives from.
        self.assertIn("function onSessionChanged", recorder_root_source)
        self.assertIn(
            "visibilities.recorder = RecordingSessionManager.shellOwnsSttPresentation",
            recorder_root_source,
        )

    def test_disconnect_falls_back_only_during_delivery_and_confirmation(self) -> None:
        job_source = (REPOSITORY_ROOT / "services/SttJob.qml").read_text()
        service_source = (REPOSITORY_ROOT / "services/SttService.qml").read_text()
        handler = job_source.split("function handleMesuraPeerDisconnected", maxsplit=1)[
            1
        ].split("function", maxsplit=1)[0]

        self.assertIn('_state !== "delivering"', handler)
        self.assertIn('_state !== "confirming"', handler)
        self.assertIn("_finishMesuraWithClipboardFallback", handler)
        self.assertNotIn("_setErrorState", handler)
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

    def test_forwards_failed_receipts_without_retry_classification(self) -> None:
        for code in (
            "provider_start_failed",
            "persistence_failed",
            "deadline_exceeded",
            "provider_turn_failed",
            "renderer_lost",
        ):
            receipt = {"outcome": "failed", "code": code}
            event = CLIENT.parse_server_message(
                41,
                json.dumps(
                    {
                        "type": "dictation.receipt",
                        "receipt": receipt,
                    }
                ),
            )

            self.assertEqual(event["type"], "receipt")
            self.assertEqual(event["receipt"], receipt)
            self.assertNotIn("retryable", event["receipt"])

    def test_delivery_failures_finish_through_one_clipboard_fallback(self) -> None:
        job_source = (REPOSITORY_ROOT / "services/SttJob.qml").read_text()
        receipt_handler = job_source.split("function _handleMesuraReceipt", maxsplit=1)[
            1
        ].split("function _showMesuraSuccessToast", maxsplit=1)[0]
        fallback_handler = job_source.split(
            "function _finishMesuraWithClipboardFallback", maxsplit=1
        )[1].split("function _sendMesuraDelivery", maxsplit=1)[0]
        timeout_handler = job_source.split(
            "readonly property Timer mesuraDeliveryTimer", maxsplit=1
        )[1].split("// Auto-hide after success state", maxsplit=1)[0]

        for outcome in (
            'receipt.outcome === "confirmation-pending"',
            'receipt.outcome === "turn-running"',
        ):
            self.assertIn(outcome, receipt_handler)
        self.assertIn('_state === "success"', receipt_handler)
        self.assertIn("_finishMesuraWithClipboardFallback", receipt_handler)
        self.assertNotIn("_setErrorState", receipt_handler)
        self.assertIn("_mesuraClipboardFallbackStarted", fallback_handler)
        self.assertIn("_storeMesuraTranscriptOnce", fallback_handler)
        self.assertIn('["wl-copy", _transcribedText]', fallback_handler)
        self.assertIn("_finishMesuraWithClipboardFallback", timeout_handler)
        self.assertNotIn("_showMesuraFailureToast", job_source)
        self.assertNotIn("retryMesuraDelivery", job_source)

    def test_rejects_a_malformed_receipt(self) -> None:
        event = CLIENT.parse_server_message(
            41,
            json.dumps({"type": "dictation.receipt", "receipt": None}),
        )

        self.assertEqual(event["type"], "client.error")
        self.assertEqual(event["code"], "malformed_input")

    def test_qml_logs_only_correlated_receipt_metadata(self) -> None:
        transport_source = (
            REPOSITORY_ROOT / "services/MesuraDictation.qml"
        ).read_text()
        receipt_handler = transport_source.split(
            '} else if (event.type === "receipt") {', maxsplit=1
        )[1].split('} else if (event.type === "client.error"', maxsplit=1)[0]

        self.assertIn("mesura-receipt | peer=", receipt_handler)
        for field in ("session=", "command=", "outcome=", "code="):
            self.assertIn(field, receipt_handler)
        self.assertNotIn("JSON.stringify(event.receipt)", receipt_handler)
        self.assertNotIn("event.receipt.text", receipt_handler)
        log_statement = next(
            line for line in receipt_handler.splitlines() if "Logger.log" in line
        )
        self.assertEqual(
            set(re.findall(r"receipt\.([A-Za-z]+)", log_statement)),
            {"sessionId", "commandId", "outcome", "code"},
        )
        self.assertNotIn("JSON.stringify(receipt)", log_statement)
        for field in ("text", "transcript", "detail", "prompt", "attachments"):
            self.assertNotIn(f"receipt.{field}", log_statement)

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
                        connection.shutdown(socket.SHUT_WR)
                        while connection.recv(4096):
                            pass

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
