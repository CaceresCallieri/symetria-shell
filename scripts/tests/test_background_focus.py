from __future__ import annotations

import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).parents[2]

METAL_WALLPAPER = REPOSITORY_ROOT / "modules" / "background" / "MetalWallpaper.qml"
WRAPPER = REPOSITORY_ROOT / "modules" / "background" / "Wrapper.qml"
BACKGROUND_CONFIG = REPOSITORY_ROOT / "config" / "BackgroundConfig.qml"
LOCK_CONFIG = REPOSITORY_ROOT / "config" / "LockConfig.qml"
WALLPAPERS_SERVICE = REPOSITORY_ROOT / "services" / "Wallpapers.qml"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class FocusBackdropTests(unittest.TestCase):
    """Source-text guards for the focus-mode metal backdrop.

    The suite reads QML source because qmltestrunner cannot load Quickshell's
    statically-linked plugins (see CLAUDE.md). Assertions go stale silently if
    these files are renamed or moved — treat a failure here as "the assertion's
    subject moved" before treating it as a regression.
    """

    def setUp(self) -> None:
        self.metal_wallpaper = read(METAL_WALLPAPER)
        self.wrapper = read(WRAPPER)
        self.background_config = read(BACKGROUND_CONFIG)
        self.lock_config = read(LOCK_CONFIG)
        self.wallpapers_service = read(WALLPAPERS_SERVICE)

    def test_backdrop_is_frozen(self) -> None:
        self.assertIn("animating: false", self.metal_wallpaper)

    def test_backdrop_binds_configured_frozen_time(self) -> None:
        self.assertIn(
            "time: Config.background.focusBackdrop.time", self.metal_wallpaper
        )

    def test_backdrop_cfg_derives_from_canonical_material_map(self) -> None:
        # The cfg must derive from LockConfig.Beams.material — a re-spelled
        # key-per-key literal re-creates the silent-undefined drift class.
        self.assertIn(
            "Object.assign({}, Config.lock.beams.material", self.metal_wallpaper
        )

    def test_lock_config_declares_canonical_material_map(self) -> None:
        self.assertIn("readonly property var material:", self.lock_config)
        # The map must cover the shader-facing material keys. Comma-agnostic:
        # the final entry carries no trailing comma.
        for key in (
            "speed",
            "noiseScale",
            "grain",
            "beamWidth",
            "rotation",
            "roughness",
            "lightIntensity",
            "ambient",
            "edgeDarken",
            "stagger",
            "growSpan",
            "beamQuantise",
            "feather",
            "frontGlow",
            "growFlip",
            "sheenRoughness",
            "sheenStrength",
            "fresnel",
        ):
            self.assertIn(f"{key}: {key}", self.lock_config)

    def test_wrapper_gates_backdrop_on_focus_and_readiness(self) -> None:
        self.assertIn("Config.background.focusBackdrop.enabled", self.wrapper)
        self.assertIn("Wallpapers.focusMode && status === Loader.Ready", self.wrapper)

    def test_background_config_declares_focus_backdrop(self) -> None:
        self.assertIn("component FocusBackdrop: JsonObject {", self.background_config)
        self.assertIn("property bool enabled: false", self.background_config)
        self.assertIn("property real time: 40", self.background_config)

    def test_focus_toasts_share_one_key(self) -> None:
        # Rapid toggles must UPDATE one keyed toast, not stack one per toggle.
        for icon in ("visibility_off", "visibility"):
            pattern = f'"{icon}", Toast.Info, 0, "", "focus-mode")'
            self.assertIn(pattern, self.wallpapers_service)
        self.assertNotIn("distraction-free", self.wallpapers_service)


if __name__ == "__main__":
    unittest.main()
