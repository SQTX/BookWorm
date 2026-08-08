import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import BookWorm

// Shown where a list or chart has nothing to draw.
//
// A single centred sentence in the middle of a large blank area reads as a bug.
// An icon, a heading, one line of guidance and (where there is one) the action
// that fixes it reads as a designed state.
Item {
    id: root

    property string icon: ""
    property string title: ""
    property string hint: ""
    // Leave empty to omit the button entirely.
    property string actionText: ""
    // Compact drops the icon — for small sections inside a page rather than a
    // whole empty page.
    property bool compact: false

    signal actionClicked()

    implicitHeight: column.implicitHeight
    implicitWidth: column.implicitWidth

    ColumnLayout {
        id: column
        anchors.centerIn: parent
        width: Math.min(root.width > 0 ? root.width : 340, 340)
        spacing: Theme.spacingSmall

        // The icon sits in a soft disc so it reads as an illustration instead of
        // a stray glyph. SVGs cannot be tinted through Image, hence the ToolButton
        // (focus and background stripped so it stays decorative).
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: Theme.spacingXS
            visible: !root.compact && root.icon !== ""
            width: 54
            height: 54
            radius: 27
            color: Theme.surfaceVariant
            opacity: 0.6

            ToolButton {
                anchors.centerIn: parent
                focusPolicy: Qt.NoFocus
                hoverEnabled: false
                background: Item {}
                icon.source: root.icon
                icon.width: 24
                icon.height: 24
                icon.color: Theme.textSecondary
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.title !== ""
            text: root.title
            color: Theme.textOnBackground
            font.pixelSize: root.compact ? Theme.fontSizeMedium : Theme.fontSizeLarge
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Text {
            Layout.fillWidth: true
            visible: root.hint !== ""
            text: root.hint
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            lineHeight: 1.3
        }

        AppButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Theme.spacingSmall
            visible: root.actionText !== ""
            variant: "outline"
            text: root.actionText
            onClicked: root.actionClicked()
        }
    }

    opacity: 0
    Component.onCompleted: fadeIn.start()

    NumberAnimation {
        id: fadeIn
        target: root
        property: "opacity"
        from: 0
        to: 1
        duration: Theme.durationSlow
        easing.type: Theme.easeOut
    }
}
