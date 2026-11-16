"""Exercise production workspace ordering without starting the desktop shell."""

import os
import re
import subprocess
from pathlib import Path

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


def extract_function(source, name, indentation=4):
    prefix = " " * indentation
    match = re.search(
        rf"^{prefix}function {name}\(.*?^{prefix}}}$", source, re.M | re.S
    )
    assert match is not None, f"Missing production function: {name}"
    return match.group()


def test_workspace_order_and_navigation(tmp_path):
    runner = Path("/usr/lib/qt6/bin/qmltestrunner")
    if not runner.exists():
        pytest.skip("Qt6 qmltestrunner is unavailable")
    module = tmp_path / "WorkspaceTest"
    module.mkdir()
    (module / "qmldir").write_text(
        "module WorkspaceTest\n"
        "HyprHarness 1.0 HyprHarness.qml\n"
        "BarHarness 1.0 BarHarness.qml\n"
        "singleton Hypr 1.0 Hypr.qml\n"
        "singleton Hyprland 1.0 Hyprland.qml\n"
        "singleton Config 1.0 Config.qml\n"
        "singleton WorkspaceCatalog 1.0 WorkspaceCatalog.qml\n"
        "Process 1.0 Process.qml\n"
        "StdioCollector 1.0 StdioCollector.qml\n"
    )
    for name, properties in {
        "Hyprland": (
            "property var workspaces: ({values: []})\n"
            "function refreshWorkspaces() {}\n"
            "function refreshMonitors() {}\n"
            "function refreshToplevels() {}"
        ),
        "Config": "property var bar: ({workspaces: {namedWorkspaceIcons: []}})",
        "WorkspaceCatalog": "property var entries: []",
    }.items():
        (module / f"{name}.qml").write_text(
            f"pragma Singleton\nimport QtQuick\nQtObject {{ {properties} }}\n"
        )
    (module / "Process.qml").write_text(
        "import QtQuick\nQtObject {\n"
        "property list<string> command\nproperty bool running\n"
        "property QtObject stdout\nproperty int starts: 0\n"
        "signal exited(int code, int status)\n"
        "onRunningChanged: if (running) starts++\n"
        "function finish(text, code) {\n"
        "stdout.text = text; stdout.streamFinished(); running = false; exited(code, 0)\n"
        "}\n}\n"
    )
    (module / "StdioCollector.qml").write_text(
        "import QtQuick\nQtObject {\n"
        'property string text: ""\nsignal streamFinished()\n}\n'
    )

    # Quickshell's static plugins cannot load in qmltestrunner. Extract the
    # unchanged production functions and fake only their compositor/config data.
    source = (REPOSITORY_ROOT / "services/Hypr.qml").read_text()
    functions = []
    for name in (
        "workspaceKey",
        "workspaceKeyForName",
        "displayedWorkspaceIds",
        "refreshWorkspaceOrder",
    ):
        functions.append(extract_function(source, name))
    functions.append(
        extract_function(source, "onRawEvent", 8).replace(
            "event: HyprlandEvent", "event: var"
        )
    )
    transport = source[
        source.index("    Timer {\n        id: workspaceOrderRefresh") : source.index(
            "    FileView {\n        id: kbLayoutFile"
        )
    ]
    (module / "HyprHarness.qml").write_text(
        "import QtQuick\nimport WorkspaceTest\n"
        'import "../WorkspaceOrdering.js" as WorkspaceOrdering\n'
        "Item {\nid: root\nproperty var _workspaceOrder: []\n"
        "property var calls: []\nproperty int activeWsId: 1\n"
        "property var focusedMonitor: null\nproperty var screenMonitor: null\n"
        "function monitorFor(screen) { return screenMonitor }\n"
        'function focusWorkspace(selector) { calls = [...calls, {action: "focus", selector: selector}] }\n'
        'function toggleSpecialWorkspace(name) { calls = [...calls, {action: "special", name: name}] }\n'
        "property bool _workspaceOrderPending: false\n"
        "property alias orderProcess: workspaceOrderProcess\n"
        "signal configReloaded()\nfunction reloadDynamicConfs() {}\n"
        + "\n".join(functions)
        + transport
        + "\n}\n"
    )
    (module / "Hypr.qml").write_text(
        "pragma Singleton\nimport QtQuick\nimport WorkspaceTest\nHyprHarness {}\n"
    )
    # Execute the actual wheel entry point, with only outgoing IPC recorded.
    bar_source = (REPOSITORY_ROOT / "modules/bar/Bar.qml").read_text()
    (module / "BarHarness.qml").write_text(
        "import QtQuick\nimport WorkspaceTest\nItem {\n"
        "property var screen: ({width: 400})\n"
        "Item { id: centerLoader; x: 100; width: 100 }\n"
        + extract_function(bar_source, "handleWheel")
        + "\n}\n"
    )
    (tmp_path / "WorkspaceOrdering.js").symlink_to(
        REPOSITORY_ROOT / "utils/WorkspaceOrdering.js"
    )
    tests = tmp_path / "tests"
    tests.mkdir()
    (tests / "tst_WorkspaceOrder.qml").write_text(
        (Path(__file__).parent / "workspaces/tst_WorkspaceOrder.qml").read_text()
    )
    # This executable runs only the offscreen Qt Quick fixture.
    result = subprocess.run(  # noqa: S603
        [str(runner), "-platform", "offscreen", "-input", str(tests), "-o", "-,txt"],
        capture_output=True,
        text=True,
        timeout=30,
        env={
            **os.environ,
            "QT_QPA_PLATFORM": "offscreen",
            "QT_QUICK_BACKEND": "software",
            "QML2_IMPORT_PATH": str(tmp_path),
        },
    )
    assert result.returncode == 0, result.stdout + result.stderr
