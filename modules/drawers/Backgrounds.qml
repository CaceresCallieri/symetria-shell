import qs.services
import qs.config
import qs.modules.session as Session
import qs.modules.launcher as Launcher
import qs.modules.bar.popouts as BarPopouts
import qs.modules.utilities as Utilities
import qs.modules.sidebar as Sidebar
import qs.modules.clipboard as ClipboardModule
import qs.modules.askpass as Askpass
import qs.modules.recorder as RecorderModule
import qs.modules.calculator as CalculatorModule
import qs.modules.packages as PackagesModule
import QtQuick
import QtQuick.Shapes

// Layer-based transparency: render all shapes to texture at full opacity,
// then apply transparency once to the entire layer. This prevents
// double-opacity artifacts where shapes overlap.
Item {
    id: root

    required property Panels panels
    required property Item bar
    required property Item agentBar

    anchors.fill: parent
    anchors.leftMargin: Config.border.sideThickness
    anchors.rightMargin: Config.border.sideThickness
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

        Askpass.AskpassBackground {
            wrapper: root.panels.askpass

            startX: (shape.width - wrapper.width) / 2 - rounding  // Centered horizontally
            startY: 0  // Start at top-left (clockwise path like bar popouts)
        }

        RecorderModule.RecorderBackground {
            wrapper: root.panels.recorder

            startX: (shape.width - wrapper.width) / 2 - rounding
            startY: 0
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
