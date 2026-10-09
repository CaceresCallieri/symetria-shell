import qs.services
import Symmetria
import QtQuick

StyledText {
    id: root

    property string bodyText: ""

    textFormat: Text.RichText
    text: CUtils.notificationBodyHtml(root.bodyText, Colours.palette.m3primary, root.font)
}
