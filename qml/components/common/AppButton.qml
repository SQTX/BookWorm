import QtQuick
import BookWorm

// One button for the whole app.
//
// Before this there were three parallel implementations: Material `Button`,
// `RoundButton`, and hand-rolled `Rectangle` + `MouseArea` blocks — each with its
// own height, radius and hover rule. Destructive actions in particular were
// copy-pasted with literal reds.
Rectangle {
    id: root

    // "primary" — filled, accent coloured, for the main action of a surface
    // "danger"  — filled red, for destructive actions
    // "ghost"   — text only, for secondary actions next to a primary one
    // "outline" — bordered, for neutral actions that still need a target
    property string variant: "primary"

    property string text: ""
    property string iconSource: ""
    property bool enabledState: true

    signal clicked()

    readonly property bool _hovered: mouseArea.containsMouse && root.enabledState
    readonly property bool _pressed: mouseArea.pressed && root.enabledState

    readonly property color _base: {
        switch (variant) {
            case "danger":  return Theme.danger;
            case "ghost":   return "transparent";
            case "outline": return "transparent";
            default:        return Theme.primary;
        }
    }
    readonly property color _baseHover: {
        switch (variant) {
            case "danger":  return Theme.dangerHover;
            case "ghost":   return Theme.hover;
            case "outline": return Theme.hover;
            default:        return Theme.primaryVariant;
        }
    }
    readonly property color _label: {
        switch (variant) {
            case "danger":  return Theme.dangerText;
            case "ghost":   return Theme.primary;
            case "outline": return Theme.textOnSurface;
            default:        return Theme.textOnPrimary;
        }
    }

    // No explicit width/height — a layout parent overrides these when it needs to
    // stretch the button, and they hug the label everywhere else.
    implicitHeight: Theme.controlHeight + 2
    implicitWidth: contentRow.implicitWidth + Theme.spacingLarge + Theme.spacingSmall

    radius: Theme.radiusControl
    color: _pressed ? Qt.darker(_baseHover, 1.15)
                    : (_hovered ? _baseHover : _base)
    border.width: variant === "outline" ? 1 : 0
    border.color: _hovered ? Theme.primary : Theme.outline
    opacity: enabledState ? 1.0 : 0.4

    // A press that only changes colour reads as a flat image; the 1% dip is what
    // makes the control feel physical.
    scale: _pressed ? 0.98 : 1.0

    Behavior on color   { ColorAnimation  { duration: Theme.durationFast } }
    Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }
    Behavior on scale   { NumberAnimation { duration: Theme.durationFast; easing.type: Theme.easeOut } }

    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: Theme.spacingMedium

        Image {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.iconSource !== ""
            source: root.iconSource
            sourceSize.width: 16
            sourceSize.height: 16
            width: 16
            height: 16
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: root._label
            font.pixelSize: Theme.fontSizeMedium
            font.bold: root.variant === "primary" || root.variant === "danger"
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabledState
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
