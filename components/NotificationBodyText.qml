import qs.services
import Symmetria
import QtQuick

StyledText {
    id: root

    property string bodyText: ""

    // WORKAROUND: Qt's Markdown links ignore linkColor, and the HTML export needs
    // RichText to preserve CSS formatting. Remove when Qt supports themed Markdown links.
    textFormat: Text.RichText
    text: CUtils.notificationBodyHtml(root.bodyText, Colours.palette.m3primary, root.font)
}
