"""Exercise CUtils against Qt without building the complete shell plugin."""

# Every subprocess uses installed Qt tooling or the locally compiled fixture.
# No command argument comes from a notification body.
# ruff: noqa: S603

import os
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
QT_MODULES = ["Qt6Quick", "Qt6Qml", "Qt6Concurrent"]


def qt_flags(package_config: str, option: str) -> list[str]:
    output = subprocess.check_output([package_config, option, *QT_MODULES], text=True)
    return shlex.split(output)


def test_notification_body_preserves_text_and_themes_links(tmp_path: Path) -> None:
    compiler = shutil.which("c++")
    package_config = shutil.which("pkg-config")
    if compiler is None or package_config is None:
        pytest.skip("The native notification test needs c++ and pkg-config")

    available = subprocess.run([package_config, "--exists", *QT_MODULES], check=False)
    if available.returncode != 0:
        pytest.skip("The native notification test needs the Qt6 development modules")

    library_tools = subprocess.check_output(
        [package_config, "--variable=libexecdir", "Qt6Core"], text=True
    ).strip()
    moc = Path(library_tools) / "moc"
    if not moc.is_file():
        pytest.skip("The native notification test needs Qt6 moc")

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
