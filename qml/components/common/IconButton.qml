import QtQuick
import QtQuick.Controls
import BookWorm

// Square icon-only button for toolbar actions that have no room for a label.
//
// Material's RoundButton was being used for this, which drew a flat circle with
// no resting outline — at 34px it read as a smudge rather than a control.
Rectangle {
    id: root

    property string iconSource: ""
    property int iconSize: 18
    property color iconColor: Theme.textSecondary
    property string tooltip: ""
    property bool enabledState: true

    signal clicked()

    implicitWidth: 38
    implicitHeight: 38

    radius: Theme.radiusControl
    color: mouseArea.pressed ? Theme.pressed
                             : (mouseArea.containsMouse ? Theme.hover : Theme.surfaceVariant)
    border.width: 1
    border.color: mouseArea.containsMouse ? Theme.primary : Theme.outline
    opacity: enabledState ? 1.0 : 0.4
    scale: mouseArea.pressed ? 0.96 : 1.0

    Behavior on color        { ColorAnimation  { duration: Theme.durationFast } }
    Behavior on border.color { ColorAnimation  { duration: Theme.durationFast } }
    Behavior on scale        { NumberAnimation { duration: Theme.durationFast; easing.type: Theme.easeOut } }

    // SVGs cannot be tinted through Image; ToolButton's icon can. Stripped of its
    // own background and focus so it stays purely decorative — the MouseArea
    // below is declared after it and takes the clicks.
    ToolButton {
        anchors.centerIn: parent
        focusPolicy: Qt.NoFocus
        hoverEnabled: false
        background: Item {}
        icon.source: root.iconSource
        icon.width: root.iconSize
        icon.height: root.iconSize
        icon.color: mouseArea.containsMouse ? Theme.textOnSurface : root.iconColor
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabledState
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    ToolTip.visible: root.tooltip !== "" && mouseArea.containsMouse
    ToolTip.text: root.tooltip
    ToolTip.delay: 400
}
