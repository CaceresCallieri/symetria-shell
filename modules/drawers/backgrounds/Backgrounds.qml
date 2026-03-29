import qs.services
import qs.config
// Relative path imports — qs.modules.* paths don't resolve in
// setSource-loaded files, so we use directory-relative paths instead.
import "../../session" as Session
import "../../launcher" as Launcher
import "../../dashboard" as Dashboard
import "../../bar/popouts" as BarPopouts
import "../../utilities" as Utilities
import "../../sidebar" as Sidebar
import "../../clipboard" as ClipboardModule
import "../../askpass" as Askpass
import "../../stt" as SttModule
import "../../calculator" as CalculatorModule
import "../../packages" as PackagesModule
import QtQuick
import QtQuick.Shapes

// Layer-based transparency: render all shapes to texture at full opacity,
// then apply transparency once to the entire layer. This prevents
// double-opacity artifacts where shapes overlap.
Item {
    id: root

    required property Item panels
    required property Item bar
    required property Item agentBar

    anchors.fill: parent
    anchors.margins: Config.border.thickness
    anchors.topMargin: bar.implicitHeight
    anchors.bottomMargin: agentBar.implicitHeight

    // Enable layer rendering to prevent overlap artifacts
    layer.enabled: true
    opacity: Colours.generalBackgroundAlpha

    Shape {
        id: shape

        readonly property real rounding: Config.border.rounding

        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        Session.Background {
            wrapper: root.panels.session

            startX: shape.width - root.panels.sidebar.width
            startY: (shape.height - wrapper.height) / 2 - rounding
        }

        Launcher.Background {
            wrapper: root.panels.launcher

            startX: (shape.width - wrapper.width) / 2 - rounding
            startY: shape.height
        }

        ClipboardModule.Background {
            wrapper: root.panels.clipboard

            startX: (shape.width - wrapper.width) / 2 - rounding
            startY: shape.height - root.panels.launcher.height - (root.panels.launcher.height > 0 ? Appearance.spacing.large : 0)
        }

        CalculatorModule.CalculatorBackground {
            wrapper: root.panels.calculator

            startX: (shape.width - wrapper.width) / 2 - rounding
            startY: {
                let y = shape.height;
                if (root.panels.launcher.height > 0)
                    y -= root.panels.launcher.height + Appearance.spacing.large;
                if (root.panels.clipboard.height > 0)
                    y -= root.panels.clipboard.height + Appearance.spacing.large;
                return y;
            }
        }

        Dashboard.Background {
            wrapper: root.panels.dashboard

            // Left-aligned panel: startX = wrapper.x - rounding so visible left edge aligns with wrapper
            // The BL union arc curves into negative x territory, blending with the shell border
            startX: -rounding
            startY: shape.height
        }

        Askpass.AskpassBackground {
            wrapper: root.panels.askpass

            startX: (shape.width - wrapper.width) / 2 - rounding  // Centered horizontally
            startY: 0  // Start at top-left (clockwise path like bar popouts)
        }

        SttModule.SttBackground {
            wrapper: root.panels.stt

            startX: (shape.width - wrapper.width) / 2 - rounding  // Centered horizontally
            startY: 0  // Start at top-left (clockwise path like bar popouts)
        }

        PackagesModule.PackagesBackground {
            wrapper: root.panels.packages

            startX: (shape.width - wrapper.width) / 2 - rounding  // Centered horizontally
            startY: 0  // Start at top-left (clockwise path like bar popouts)
        }

        BarPopouts.Background {
            wrapper: root.panels.popouts

            startX: wrapper.x - rounding
            startY: wrapper.y
        }

        Utilities.Background {
            wrapper: root.panels.utilities
            sidebar: sidebar

            startX: shape.width - rounding  // Start at BR corner's inner edge for union arc
            startY: shape.height
        }

        Sidebar.Background {
            id: sidebar

            wrapper: root.panels.sidebar
            panels: root.panels

            startX: shape.width
            startY: 0
        }
    }
}
