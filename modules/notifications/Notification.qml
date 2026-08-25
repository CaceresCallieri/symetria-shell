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
        return icon.startsWith("/") || icon.startsWith("file://") || icon.startsWith("~/");
    }
    // System-icon resolution check. When the sender passes an icon name
    // that no installed theme provides (e.g. Kanata sends "kanata" but no
    // theme ships that icon), the resolved path is empty and ColouredIcon
    // would render an empty disc. We detect that here and route to the
    // MaterialIcon fallback (same path that fires when hasAppIcon is false)
    // so the disc always has a glyph instead of looking like a blank pill.
    //
    // Uses Icons.safeIconPath (which calls Quickshell.iconPath with check=true)
    // rather than raw Quickshell.iconPath so missing-icon attempts don't spam
    // warnings into the shell log on every notification with an unknown name.
    readonly property url resolvedSystemIconPath: hasAppIcon && !hasTransparentIcon ? Icons.safeIconPath(modelData.appIcon, "") : ""
    readonly property bool systemIconResolves: resolvedSystemIconPath.length > 0
    // Inner content height (no card margins). Grows to the LARGER of (text
    // content) and (icon reservation) so the card never collapses below the
    // icon's height when the body is short. Used as inner Item's
    // implicitHeight; the card's full external height is exposed separately
    // as `nonAnimHeight` below (which Content.qml's stack-height summation
    // depends on — getting these two confused under-allocates the stack
    // and clips the bottom card's body).
    readonly property int contentInnerHeight: Math.max(summary.implicitHeight + (root.expanded ? appName.height + body.height + actions.height + actions.anchors.topMargin : bodyPreview.height), Config.notifs.sizes.image)
    // Full external card height (animation target). MUST equal the height
    // that the card actually renders at — Content.qml sums this across
    // visible cards to size the notifications stack, and any divergence
    // clips the last card.
    readonly property int nonAnimHeight: contentInnerHeight + inner.anchors.margins * 2
    property bool expanded: Config.notifs.openExpanded

    readonly property bool isCritical: root.modelData.urgency === NotificationUrgency.Critical
    // Card body is ALWAYS neutral surfaceContainerHigh regardless of urgency.
    // Critical urgency is signaled by the left accent stripe (declared after
    // the MouseArea below), NOT by tinting the whole card. The previous
    // full-card m3error treatment was visually jarring and clashed with
    // onSurface text/icon colors (which weren't recomputed for the red bg).
    // Do not re-add the urgency branch here — the stripe is the signal.
    readonly property color cardBaseColor: Colours.palette.m3surfaceContainerHigh
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
    // Card height = inner content + top/bottom margins. inner is only top-
    // anchored (no bottom anchor), so we add the bottom margin here at the
    // root level. nonAnimHeight (the stable animation target) MUST equal
    // this — Content.qml sums it for stack sizing.
    implicitHeight: inner.implicitHeight + inner.anchors.margins * 2

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

            // Use contentInnerHeight (no margins) — margins are applied at
            // root level so root.implicitHeight = contentInnerHeight + margins*2.
            implicitHeight: root.contentInnerHeight

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

                // Vertically center against the inner content area so the
                // icon sits in the visual midline of the card regardless of
                // text length. Combined with contentInnerHeight's Math.max,
                // this means the icon stays centered when text is shorter
                // than the icon AND when expanded text is taller than it.
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
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

                        // Observability: log when the main image fails to
                        // render. Covers (a) restored notifications whose
                        // cached PNG was cleaned up, and (b) transient temp
                        // paths (e.g. Chromium temp files) deleted before
                        // first paint. Grep `[notif-debug] image-failed`.
                        onStatusChanged: {
                            if (status === Image.Error || status === Image.Null) {
                                console.warn(`[notif-debug] image-failed id=${root.modelData.id} appName='${root.modelData.appName}'`, `source='${(source.toString() || "").slice(0, 120)}' status=${status}`);
                            }
                        }
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

                        // Skip when the sender gave a system icon name that
                        // didn't resolve — the MaterialIcon fallback below
                        // takes over so the disc isn't blank.
                        active: root.hasAppIcon && (root.hasTransparentIcon || root.systemIconResolves)
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
                            // Reuse the root-level resolved path so we don't
                            // re-run the icon-theme lookup on every paint.
                            source: root.resolvedSystemIconPath
                            colour: Colours.palette.m3onSurface
                            layer.enabled: root.modelData.appIcon.endsWith("symbolic")
                        }
                    }

                    Loader {
                        // Active when the icon Loader above is not active
                        // (no icon provided, or system icon name that didn't
                        // resolve against any installed theme). Binding to
                        // !icon.active makes the inverse relationship explicit
                        // and keeps both Loaders in sync automatically.
                        active: !icon.active
                        asynchronous: true
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: -Appearance.font.size.large * 0.02
                        anchors.verticalCenterOffset: Appearance.font.size.large * 0.02

                        sourceComponent: MaterialIcon {
                            text: Icons.getNotifIcon(root.modelData.summary, root.modelData.urgency)

                            color: Colours.palette.m3onSurface
                            // Use `larger` (15pt default) rather than `large`
                            // (18pt) to fit the smaller default disc (24px
                            // visible from a 32px reservation). 18pt would
                            // hug the disc edges; 15pt lands at ~62% disc
                            // fill which matches the previous design ratio.
                            font.pointSize: Appearance.font.size.larger
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

    // Critical-urgency left accent stripe. Moves the urgency signal from
    // "tint the whole card body" to "6px red bar at the left edge", which is
    // far less visually jarring while still distinguishing critical from
    // normal at a glance. The outer ClippingRectangle clips the stripe to
    // the cardBody's rounded shape so it conforms to the top-left and
    // bottom-left corner curves — anchoring a plain Rectangle here without
    // the rounded clip would render a square stub poking past those curves.
    // z: 1 keeps it above the MouseArea's content so future layout changes
    // can't accidentally occlude it.
    ClippingRectangle {
        anchors.fill: parent
        color: "transparent"
        radius: root.radius
        visible: root.isCritical
        z: 1

        Rectangle {
            width: 6
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            // m3powerButton (saturated coral-red, same hue as the bar's power
            // icon), NOT m3error: m3error is the MD3 token for error *text*
            // on dark surfaces and resolves to pale pink (#ffb4ab) — which
            // read as dim against the dark card body. m3powerButton (#E0685F)
            // is the scheme's designated high-visibility accent and stays
            // theme-correct on rescheme.
            color: Colours.palette.m3powerButton
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
