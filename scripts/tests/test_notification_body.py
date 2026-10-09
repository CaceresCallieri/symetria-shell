"""Exercise CUtils against Qt without building the complete shell plugin."""

# Every subprocess uses installed Qt tooling or the locally compiled fixture.
# No command argument comes from a notification body.
# ruff: noqa: S603

import os
import shlex
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
QT_MODULES = ["Qt6Quick", "Qt6Qml", "Qt6Concurrent"]


def qt_flags(package_config: str, option: str) -> list[str]:
    output = subprocess.check_output([package_config, option, *QT_MODULES], text=True)
    return shlex.split(output)


def run_notification_body_test() -> None:
    compiler = shutil.which("c++")
    package_config = shutil.which("pkg-config")
    if compiler is None or package_config is None:
        raise unittest.SkipTest("The native notification test needs c++ and pkg-config")

    available = subprocess.run([package_config, "--exists", *QT_MODULES], check=False)
    if available.returncode != 0:
        raise unittest.SkipTest(
            "The native notification test needs the Qt6 development modules"
        )

    library_tools = subprocess.check_output(
        [package_config, "--variable=libexecdir", "Qt6Core"], text=True
    ).strip()
    moc = Path(library_tools) / "moc"
    if not moc.is_file():
        raise unittest.SkipTest("The native notification test needs Qt6 moc")

    with tempfile.TemporaryDirectory() as directory:
        verify_native_body(compiler, package_config, moc, Path(directory))


def verify_native_body(
    compiler: str, package_config: str, moc: Path, tmp_path: Path
) -> None:
    native_source = REPOSITORY_ROOT / "plugin/src/Symmetria"
    generated_source = tmp_path / "moc_cutils.cpp"
    executable = tmp_path / "verify-notification-body"
    subprocess.run(
        [
            str(moc),
            *qt_flags(package_config, "--cflags"),
            str(native_source / "cutils.hpp"),
            "-o",
            str(generated_source),
        ],
        check=True,
    )
    subprocess.run(
        [
            compiler,
            "-std=c++20",
            "-fPIC",
            "-I",
            str(native_source),
            *qt_flags(package_config, "--cflags"),
            str(Path(__file__).with_suffix(".cpp")),
            str(generated_source),
            str(native_source / "cutils.cpp"),
            "-o",
            str(executable),
            *qt_flags(package_config, "--libs"),
        ],
        check=True,
    )
    result = subprocess.run(
        [str(executable)],
        env={**os.environ, "QT_QPA_PLATFORM": "offscreen"},
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr


# The pytest fixture passed locally but failed CI: its type checker has no pytest.
# Keep this wrapper in unittest so both environments use the standard library.
class NotificationBodyTests(unittest.TestCase):
    def test_preserves_text_and_themes_links(self) -> None:
        run_notification_body_test()
