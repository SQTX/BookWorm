import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import WormBook

Item {
    id: bookListPage

    signal bookSelected(int bookId)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingXL
        spacing: Theme.spacingLarge

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingLarge

            Text {
                text: "Library"
                color: Theme.textOnBackground
                font.pixelSize: Theme.fontSizeHeader
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            // Type distribution
            Text {
                text: {
                    var dummy = bookController.model.count;
                    var dist = bookController.getTypeDistribution();
                    var keys = Object.keys(dist).sort();
                    var parts = [];
                    for (var i = 0; i < keys.length; i++) {
                        var k = keys[i];
                        var label = k.charAt(0).toUpperCase() + k.slice(1) + "s";
                        parts.push(label + ": " + dist[k]);
                    }
                    return parts.length > 0 ? parts.join("  \u00B7  ") : "0 books";
                }
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                verticalAlignment: Text.AlignVCenter
            }
        }

        // Search & filter bar
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSmall

            // Search field
            TextField {
                id: searchField
                Layout.preferredWidth: 220
                Layout.preferredHeight: 36
                topPadding: 6
                bottomPadding: 6
                font.pixelSize: Theme.fontSizeMedium
                placeholderText: "\u{1F50D} Search title / author..."
                Material.accent: Theme.primary
                onTextChanged: bookController.searchQuery = text
            }

            // Date filter (month picker for "read" date)
            TextField {
                id: dateFilterField
                Layout.preferredWidth: 100
                Layout.preferredHeight: 36
                topPadding: 6
                bottomPadding: 6
                font.pixelSize: Theme.fontSizeSmall
                placeholderText: "MM-YYYY"
                Material.accent: Theme.primary
                validator: RegularExpressionValidator { regularExpression: /[0-9\-]*/ }
                maximumLength: 7
                onTextChanged: {
                    // Parse MM-YYYY to ISO YYYY-MM-01
                    var t = text.trim();
                    if (t.length === 7) {
                        var parts = t.split("-");
                        if (parts.length === 2) {
                            var iso = parts[1] + "-" + parts[0] + "-01";
                            bookController.filterEndDate = iso;
                            return;
                        }
                    }
                    bookController.filterEndDate = "";
                }

                ToolButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20; height: 20
                    visible: dateFilterField.text !== ""
                    contentItem: Text {
                        text: "\u2715"
                        color: Theme.textSecondary
                        font.pixelSize: 9
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: { dateFilterField.text = ""; }
                }
            }

            Item { Layout.fillWidth: true }

            // Status filter chips
            Row {
                spacing: Theme.spacingSmall

                Repeater {
                    model: [
                        { label: "All",       value: "" },
                        { label: "Reading",   value: "reading" },
                        { label: "Read",      value: "read" },
                        { label: "Planned",   value: "planned" },
                        { label: "Abandoned", value: "abandoned" }
                    ]

                    Rectangle {
                        required property var modelData
                        required property int index
                        width: filterChipText.implicitWidth + Theme.spacingLarge
                        height: 28
                        radius: 14
                        color: bookController.filterStatus === modelData.value
                               ? Theme.primary : Theme.surfaceVariant
                        border.width: 1
                        border.color: bookController.filterStatus === modelData.value
                                      ? "transparent" : Theme.divider

                        Text {
                            id: filterChipText
                            anchors.centerIn: parent
                            text: modelData.label
                            color: bookController.filterStatus === modelData.value
                                   ? Theme.textOnPrimary : Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: bookController.filterStatus === modelData.value
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: bookController.filterStatus = modelData.value
                        }
                    }
                }
            }

            // Add book button
            RoundButton {
                width: 36; height: 36
                icon.source: "qrc:/qt/qml/WormBook/src/img/icons/add-book.svg"
                icon.width: 18; icon.height: 18
                icon.color: Theme.textOnPrimary
                Material.background: Theme.primary
                onClicked: addDialog.open()
            }
        }

        // Book grid
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            GridView {
                id: gridView
                anchors.fill: parent
                cellWidth: 196
                cellHeight: 316
                model: bookController.model

                delegate: Item {
                    id: cellDelegate
                    width: gridView.cellWidth
                    height: gridView.cellHeight

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

                    BookCard {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 8
                        width: 180
                        height: 300
                        bookId: cellDelegate.bookId
                        title: cellDelegate.title
                        author: cellDelegate.author
                        rating: cellDelegate.rating
                        status: cellDelegate.status
                        coverImagePath: cellDelegate.coverImagePath
                        genre: cellDelegate.genre
                        pageCount: cellDelegate.pageCount
                        currentPage: cellDelegate.currentPage
                        tags: cellDelegate.tags
                        onClicked: bookListPage.bookSelected(cellDelegate.bookId)
                    }

                    // Row separator — full width, drawn only from first cell in row
                    Rectangle {
                        anchors.bottom: parent.bottom
                        x: -cellDelegate.x
                        width: gridView.width
                        height: 1
                        color: Theme.divider
                        opacity: 0.3
                        visible: cellDelegate.x < gridView.cellWidth
                    }
                }

                // Empty state
                Text {
                    anchors.centerIn: parent
                    visible: gridView.count === 0
                    text: searchField.text ? "No books match your search" : "No books yet. Click + to add one!"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeLarge
                }
            }
        }
    }

    // Add book dialog
    BookForm {
        id: addDialog
        mode: "add"
        onAccepted: {
            bookController.addBook(bookData);
        }
    }
}
