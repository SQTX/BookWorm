import QtQuick
import QtQuick.Layouts
import BookWorm

// The title block every page opens with.
//
// The five views each had their own header with slightly different margins and
// alignment, so switching pages nudged the title a few pixels. Actions declared
// as children land in the right-hand slot, vertically centred against the title.
Item {
    id: root

    property string title: ""
    // Optional line under the title — counts, distributions, context.
    property string subtitle: ""
    // Runs along the bottom of the title, drawn in the page accent.
    property bool showRule: true

    default property alias actions: actionRow.data

    implicitHeight: headerRow.implicitHeight + (showRule ? Theme.spacingMedium + 1 : 0)

    RowLayout {
        id: headerRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Theme.spacingLarge

        ColumnLayout {
            spacing: Theme.spacingXS

            Text {
                text: root.title
                color: Theme.textOnBackground
                font.pixelSize: Theme.fontSizeHeader
                font.bold: true
                font.letterSpacing: -0.5
            }

            Text {
                Layout.fillWidth: true
                visible: root.subtitle !== ""
                text: root.subtitle
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
            }
        }

        Item { Layout.fillWidth: true }

        RowLayout {
            id: actionRow
            Layout.alignment: Qt.AlignVCenter
            spacing: Theme.spacingMedium
        }
    }

    // A hairline rather than a full divider — enough to seat the title without
    // boxing the page in.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        visible: root.showRule
        color: Theme.outline
    }

    // Entrance: the title settles in rather than snapping into place on every
    // page switch. Paired with the StackView fade in Main.qml.
    opacity: 0
    Component.onCompleted: introAnim.start()

    ParallelAnimation {
        id: introAnim
        NumberAnimation {
            target: root; property: "opacity"
            from: 0; to: 1
            duration: Theme.durationMedium
        }
        NumberAnimation {
            target: headerRow; property: "y"
            from: 8; to: 0
            duration: Theme.durationSlow
            easing.type: Theme.easeOut
        }
    }
}
