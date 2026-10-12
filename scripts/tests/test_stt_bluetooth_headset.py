"""Source-text guards for STT through a Bluetooth headset microphone.

A headset mic makes WirePlumber flip the card from A2DP to HFP, which swaps
the sink node under the running duck and delivers digital silence while the
SCO link comes up. These tests pin the three behaviours that depend on it;
qmltestrunner cannot load Quickshell's plugins, so they assert over source.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).parents[2]


def read_source(relative_path: str) -> str:
    return (REPOSITORY_ROOT / relative_path).read_text()


def code_only(source: str) -> str:
    """Drop // comments, which legitimately name the APIs the code avoids."""
    return re.sub(r"//.*", "", source)


def function_body(source: str, name: str) -> str:
    start = source.index(f"function {name}(")
    next_function = source.find("\n    function ", start + 1)
    return source[start : next_function if next_function != -1 else len(source)]


class AudioDuckingSinkSwapTests(unittest.TestCase):
    def setUp(self) -> None:
        self.source = read_source("services/AudioDucking.qml")

    def test_sinks_are_keyed_by_bluetooth_profile(self) -> None:
        # The A2DP and HFP sinks share node.name; only the profile tells them
        # apart. Keying by name alone reintroduces the volume-0 regression.
        self.assertIn('"api.bluez5.profile"', function_body(self.source, "_sinkKey"))

    def test_restore_never_reads_the_default_sink_volume(self) -> None:
        # The old implementation compared Audio.volume across the A2DP→HFP
        # swap and skipped the restore as "changed externally".
        code = code_only(self.source)
        self.assertNotIn("Audio.volume", code)
        self.assertNotIn("Audio.setVolume", code)

    def test_absent_sink_waits_for_its_return(self) -> None:
        restore = function_body(self.source, "restore")
        self.assertIn("_addPendingRestore(", restore)
        self.assertIn("_processPendingRestores()", self.source)

    def test_new_duck_adopts_pending_restores(self) -> None:
        # Otherwise a dictation started before the headset flips back to A2DP
        # lets the pending restore expire mid-dictation.
        self.assertIn(
            "_duckedSinks = _adoptPendingRestores()", function_body(self.source, "duck")
        )


class SttJobDeadMicrophoneTests(unittest.TestCase):
    def setUp(self) -> None:
        self.source = read_source("services/SttJob.qml")

    def test_digital_silence_is_not_sent_for_transcription(self) -> None:
        submit = function_body(self.source, "_submitForTranscription")
        gate = submit.index(
            "_sessionLevelReadings > 0 && !_sessionHasAudio && !_levelMonitorDied"
        )
        self.assertLess(gate, submit.index('_state = "processing"'))
        # "silence" is the non-retryable source: retrying dead audio is futile.
        self.assertIn('_setErrorState("silence", "No audio from microphone"', submit)

    def test_segment_audio_flag_resets_on_every_recording_start(self) -> None:
        self.assertIn(
            "_segmentHasAudio = false", function_body(self.source, "_startRecording")
        )

    def test_level_monitor_marks_audio_only_on_nonzero_level(self) -> None:
        self.assertRegex(
            self.source,
            re.compile(r"if \(level > 0 && !job\._segmentHasAudio\)"),
        )


class RecorderMicrophoneHintTests(unittest.TestCase):
    def test_recorder_shows_the_mic_starting_hint(self) -> None:
        content = read_source("modules/recorder/Content.qml")
        self.assertIn("job?.waitingForMicrophone", content)
        self.assertIn("visible: root.waitingForMicrophone", content)


if __name__ == "__main__":
    unittest.main()
