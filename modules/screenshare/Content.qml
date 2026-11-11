pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.config
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

KeyboardController {
    id: root

    controls: selection.mode === "region" ? [outputChooser, resetRegionButton, rememberControl, helpButton, cancelButton, shareButton, header.trailingItem] : [rememberControl, helpButton, cancelButton, shareButton, header.trailingItem]
    readonly property var modeLabels: ["Ventanas", "Pantallas", "Espacios", "Región"] // intentional var: mode labels
    readonly property var modeIcons: ["select_window", "monitor", "workspaces", "crop_free"] // intentional var: icon names

    focus: true
    selectionModel: selection
    searchInput: search
    columns: grid.columns
    onConfirmRequested: ScreenShare.confirm(selection.selection())
    onCancelRequested: ScreenShare.cancel()
    onSelectionMoved: index => grid.positionViewAtIndex(index, GridView.Contain)
    Component.onCompleted: selection.load(ScreenShare.context)

    SelectionModel {
        id: selection
        onModeIndexChanged: outputChooser.popup.close()
    }

    PillCard {
        anchors.fill: parent
    }
    // Consume clicks inside the card so only the surrounding scrim cancels.
    MouseArea {
        anchors.fill: parent
        onClicked: root.focusSources()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Math.min(root.height < 600 ? 12 : 24, root.width * 0.04)
        spacing: root.height < 600 ? 8 : 16

        HeaderLayout {
            id: header
            Layout.fillWidth: true
            leading: MaterialIcon {
                text: "screen_share"
            }
            heading: ColumnLayout {
                StyledText {
                    Layout.fillWidth: true
                    text: "Compartir pantalla"
                    font.pointSize: Appearance.font.size.large
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: "Elegí qué querés mostrar."
                    opacity: 0.65
                    elide: Text.ElideRight
                }
            }
            trailing: ActionButton {
                Keys.forwardTo: [root]
                closeControl: true
                onClicked: ScreenShare.cancel()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Repeater {
                model: 4
                ActionButton {
                    Keys.forwardTo: [root]
                    required property int index
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    iconName: root.modeIcons[index]
                    text: root.modeLabels[index]
                    selected: selection.modeIndex === index
                    onClicked: {
                        selection.setMode(index);
                        search.text = "";
                        root.focusSources();
                    }
                }
            }
        }

        StyledTextField {
            id: search
            Keys.forwardTo: [root]
            visible: selection.mode !== "region"
            Layout.fillWidth: true
            implicitHeight: 32
            placeholderText: "Buscar…"
            onTextEdited: selection.setQuery(text)
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0

            GridView {
                id: grid
                anchors.fill: parent
                visible: selection.mode !== "region"
                clip: true
                readonly property int columns: Math.max(1, Math.floor(width / 230))
                cellWidth: width / columns
                cellHeight: Math.min(150, (cellWidth - 16) * 0.56) + 68
                model: selection.items
                currentIndex: selection.currentIndex
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}

                delegate: AbstractButton {
                    id: tile
                    required property var modelData
                    required property int index
                    width: grid.cellWidth - 12
                    height: grid.cellHeight - 12
                    focusPolicy: Qt.NoFocus
                    Accessible.name: `${modelData.title}, ${modelData.app}, ${modelData.detail}`
                    onClicked: {
                        selection.currentIndex = index;
                        root.focusSources();
                    }
                    onDoubleClicked: root.confirm()
                    Component.onCompleted: {
                        if (selection.mode === "windows")
                            ScreenShare.requestThumbnail(modelData.id);
                    }
                    background: PillCard {
                        borderWidth: selection.currentIndex === tile.index ? 2 : 1
                        borderColor: selection.currentIndex === tile.index ? Colours.palette.m3onSurface : Colours.palette.m3outlineVariant
                        color: Colours.pillStyle(Colours.palette.m3surfaceContainerLow, tile.hovered ? Colours.glass.strong : Colours.glass.medium).background
                    }
                    contentItem: ColumnLayout {
                        spacing: 8
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 0
                            Image {
                                anchors.fill: parent
                                anchors.margins: 6
                                source: tile.modelData.thumbnail || ScreenShare.thumbnails[tile.modelData.id] || ""
                                sourceSize: Qt.size(720, 150)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }
                            MaterialIcon {
                                anchors.centerIn: parent
                                text: tile.modelData.icon
                                visible: !tile.modelData.thumbnail && !ScreenShare.thumbnails[tile.modelData.id]
                                font.pointSize: 32
                                opacity: 0.5
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.margins: 10
                            spacing: 3
                            StyledText {
                                Layout.fillWidth: true
                                text: tile.modelData.title
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: `${tile.modelData.app} · ${tile.modelData.detail}`
                                opacity: 0.6
                                elide: Text.ElideRight
                                font.pointSize: Appearance.font.size.small
                            }
                        }
                    }
                }
            }

            StyledText {
                anchors.centerIn: parent
                visible: selection.mode !== "region" && selection.items.length === 0
                text: "No hay fuentes disponibles."
            }

            ColumnLayout {
                anchors.fill: parent
                visible: selection.mode === "region"
                spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    ComboBox {
                        id: outputChooser
                        Keys.forwardTo: [root]
                        Layout.fillWidth: true
                        model: selection.outputs.map(item => `${item.name} · ${item.width} × ${item.height}`)
                        currentIndex: selection.outputIndex
                        onActivated: index => {
                            selection.selectOutput(index);
                            root.focusSources();
                        }
                        contentItem: StyledText {
                            text: outputChooser.displayText
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        background: PillSurface {}
                    }
                    ActionButton {
                        id: resetRegionButton
                        Keys.forwardTo: [root]
                        text: "Restablecer"
                        enabled: selection.region !== null
                        onClicked: {
                            selection.region = null;
                            root.focusSources();
                        }
                    }
                }
                RegionPreview {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    selectionModel: selection
                    imageSource: ScreenShare.context.sources?.screens?.find(item => item.app === selection.output?.name)?.thumbnail ?? ""
                    accentColor: Colours.palette.m3onSurface
                }
                StyledText {
                    text: selection.regionSize
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }
        }

        StyledText {
            visible: ScreenShare.errorMessage !== ""
            text: ScreenShare.errorMessage
            color: Colours.palette.m3error
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                StyledText {
                    text: "Recordar esta selección"
                }
                StyledText {
                    text: "La aplicación podrá volver a compartir sin preguntar."
                    opacity: 0.6
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }
            StyledSwitch {
                id: rememberControl
                Keys.forwardTo: [root]
                checked: selection.remember
                Accessible.name: "Recordar esta selección"
                onToggled: selection.remember = checked
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -3
                    color: "transparent"
                    radius: height / 2
                    border.width: 2
                    border.color: Colours.palette.m3onSurface
                    visible: rememberControl.activeFocus
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            ActionButton {
                id: helpButton
                Keys.forwardTo: [root]
                text: "Atajos"
                iconName: "keyboard"
                onClicked: {
                    root.openHelp();
                }
            }
            Item {
                Layout.fillWidth: true
            }
            ActionButton {
                id: cancelButton
                Keys.forwardTo: [root]
                text: "Cancelar"
                onClicked: ScreenShare.cancel()
            }
            ActionButton {
                id: shareButton
                Keys.forwardTo: [root]
                text: ScreenShare.submitting ? "Compartiendo…" : "Compartir"
                iconName: "screen_share"
                enabled: selection.canConfirm && !ScreenShare.submitting
                selected: true
                onClicked: root.confirm()
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#dd000000"
        visible: root.helpOpen
        MouseArea {
            anchors.fill: parent
            onClicked: root.closeHelp()
        }
        PillCard {
            anchors.centerIn: parent
            width: Math.min(root.width - 32, 480)
            height: helpText.implicitHeight + 48
            StyledText {
                id: helpText
                anchors.fill: parent
                anchors.margins: 24
                text: "Tab / Shift+Tab   Cambiar modo\n1–4   Elegir modo\nhjkl / Flechas   Mover selección\nShift + dirección   Ajustar región\n/   Buscar\nF6 / Shift+F6   Recorrer controles\nr   Recordar selección\nDelete   Borrar región\nEnter   Compartir\nEsc / q   Cancelar\n\nEsc o Enter para volver"
                wrapMode: Text.Wrap
            }
        }
    }
}
