import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import WormBook

Rectangle {
    id: card

    required property int bookId
    required property string title
    required property string author
    required property int rating
    required property string status
    required property string coverImagePath
    required property string genre

    signal clicked()

    width: 200
    height: 280
    radius: Theme.radiusMedium
    color: Theme.surface
    border.color: mouseArea.containsMouse ? Theme.primary : "transparent"
    border.width: 1

    Behavior on border.color { ColorAnimation { duration: 150 } }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.clicked()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingMedium
        spacing: Theme.spacingSmall

        // Cover image placeholder
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 140
            radius: Theme.radiusSmall
            color: Theme.surfaceVariant

            Image {
                anchors.fill: parent
                source: card.coverImagePath ? "file://" + card.coverImagePath : ""
                fillMode: Image.PreserveAspectCrop
                visible: status === Image.Ready
                clip: true
            }

            // Fallback icon when no cover
            Text {
                anchors.centerIn: parent
                text: "\u{1F4D6}"
                font.pixelSize: 48
                visible: !card.coverImagePath || card.coverImagePath === ""
                opacity: 0.5
            }
        }

        // Title
        Text {
            Layout.fillWidth: true
            text: card.title
            color: Theme.textOnSurface
            font.pixelSize: Theme.fontSizeMedium
            font.bold: true
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.Wrap
        }

        // Author
        Text {
            Layout.fillWidth: true
            text: card.author
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeSmall
            elide: Text.ElideRight
        }

        // Rating stars
        Row {
            spacing: 2
            visible: card.rating > 0

            Repeater {
                model: 6
                Text {
                    text: index < card.rating ? "\u2605" : "\u2606"
                    color: index < card.rating ? Theme.primary : Theme.textSecondary
                    font.pixelSize: 14
                }
            }
        }

        Item { Layout.fillHeight: true }

        // Status badge
        Rectangle {
            Layout.alignment: Qt.AlignLeft
            implicitWidth: statusLabel.implicitWidth + Theme.spacingLarge
            implicitHeight: 22
            radius: 11
            color: Theme.statusColor(card.status)
            opacity: 0.85

            Text {
                id: statusLabel
                anchors.centerIn: parent
                text: Theme.statusLabel(card.status)
                color: "#000000"
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }
        }
    }
}
