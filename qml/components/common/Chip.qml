import QtQuick
import BookWorm

// The selectable pill used for status filters, period units and audio modes.
// Four near-identical copies existed across BookListView, ChallengesView,
// BookForm and the settings popup.
Rectangle {
    id: root

    property string text: ""
    property bool selected: false
    property color accent: Theme.primary
    // Some chips are labels rather than controls (a metric badge on a card).
    property bool interactive: true

    signal clicked()

    implicitWidth: chipLabel.implicitWidth + Theme.spacingLarge + Theme.spacingSmall
    implicitHeight: Theme.chipHeight

    radius: height / 2
    color: selected ? accent
                    : (mouseArea.containsMouse && interactive ? Theme.hover : Theme.surfaceVariant)
    border.width: 1
    border.color: selected ? "transparent"
                           : (mouseArea.containsMouse && interactive ? accent : Theme.outline)

    scale: mouseArea.pressed && interactive ? 0.96 : 1.0

    Behavior on color        { ColorAnimation  { duration: Theme.durationFast } }
    Behavior on border.color { ColorAnimation  { duration: Theme.durationFast } }
    Behavior on scale        { NumberAnimation { duration: Theme.durationFast; easing.type: Theme.easeOut } }

    Text {
        id: chipLabel
        anchors.centerIn: parent
        text: root.text
        color: root.selected ? Theme.textOnPrimary : Theme.textSecondary
        font.pixelSize: Theme.fontSizeSmall
        font.bold: root.selected

        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: root.interactive
        enabled: root.interactive
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
