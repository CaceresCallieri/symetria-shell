"""Exercise the production panel input bindings with offscreen Qt Quick clicks."""

import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DRAWER_WRAPPER = REPOSITORY_ROOT / "modules/drawers/Wrapper.qml"

QML_TEST = """\
import QtQuick
import QtTest

Item {
    id: fixture
    width: 800
    height: 600
    property int interceptedClicks: 0
    property int passedClicks: 0

    MouseArea {
        anchors.fill: parent
        onClicked: fixture.passedClicks++
    }

    Item {
        id: panels
        x: 12
        y: 36
        width: 700
        height: 500

        Item {
            id: indicator
            x: 500
            y: 400
            implicitWidth: 40
            implicitHeight: 40
            visible: false
        }

        Item {
            id: edgeTrigger
            width: 1
            height: 25
            anchors.right: parent.right
            anchors.bottom: parent.bottom
        }
    }

    Component {
        id: regionFactory
        // PRODUCTION_REGION
    }

    TestCase {
        name: "DrawerInput"
        when: windowShown
        property Item region

        function init() {
            panels.visible = true;
            panels.x = 12;
            panels.y = 36;
            indicator.visible = false;
            fixture.interceptedClicks = 0;
            fixture.passedClicks = 0;
            region = createTemporaryObject(regionFactory, fixture, { modelData: indicator });
            verify(region !== null);
        }

        function clickIndicator() {
            mouseClick(fixture, panels.x + indicator.x + 20, panels.y + indicator.y + 20);
        }

        function test_hiddenIndicatorPassesClicks() {
            compare(indicator.width, 40);
            compare(indicator.height, 40);
            clickIndicator();
            compare(fixture.passedClicks, 1);
            compare(fixture.interceptedClicks, 0);
        }

        function test_visibilityChangesUpdateInput() {
            indicator.visible = true;
            clickIndicator();
            compare(fixture.interceptedClicks, 1);
            indicator.visible = false;
            clickIndicator();
            compare(fixture.passedClicks, 1);
            compare(fixture.interceptedClicks, 1);
        }

        function test_containerMovementUpdatesInput() {
            indicator.visible = true;
            panels.x += 23;
            panels.y += 17;
            compare(region.x, panels.x + indicator.x);
            compare(region.y, panels.y + indicator.y);
            clickIndicator();
            compare(fixture.interceptedClicks, 1);
        }

        function test_invisibleParentPassesClicks() {
            indicator.visible = true;
            panels.visible = false;
            clickIndicator();
            compare(fixture.passedClicks, 1);
            panels.visible = true;
        }

        function test_edgeTriggerRetainsItsInput() {
            region.modelData = edgeTrigger;
            compare(region.width, 1);
            compare(region.height, 25);
            mouseClick(fixture, region.x, region.y + 12);
            compare(fixture.interceptedClicks, 1);
            mouseClick(fixture, region.x - 1, region.y + 12);
            compare(fixture.passedClicks, 1);
        }
    }
}
"""


def production_region_fixture() -> str:
    source = DRAWER_WRAPPER.read_text()
    match = re.search(r"Region \{\s+required property Item modelData\b[^{}]*\}", source)
    if match is None:
        raise AssertionError("The panel Region delegate moved; update the fixture")
    region = match.group().replace("Region {", "Item {", 1)
    # Quickshell is statically linked and cannot load in qmltestrunner. Keep
    # every production binding; replace only the Region type and its operation.
    region = region.replace("intersection: Intersection.Subtract", "")
    return (
        region[:-1]
        + "MouseArea { anchors.fill: parent; onClicked: fixture.interceptedClicks++ }\n}"
    )


class DrawerInputTests(unittest.TestCase):
    def test_panel_input_follows_visibility_and_geometry(self) -> None:
        qt6_runner = Path("/usr/lib/qt6/bin/qmltestrunner")
        runner = (
            str(qt6_runner) if qt6_runner.is_file() else shutil.which("qmltestrunner")
        )
        if runner is None:
            self.skipTest("The drawer input test needs Qt6 qmltestrunner")

        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / "tst_drawer_input.qml"
            fixture.write_text(
                QML_TEST.replace("// PRODUCTION_REGION", production_region_fixture())
            )
            result = subprocess.run(  # noqa: S603
                [runner, "-input", str(fixture)],
                env={**os.environ, "QT_QPA_PLATFORM": "offscreen"},
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
        output = result.stdout + result.stderr
        if "QtTest library 5." in output:
            self.skipTest("The available qmltestrunner uses Qt5; Qt6 is required")
        self.assertEqual(result.returncode, 0, output)
