pragma ComponentBehavior: Bound

import qs.components
import qs.components.effects
import qs.services
import qs.config
import qs.utils
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

PillCard {
    id: root

    required property Notifs.Notif modelData
    readonly property bool hasImage: modelData.image.length > 0
    readonly property bool hasAppIcon: modelData.appIcon.length > 0
    // Detect custom icon paths: absolute paths, file:// URLs, or home-relative paths
    readonly property bool hasTransparentIcon: {
        const icon = modelData.appIcon;
        return icon.startsWith("/") ||
               icon.startsWith("file://") ||
               icon.startsWith("~/");
    }
    readonly property int nonAnimHeight: summary.implicitHeight + (root.expanded ? appName.height + body.height + actions.height + actions.anchors.topMargin : bodyPreview.height) + inner.anchors.margins * 2
    property bool expanded: Config.notifs.openExpanded

    readonly property color cardBaseColor: root.modelData.urgency === NotificationUrgency.Critical
        ? Colours.palette.m3error
        : Colours.palette.m3surfaceContainerHigh
    readonly property var cardStyle: Colours.pillStyle(cardBaseColor, Colours.glass.medium)
    readonly property var foregroundContainerStyle: Colours.pillStyle(cardBaseColor, Colours.glass.strong)

    color: cardStyle.background
    radius: Appearance.rounding.normal
    borderWidth: 1
    borderColor: cardStyle.border

    Behavior on borderColor {
        CAnim {}
    }

    implicitWidth: Config.notifs.sizes.width
    implicitHeight: inner.implicitHeight

    x: Config.notifs.sizes.width
    Component.onCompleted: {
        x = 0;
        modelData.lock(this);
    }
    Component.onDestruction: modelData.unlock(this)

    Behavior on x {
        Anim {
            easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
        }
    }

    MouseArea {
        property int startY

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.expanded && body.hoveredLink ? Qt.PointingHandCursor : pressed ? Qt.ClosedHandCursor : undefined
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        preventStealing: true

        onEntered: root.modelData.timer.stop()
        onExited: {
            if (!pressed)
                root.modelData.timer.start();
        }

        // drag.target: root (NOT parent) — PillCard's default slot reparents
        // children into contentHolder, so `parent` here resolves to contentHolder
        // (which is anchors.fill: parent and can't be moved). The slide-to-dismiss
        // gesture must move the PillCard root itself.
        drag.target: root
        drag.axis: Drag.XAxis

        onPressed: event => {
            root.modelData.timer.stop();
            startY = event.y;
            if (event.button === Qt.MiddleButton)
                root.modelData.close();
        }
        onReleased: event => {
            if (!containsMouse)
                root.modelData.timer.start();

            if (Math.abs(root.x) < Config.notifs.sizes.width * Config.notifs.clearThreshold)
                root.x = 0;
            else
                root.modelData.popup = false;
        }
        onPositionChanged: event => {
            if (pressed) {
                const diffY = event.y - startY;
                if (Math.abs(diffY) > Config.notifs.expandThreshold)
                    root.expanded = diffY > 0;
            }
        }
        onClicked: event => {
            if (!Config.notifs.actionOnClick || event.button !== Qt.LeftButton)
                return;

            const actions = root.modelData.actions;
            if (actions?.length === 1)
                actions[0].invoke();
        }

        Item {
            id: inner

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Appearance.padding.normal

            implicitHeight: root.nonAnimHeight

            Behavior on implicitHeight {
                Anim {
                    duration: Appearance.anim.durations.expressiveDefaultSpatial
                    easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
                }
            }

            Loader {
                id: image

                active: root.hasImage
                asynchronous: true

                anchors.left: parent.left
                anchors.top: parent.top
                width: Config.notifs.sizes.image
                height: Config.notifs.sizes.image
                visible: root.hasImage || root.hasAppIcon

                sourceComponent: ClippingRectangle {
                    radius: Appearance.rounding.full
                    implicitWidth: Config.notifs.sizes.image
                    implicitHeight: Config.notifs.sizes.image

                    Image {
                        anchors.fill: parent
                        source: Qt.resolvedUrl(root.modelData.image)
                        fillMode: Image.PreserveAspectCrop
                        cache: false
                        asynchronous: true
                    }
                }
            }

            Loader {
                id: appIcon

                active: root.hasAppIcon || !root.hasImage
                asynchronous: true

                anchors.horizontalCenter: root.hasImage ? undefined : image.horizontalCenter
                anchors.verticalCenter: root.hasImage ? undefined : image.verticalCenter
                anchors.right: root.hasImage ? image.right : undefined
                anchors.bottom: root.hasImage ? image.bottom : undefined

                sourceComponent: StyledRect {
                    radius: Appearance.rounding.full
                    color: root.hasTransparentIcon ? "transparent" : root.foregroundContainerStyle.background
                    border.width: root.hasTransparentIcon ? 0 : 1
                    border.color: root.hasTransparentIcon ? "transparent" : root.foregroundContainerStyle.border
                    implicitWidth: root.hasImage ? Config.notifs.sizes.badge : Math.round(Config.notifs.sizes.image * 0.75)
                    implicitHeight: root.hasImage ? Config.notifs.sizes.badge : Math.round(Config.notifs.sizes.image * 0.75)

                    Loader {
                        id: icon

                        active: root.hasAppIcon
                        asynchronous: true

                        anchors.centerIn: parent

                        // Custom icons: 80% for padding, system icons: 60% (with colored background)
                        width: root.hasTransparentIcon ? Math.round(parent.width * 0.8) : Math.round(parent.width * 0.6)
                        height: root.hasTransparentIcon ? Math.round(parent.height * 0.8) : Math.round(parent.height * 0.6)

                        // Use plain Image for custom file paths (preserves SVG transparency)
                        // Use ColouredIcon for system icons (uses Qt icon theme engine)
                        sourceComponent: root.hasTransparentIcon ? customIconComponent : systemIconComponent
                    }

                    Component {
                        id: customIconComponent

                        Image {
                            anchors.fill: parent
                            source: root.modelData.appIcon
                            sourceSize.width: width
                            sourceSize.height: height
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: true

                            onStatusChanged: {
                                if (status === Image.Error)
                                    console.warn("[Notification] Failed to load custom icon:", source);
                            }
                        }
                    }

                    Component {
                        id: systemIconComponent

                        ColouredIcon {
                            anchors.fill: parent
                            source: Quickshell.iconPath(root.modelData.appIcon)
                            colour: Colours.palette.m3onSurface
                            layer.enabled: root.modelData.appIcon.endsWith("symbolic")
                        }
                    }

                    Loader {
                        active: !root.hasAppIcon
                        asynchronous: true
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: -Appearance.font.size.large * 0.02
                        anchors.verticalCenterOffset: Appearance.font.size.large * 0.02

                        sourceComponent: MaterialIcon {
                            text: Icons.getNotifIcon(root.modelData.summary, root.modelData.urgency)

                            color: Colours.palette.m3onSurface
                            font.pointSize: Appearance.font.size.large
                        }
                    }
                }
            }

            StyledText {
                id: appName

                anchors.top: parent.top
                anchors.left: image.right
                anchors.leftMargin: Appearance.spacing.smaller

                animate: true
                text: appNameMetrics.elidedText
                maximumLineCount: 1
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.small

                opacity: root.expanded ? 1 : 0

                Behavior on opacity {
                    Anim {}
                }
            }

            TextMetrics {
                id: appNameMetrics

                text: root.modelData.appName
                font.family: appName.font.family
                font.pointSize: appName.font.pointSize
                elide: Text.ElideRight
                elideWidth: expandBtn.x - time.width - timeSep.width - summary.x - Appearance.spacing.small * 3
            }

            StyledText {
                id: summary

                anchors.top: parent.top
                anchors.left: image.right
                anchors.leftMargin: Appearance.spacing.smaller

                animate: true
                text: summaryMetrics.elidedText
                maximumLineCount: 1
                height: implicitHeight

                states: State {
                    name: "expanded"
                    when: root.expanded

                    PropertyChanges {
                        summary.maximumLineCount: undefined
                    }

                    AnchorChanges {
                        target: summary
                        anchors.top: appName.bottom
                    }
                }

                transitions: Transition {
                    PropertyAction {
                        target: summary
                        property: "maximumLineCount"
                    }
                    AnchorAnimation {
                        duration: Appearance.anim.durations.normal
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.anim.curves.standard
                    }
                }

                Behavior on height {
                    Anim {}
                }
            }

            TextMetrics {
                id: summaryMetrics

                text: root.modelData.summary
                font.family: summary.font.family
                font.pointSize: summary.font.pointSize
                elide: Text.ElideRight
                elideWidth: expandBtn.x - time.width - timeSep.width - summary.x - Appearance.spacing.small * 3
            }

            StyledText {
                id: timeSep

                anchors.top: parent.top
                anchors.left: summary.right
                anchors.leftMargin: Appearance.spacing.small

                text: "•"
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.small

                states: State {
                    name: "expanded"
                    when: root.expanded

                    AnchorChanges {
                        target: timeSep
                        anchors.left: appName.right
                    }
                }

                transitions: Transition {
                    AnchorAnimation {
                        duration: Appearance.anim.durations.normal
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.anim.curves.standard
                    }
                }
            }

            StyledText {
                id: time

                anchors.top: parent.top
                anchors.left: timeSep.right
                anchors.leftMargin: Appearance.spacing.small

                animate: true
                horizontalAlignment: Text.AlignLeft
                text: root.modelData.timeStr
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.small
            }

            Item {
                id: expandBtn

                anchors.right: parent.right
                anchors.top: parent.top

                implicitWidth: expandIcon.height
                implicitHeight: expandIcon.height

                StateLayer {
                    radius: Appearance.rounding.full
                    color: Colours.palette.m3onSurface

                    function onClicked() {
                        root.expanded = !root.expanded;
                    }
                }

                MaterialIcon {
                    id: expandIcon

                    anchors.centerIn: parent

                    animate: true
                    text: root.expanded ? "expand_less" : "expand_more"
                    font.pointSize: Appearance.font.size.normal
                }
            }

            StyledText {
                id: bodyPreview

                anchors.left: summary.left
                anchors.right: expandBtn.left
                anchors.top: summary.bottom
                anchors.rightMargin: Appearance.spacing.small

                animate: true
                textFormat: Text.MarkdownText
                text: bodyPreviewMetrics.elidedText
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.small

                opacity: root.expanded ? 0 : 1

                Behavior on opacity {
                    Anim {}
                }
            }

            TextMetrics {
                id: bodyPreviewMetrics

                text: root.modelData.body
                font.family: bodyPreview.font.family
                font.pointSize: bodyPreview.font.pointSize
                elide: Text.ElideRight
                elideWidth: bodyPreview.width
            }

            StyledText {
                id: body

                anchors.left: summary.left
                anchors.right: expandBtn.left
                anchors.top: summary.bottom
                anchors.rightMargin: Appearance.spacing.small

                animate: true
                textFormat: Text.MarkdownText
                text: root.modelData.body
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.small
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                height: text ? implicitHeight : 0

                onLinkActivated: link => {
                    if (!root.expanded)
                        return;

                    Quickshell.execDetached(["app2unit", "-O", "--", link]);
                    root.modelData.popup = false;
                }

                opacity: root.expanded ? 1 : 0

                Behavior on opacity {
                    Anim {}
                }
            }

            RowLayout {
                id: actions

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: body.bottom
                anchors.topMargin: Appearance.spacing.small

                spacing: Appearance.spacing.smaller

                opacity: root.expanded ? 1 : 0

                Behavior on opacity {
                    Anim {}
                }

                Action {
                    modelData: QtObject {
                        readonly property string text: qsTr("Close")
                        function invoke(): void {
                            root.modelData.close();
                        }
                    }
                }

                Repeater {
                    model: root.modelData.actions

                    delegate: Component {
                        Action {}
                    }
                }
            }
        }
    }

    component Action: StyledRect {
        id: action

        required property var modelData

        radius: Appearance.rounding.full
        color: root.foregroundContainerStyle.background
        border.width: 1
        border.color: root.foregroundContainerStyle.border

        Layout.preferredWidth: actionText.width + Appearance.padding.normal * 2
        Layout.preferredHeight: actionText.height + Appearance.padding.small * 2
        implicitWidth: actionText.width + Appearance.padding.normal * 2
        implicitHeight: actionText.height + Appearance.padding.small * 2

        StateLayer {
            radius: Appearance.rounding.full
            color: Colours.palette.m3onSurface

            function onClicked(): void {
                action.modelData.invoke();
            }
        }

        StyledText {
            id: actionText

            anchors.centerIn: parent
            text: actionTextMetrics.elidedText
            color: Colours.palette.m3onSurface
            font.pointSize: Appearance.font.size.small
        }

        TextMetrics {
            id: actionTextMetrics

            text: action.modelData.text
            font.family: actionText.font.family
            font.pointSize: actionText.font.pointSize
            elide: Text.ElideRight
            elideWidth: {
                const numActions = root.modelData.actions.length + 1;
                return (inner.width - actions.spacing * (numActions - 1)) / numActions - Appearance.padding.normal * 2;
            }
        }
    }
}
