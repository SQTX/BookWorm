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
    required property int pageCount
    required property int currentPage
    required property string tags

    signal clicked()

    width: 180
    height: 300
    radius: Theme.radiusMedium
    color: Theme.surface
    clip: true

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.clicked()
    }

    Column {
        anchors.fill: parent
        spacing: 0

        // ── Status bar (full width) ──
        Rectangle {
            width: parent.width
            height: 22
            color: Theme.statusColor(card.status)
            radius: Theme.radiusMedium

            // Square off bottom corners
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: Theme.radiusMedium
                color: parent.color
            }

            Row {
                anchors.centerIn: parent
                spacing: 4

                Text {
                    text: card.status === "read" ? "\u2714"
                        : card.status === "reading" ? "\u25CF"
                        : card.status === "abandoned" ? "\u2715"
                        : "\u2026"
                    color: "#000000"
                    font.pixelSize: 10
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: Theme.statusLabel(card.status)
                    color: "#000000"
                    font.pixelSize: 11
                    font.bold: true
                }
            }
        }

        // ── Separator line between status bar and cover ──
        Rectangle {
            width: parent.width
            height: 1
            color: Theme.divider
        }

        // ── Cover image ──
        // 6:9 book format → height = width * (9/6) = width * 1.5
        // Available for cover: card.height - statusBar(22) - infoArea(~100) ≈ 178
        // width * 1.5 = 180 * 1.5 = 270, but we cap at available space
        Rectangle {
            width: parent.width
            height: Math.min(parent.width * 1.4, card.height - 23 - infoCol.implicitHeight)
            color: Theme.surfaceVariant
            clip: true

            Image {
                anchors.fill: parent
                source: card.coverImagePath ? "file://" + card.coverImagePath : ""
                fillMode: Image.PreserveAspectCrop
                visible: status === Image.Ready
            }

            Text {
                anchors.centerIn: parent
                text: "\u{1F4D6}"
                font.pixelSize: 40
                visible: !card.coverImagePath || card.coverImagePath === ""
                opacity: 0.3
            }
        }

        // ── Info area ──
        Column {
            id: infoCol
            width: parent.width
            padding: Theme.spacingMedium
            topPadding: 6
            bottomPadding: 6
            spacing: 3

            // Title
            Text {
                width: parent.width - parent.padding * 2
                text: card.title
                color: Theme.textOnSurface
                font.pixelSize: 13
                font.bold: true
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
                lineHeight: 1.1
            }

            // Author
            Text {
                width: parent.width - parent.padding * 2
                text: card.author
                color: Theme.textSecondary
                font.pixelSize: 11
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            // ── Stars — only when read and has rating ──
            Row {
                spacing: 1
                visible: card.status === "read" && card.rating > 0

                Repeater {
                    model: 6
                    Text {
                        required property int index
                        text: index < card.rating ? "\u2605" : "\u2606"
                        color: index < card.rating ? Theme.primary : Theme.textSecondary
                        font.pixelSize: 14
                    }
                }
            }

            // ── Reading progress — only when reading ──
            Column {
                width: parent.width - parent.padding * 2
                visible: card.status === "reading" && card.pageCount > 0
                spacing: 2

                Rectangle {
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Theme.surfaceVariant

                    Rectangle {
                        width: card.pageCount > 0
                            ? parent.width * Math.min(card.currentPage / card.pageCount, 1.0)
                            : 0
                        height: parent.height
                        radius: 2
                        color: Theme.statusReading
                    }
                }

                Text {
                    text: {
                        var pct = card.pageCount > 0
                            ? Math.round((card.currentPage / card.pageCount) * 100) : 0;
                        return card.currentPage + "/" + card.pageCount + "  (" + pct + "%)";
                    }
                    color: Theme.statusReading
                    font.pixelSize: 10
                    font.bold: true
                }
            }

            // ── Genre tags ──
            Flow {
                width: parent.width - parent.padding * 2
                spacing: 4
                visible: card.genre !== "" || card.tags !== ""

                Repeater {
                    model: {
                        var items = [];
                        if (card.genre)
                            items.push(card.genre);
                        if (card.tags) {
                            var tagList = card.tags.split(",");
                            for (var i = 0; i < tagList.length && items.length < 3; i++) {
                                var t = tagList[i].trim();
                                if (t && t !== card.genre)
                                    items.push(t);
                            }
                        }
                        return items;
                    }

                    Rectangle {
                        required property string modelData
                        implicitWidth: tagText.implicitWidth + 8
                        implicitHeight: 16
                        radius: 3
                        color: Theme.surfaceVariant

                        Text {
                            id: tagText
                            anchors.centerIn: parent
                            text: modelData
                            color: Theme.textSecondary
                            font.pixelSize: 9
                        }
                    }
                }
            }
        }
    }

    // ── Hover border overlay (on top of all content) ──
    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusMedium
        color: "transparent"
        border.width: 2
        border.color: mouseArea.containsMouse ? Theme.statusColor(card.status) : "transparent"

        Behavior on border.color { ColorAnimation { duration: 150 } }
    }
}
