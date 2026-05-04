pragma ComponentBehavior: Bound

import qs.components
import qs.components.effects
import qs.components.controls
import qs.services
import qs.config
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

CustomMouseArea {
    id: root

    required property var state

    readonly property int currMonth: state.currentDate.getMonth()
    readonly property int currYear: state.currentDate.getFullYear()

    // When true (set by popout consumers), the navigation row and the calendar
    // body are each wrapped in a claymorphism PillCard frame, and the chevron
    // arrows are promoted to raised Tonal IconButtons matching the utilities
    // popup. Default false preserves the dashboard's existing flat layout where
    // an outer Rect already provides the panel framing.
    property bool panelMode: false

    anchors.left: parent.left
    anchors.right: parent.right
    implicitWidth: inner.implicitWidth + inner.anchors.margins * 2
    implicitHeight: inner.implicitHeight + inner.anchors.margins * 2

    acceptedButtons: Qt.MiddleButton
    onClicked: root.state.currentDate = new Date()

    function onWheel(event: WheelEvent): void {
        if (event.angleDelta.y > 0)
            root.state.currentDate = new Date(root.currYear, root.currMonth - 1, 1);
        else if (event.angleDelta.y < 0)
            root.state.currentDate = new Date(root.currYear, root.currMonth + 1, 1);
    }

    ColumnLayout {
        id: inner

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Appearance.padding.large
        // Tighter when sections are bare (dashboard); roomier when sections are
        // framed in PillCards (popouts) so the two clay frames breathe.
        spacing: root.panelMode ? Appearance.spacing.normal : Appearance.spacing.small

        // Navigation header — wrapped in a claymorphism PillCard when panelMode
        // (popouts), naked when !panelMode (dashboard, where an outer Rect
        // already provides the panel framing).
        Item {
            id: navSection

            Layout.fillWidth: true
            implicitHeight: monthNavigationRow.implicitHeight + (root.panelMode ? Appearance.padding.normal * 2 : 0)

            PillCard {
                anchors.fill: parent
                visible: root.panelMode
            }

            RowLayout {
                id: monthNavigationRow

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: root.panelMode ? Appearance.padding.normal : 0
                anchors.rightMargin: root.panelMode ? Appearance.padding.normal : 0
                spacing: Appearance.spacing.small

                // Prev month — dashboard variant: naked icon over a hover state
                // layer. Visible only when !panelMode; Layouts skip invisible
                // items so the panel-variant chevron below takes its slot.
                Item {
                    visible: !root.panelMode
                    implicitWidth: implicitHeight
                    implicitHeight: prevMonthText.implicitHeight + Appearance.padding.small * 2

                    StateLayer {

                        radius: Appearance.rounding.full

                        function onClicked(): void {
                            root.state.currentDate = new Date(root.currYear, root.currMonth - 1, 1);
                        }
                    }

                    MaterialIcon {
                        id: prevMonthText

                        anchors.centerIn: parent
                        text: "chevron_left"
                        color: Colours.palette.m3tertiary
                        font.pointSize: Appearance.font.size.normal
                        font.weight: 700
                    }
                }

                // Prev month — popout variant: raised Tonal IconButton matching
                // the utilities popup's pill aesthetic.
                IconButton {
                    visible: root.panelMode
                    icon: "chevron_left"
                    type: IconButton.Tonal
                    toggle: false
                    raised: true
                    onClicked: root.state.currentDate = new Date(root.currYear, root.currMonth - 1, 1)
                }

                Item {
                    Layout.fillWidth: true

                    implicitWidth: monthYearDisplay.implicitWidth + Appearance.padding.small * 2
                    implicitHeight: monthYearDisplay.implicitHeight + Appearance.padding.small * 2

                    StateLayer {
                        anchors.fill: monthYearDisplay
                        anchors.margins: -Appearance.padding.small
                        anchors.leftMargin: -Appearance.padding.normal
                        anchors.rightMargin: -Appearance.padding.normal

                        radius: Appearance.rounding.full
                        disabled: {
                            const now = new Date();
                            return root.currMonth === now.getMonth() && root.currYear === now.getFullYear();
                        }

                        function onClicked(): void {
                            root.state.currentDate = new Date();
                        }
                    }

                    StyledText {
                        id: monthYearDisplay

                        anchors.centerIn: parent
                        text: grid.title
                        color: Colours.palette.m3primary
                        font.pointSize: Appearance.font.size.normal
                        font.weight: 500
                        font.capitalization: Font.Capitalize
                    }
                }

                // Next month — dashboard variant.
                Item {
                    visible: !root.panelMode
                    implicitWidth: implicitHeight
                    implicitHeight: nextMonthText.implicitHeight + Appearance.padding.small * 2

                    StateLayer {

                        radius: Appearance.rounding.full

                        function onClicked(): void {
                            root.state.currentDate = new Date(root.currYear, root.currMonth + 1, 1);
                        }
                    }

                    MaterialIcon {
                        id: nextMonthText

                        anchors.centerIn: parent
                        text: "chevron_right"
                        color: Colours.palette.m3tertiary
                        font.pointSize: Appearance.font.size.normal
                        font.weight: 700
                    }
                }

                // Next month — popout variant.
                IconButton {
                    visible: root.panelMode
                    icon: "chevron_right"
                    type: IconButton.Tonal
                    toggle: false
                    raised: true
                    onClicked: root.state.currentDate = new Date(root.currYear, root.currMonth + 1, 1)
                }
            }
        }

        // Calendar body — day-of-week row + month grid + animated today
        // indicator. Wrapped in a claymorphism PillCard when panelMode (popouts).
        // When !panelMode (dashboard), bodyContent flows directly without an
        // inner frame because the dashboard's outer Rect already provides one.
        Item {
            id: bodySection

            Layout.fillWidth: true
            implicitHeight: bodyContent.implicitHeight + (root.panelMode ? Appearance.padding.normal * 2 : 0)

            PillCard {
                anchors.fill: parent
                visible: root.panelMode
            }

            ColumnLayout {
                id: bodyContent

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: root.panelMode ? Appearance.padding.normal : 0
                spacing: Appearance.spacing.small

                DayOfWeekRow {
                    id: daysRow

                    Layout.fillWidth: true
                    locale: grid.locale

                    delegate: StyledText {
                        required property var model

                        horizontalAlignment: Text.AlignHCenter
                        text: model.shortName
                        font.weight: 500
                        color: (model.day === 0 || model.day === 6) ? Colours.palette.m3secondary : Colours.palette.m3onSurfaceVariant
                    }
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: grid.implicitHeight

                    MonthGrid {
                        id: grid

                        month: root.currMonth
                        year: root.currYear

                        anchors.fill: parent

                        spacing: 3
                        locale: Qt.locale()

                        delegate: Item {
                            id: dayItem

                            required property var model

                            implicitWidth: implicitHeight
                            implicitHeight: text.implicitHeight + Appearance.padding.small * 2

                            StyledText {
                                id: text

                                anchors.centerIn: parent

                                horizontalAlignment: Text.AlignHCenter
                                text: grid.locale.toString(dayItem.model.day)
                                color: {
                                    const dayOfWeek = dayItem.model.date.getUTCDay();
                                    if (dayOfWeek === 0 || dayOfWeek === 6)
                                        return Colours.palette.m3secondary;

                                    return Colours.palette.m3onSurfaceVariant;
                                }
                                opacity: dayItem.model.today || dayItem.model.month === grid.month ? 1 : 0.4
                                font.pointSize: Appearance.font.size.normal
                                font.weight: 500
                            }
                        }
                    }

                    StyledRect {
                        id: todayIndicator

                        readonly property Item todayItem: grid.contentItem.children.find(c => c.model.today) ?? null
                        property Item today

                        onTodayItemChanged: {
                            if (todayItem)
                                today = todayItem;
                        }

                        x: today ? today.x + (today.width - implicitWidth) / 2 : 0
                        y: today?.y ?? 0

                        implicitWidth: today?.implicitWidth ?? 0
                        implicitHeight: today?.implicitHeight ?? 0

                        clip: true
                        radius: Appearance.rounding.full
                        // Match the bar's active workspace pill (ActiveIndicator.qml) and
                        // the active quick toggles (PillToggleSurface.qml): translucent
                        // strong-glass base + two gradient passes producing a top-LEFT
                        // dark / bottom-RIGHT bright depression. Replaces the prior
                        // solid m3primary fill so today's cell reads as "pressed in"
                        // rather than "lit up". Border zeroed so no drawn outline
                        // competes with the gradient-defined depression edges.
                        color: Colours.pillStyle(Colours.palette.m3primary, Colours.glass.strong).background
                        border.width: 0

                        opacity: todayItem ? 1 : 0
                        scale: todayItem ? 1 : 0.7

                        // Vertical depression — top dark, bottom light. Stops mirror
                        // ActiveIndicator / PillToggleSurface so the three pressed
                        // surfaces share an identical feel.
                        Rectangle {
                            anchors.fill: parent
                            radius: todayIndicator.radius
                            color: "transparent"

                            gradient: Gradient {
                                GradientStop { position: 0.00; color: Qt.rgba(0, 0, 0, 0.55) }
                                GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.00) }
                                GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.00) }
                                GradientStop { position: 1.00; color: Qt.rgba(1, 1, 1, 0.12) }
                            }
                        }

                        // Horizontal depression at 50% weight — combined with the
                        // vertical pass, the diagonal makes top-LEFT darkest and
                        // bottom-RIGHT brightest.
                        Rectangle {
                            anchors.fill: parent
                            radius: todayIndicator.radius
                            color: "transparent"

                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.00; color: Qt.rgba(0, 0, 0, 0.55 * 0.5) }
                                GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.00) }
                                GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.00) }
                                GradientStop { position: 1.00; color: Qt.rgba(1, 1, 1, 0.12 * 0.5) }
                            }
                        }

                        // Colouriser declared LAST so the day-number glyph paints on
                        // top of the depression gradients and stays crisp.
                        Colouriser {
                            x: -todayIndicator.x
                            y: -todayIndicator.y

                            implicitWidth: grid.width
                            implicitHeight: grid.height

                            source: grid
                            sourceColor: Colours.palette.m3onSurface
                            // Tint to a light foreground rather than m3onPrimary.
                            // The today pill is a translucent strong-glass base
                            // overlaid with a top-dark depression gradient, so it
                            // renders dark overall — m3onPrimary (#333 in the
                            // warm-neutral dark scheme) tinted today's number
                            // dark-on-dark, making it invisible. m3onSurface is
                            // the bright "text on dark surface" colour and
                            // contrasts with the depression.
                            colorizationColor: Colours.palette.m3onSurface
                        }

                        Behavior on opacity {
                            Anim {}
                        }

                        Behavior on scale {
                            Anim {}
                        }

                        Behavior on x {
                            Anim {
                                duration: Appearance.anim.durations.expressiveDefaultSpatial
                                easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
                            }
                        }

                        Behavior on y {
                            Anim {
                                duration: Appearance.anim.durations.expressiveDefaultSpatial
                                easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
                            }
                        }
                    }
                }
            }
        }
    }
}
