import qs.config
import QtQuick

// Claymorphism content frame — pairs a PillCard background with an
// auto-margined, vertically-centered content slot. Replaces the
// boilerplate stencil that appeared in every bar popout framing a
// content region inside a claymorphism card:
//
//   Item {
//       implicitWidth: <fixed | inner.implicitWidth + 2*padding>
//       implicitHeight: inner.implicitHeight + 2*padding
//       PillCard { anchors.fill: parent }
//       <Layout> {
//           anchors.left/right; verticalCenter
//           anchors.leftMargin/rightMargin: <padding>
//           ...
//       }
//   }
//
// `contentMargins` defaults to `padding.large` (15) — the tier used by
// every single-card popout. Multi-card stacks (Weather, Updates, Ram)
// opt down to `padding.normal` (10) for compact section spacing.
//
// `card` alias exposes the underlying PillCard for per-instance overrides
// (e.g. `clipContent`, custom radius for nested contexts).
//
// Why `implicitWidth` is NOT auto-derived: anchoring the content holder
// to both sides of root creates a width cycle (root.implicitWidth ->
// contentHolder.implicitWidth -> childrenRect.width -> contentHolder.width
// -> root.width). Every existing consumer already supplies a width
// explicitly, so making consumers opt in to one of the two patterns
// avoids the cycle.
//
// Consumer patterns:
//
//   // A — content-derived width (single-card popout, no fixed size)
//   PillCardSection {
//       id: section
//       implicitWidth: layout.implicitWidth + section.contentMargins * 2
//       ColumnLayout {
//           id: layout
//           anchors.left: parent.left; anchors.right: parent.right
//           // children
//       }
//   }
//
//   // B — fixed width (popouts pinned to a Config.bar.sizes value)
//   PillCardSection {
//       implicitWidth: Config.bar.sizes.networkWidth
//       ColumnLayout { anchors.left: parent.left; anchors.right: parent.right; ... }
//   }
//
//   // C — fill-parent width (sections stacked inside a sized outer Column)
//   PillCardSection {
//       width: parent.width
//       contentMargins: Appearance.padding.normal
//       ColumnLayout { anchors.left: parent.left; anchors.right: parent.right; ... }
//   }

Item {
    id: root

    property real contentMargins: Appearance.padding.large
    property alias card: card

    default property alias content: contentHolder.data

    implicitHeight: contentHolder.implicitHeight + contentMargins * 2

    PillCard {
        id: card
        anchors.fill: parent
    }

    Item {
        id: contentHolder

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: root.contentMargins
        anchors.rightMargin: root.contentMargins

        implicitHeight: childrenRect.height
    }
}
