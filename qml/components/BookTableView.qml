import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import WormBook

Item {
    id: tablePage

    signal bookSelected(int bookId)

    // Column definitions
    readonly property var columns: [
        { role: "coverImagePath", label: "",            width: 50,  type: "cover" },
        { role: "title",          label: "Title",       width: -1,  type: "text" },
        { role: "itemType",       label: "Type",        width: 80,  type: "badge" },
        { role: "status",         label: "Status",      width: 110, type: "status" },
        { role: "pageCount",      label: "Pages",       width: 70,  type: "number" },
        { role: "author",         label: "Author",      width: 180, type: "text" },
        { role: "rating",         label: "Rating",      width: 120, type: "stars" },
        { role: "endDate",        label: "Finished",    width: 130, type: "date" },
        { role: "genre",          label: "Genre",       width: 120, type: "text" },
        { role: "tags",           label: "Tags",        width: 130, type: "text" }
    ]

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Header bar
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Theme.spacingLarge
            spacing: Theme.spacingLarge

            Text {
                text: "Table"
                color: Theme.textOnBackground
                font.pixelSize: Theme.fontSizeHeader
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            Text {
                text: bookController.model.count + " books"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeMedium
                verticalAlignment: Text.AlignVCenter
            }
        }

        // Search & filter bar
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacingLarge
            Layout.rightMargin: Theme.spacingLarge
            Layout.bottomMargin: Theme.spacingMedium
            spacing: Theme.spacingMedium

            TextField {
                id: searchField
                Layout.preferredWidth: 300
                placeholderText: "Search by title or author..."
                Material.accent: Theme.primary
                onTextChanged: bookController.searchQuery = text
            }

            Item { Layout.fillWidth: true }

            Row {
                spacing: Theme.spacingSmall

                Repeater {
                    model: [
                        { label: "All", value: "" },
                        { label: "Reading", value: "reading" },
                        { label: "Read", value: "read" },
                        { label: "Planned", value: "planned" }
                    ]

                    Button {
                        text: modelData.label
                        flat: true
                        highlighted: bookController.filterStatus === modelData.value
                        Material.accent: Theme.primary
                        onClicked: bookController.filterStatus = modelData.value
                    }
                }
            }

            RoundButton {
                icon.source: "qrc:/qt/qml/WormBook/src/img/icons/add-book.svg"
                icon.width: 20; icon.height: 20
                icon.color: Theme.textOnPrimary
                Material.background: Theme.primary
                onClicked: addDialog.open()
            }
        }

        // Table header
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            color: Theme.surface

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.divider
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingMedium
                anchors.rightMargin: Theme.spacingMedium

                Repeater {
                    model: tablePage.columns

                    Item {
                        width: modelData.width > 0 ? modelData.width : headerFillWidth()
                        height: parent.height

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingSmall
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                            font.letterSpacing: 0.5
                            elide: Text.ElideRight
                            width: parent.width - Theme.spacingMedium
                        }
                    }
                }
            }
        }

        // Table body
        ListView {
            id: tableList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: bookController.model
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Rectangle {
                id: rowDelegate
                width: tableList.width
                height: 44
                color: rowMouse.containsMouse ? Theme.surfaceVariant : (index % 2 === 0 ? "transparent" : Qt.rgba(1, 1, 1, 0.02))

                required property int index
                required property int bookId
                required property string title
                required property string author
                required property string genre
                required property int pageCount
                required property string startDate
                required property string endDate
                required property int rating
                required property string status
                required property string coverImagePath
                required property string itemType
                required property bool isNonFiction
                required property string tags

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tablePage.bookSelected(rowDelegate.bookId)
                }

                // Bottom border
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Theme.divider
                    opacity: 0.5
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingMedium
                    anchors.rightMargin: Theme.spacingMedium

                    // Cover thumbnail
                    Item {
                        width: 50
                        height: parent.height

                        Rectangle {
                            anchors.centerIn: parent
                            width: 30; height: 38
                            radius: 3
                            color: Theme.surfaceVariant
                            clip: true

                            Image {
                                anchors.fill: parent
                                source: rowDelegate.coverImagePath ? "file://" + rowDelegate.coverImagePath : ""
                                fillMode: Image.PreserveAspectCrop
                                visible: status === Image.Ready
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "\u{1F4D6}"
                                font.pixelSize: 16
                                visible: !rowDelegate.coverImagePath || rowDelegate.coverImagePath === ""
                                opacity: 0.4
                            }
                        }
                    }

                    // Title
                    Item {
                        width: headerFillWidth()
                        height: parent.height

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingSmall
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - Theme.spacingMedium
                            text: rowDelegate.title
                            color: Theme.textOnSurface
                            font.pixelSize: Theme.fontSizeMedium
                            font.bold: true
                            elide: Text.ElideRight
                        }
                    }

                    // Type badge
                    Item {
                        width: 80
                        height: parent.height

                        Rectangle {
                            anchors.centerIn: parent
                            implicitWidth: typeText.implicitWidth + Theme.spacingLarge
                            implicitHeight: 22
                            radius: 4
                            color: Theme.surfaceVariant

                            Text {
                                id: typeText
                                anchors.centerIn: parent
                                text: {
                                    var t = rowDelegate.itemType || "book";
                                    return t.charAt(0).toUpperCase() + t.slice(1);
                                }
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }
                    }

                    // Status
                    Item {
                        width: 110
                        height: parent.height

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingSmall
                            implicitWidth: statusRow.implicitWidth + Theme.spacingLarge
                            implicitHeight: 22
                            radius: 11
                            color: Theme.statusColor(rowDelegate.status)
                            opacity: 0.85

                            Row {
                                id: statusRow
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    text: rowDelegate.status === "read" ? "\u2714" : rowDelegate.status === "planned" ? "\u2718" : "\u25CF"
                                    color: "#000000"
                                    font.pixelSize: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: Theme.statusLabel(rowDelegate.status)
                                    color: "#000000"
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                }
                            }
                        }
                    }

                    // Pages
                    Item {
                        width: 70
                        height: parent.height

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingSmall
                            anchors.verticalCenter: parent.verticalCenter
                            text: rowDelegate.pageCount > 0 ? rowDelegate.pageCount : "—"
                            color: rowDelegate.pageCount > 0 ? Theme.textOnSurface : Theme.textSecondary
                            font.pixelSize: Theme.fontSizeMedium
                        }
                    }

                    // Author
                    Item {
                        width: 180
                        height: parent.height

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingSmall
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - Theme.spacingMedium
                            text: rowDelegate.author
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeMedium
                            elide: Text.ElideRight
                        }
                    }

                    // Rating stars
                    Item {
                        width: 120
                        height: parent.height

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingSmall
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            visible: rowDelegate.rating > 0

                            Repeater {
                                model: 6

                                Text {
                                    text: index < rowDelegate.rating ? "\u2605" : "\u2606"
                                    color: index < rowDelegate.rating ? Theme.primary : Theme.textSecondary
                                    font.pixelSize: 14
                                }
                            }
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingSmall
                            anchors.verticalCenter: parent.verticalCenter
                            text: "—"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeMedium
                            visible: rowDelegate.rating <= 0
                        }
                    }

                    // End date
                    Item {
                        width: 130
                        height: parent.height

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingSmall
                            anchors.verticalCenter: parent.verticalCenter
                            text: rowDelegate.endDate || "—"
                            color: rowDelegate.endDate ? Theme.textOnSurface : Theme.textSecondary
                            font.pixelSize: Theme.fontSizeMedium
                        }
                    }

                    // Genre
                    Item {
                        width: 120
                        height: parent.height

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingSmall
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - Theme.spacingMedium
                            text: rowDelegate.genre || "—"
                            color: rowDelegate.genre ? Theme.textOnSurface : Theme.textSecondary
                            font.pixelSize: Theme.fontSizeMedium
                            elide: Text.ElideRight
                        }
                    }

                    // Tags
                    Item {
                        width: 130
                        height: parent.height

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingSmall
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - Theme.spacingMedium
                            text: rowDelegate.tags || "—"
                            color: rowDelegate.tags ? Theme.textOnSurface : Theme.textSecondary
                            font.pixelSize: Theme.fontSizeMedium
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // Empty state
            Text {
                anchors.centerIn: parent
                visible: tableList.count === 0
                text: searchField.text ? "No books match your search" : "No books yet. Click + to add one!"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeLarge
            }
        }
    }

    function headerFillWidth() {
        var fixed = 0;
        for (var i = 0; i < columns.length; ++i) {
            if (columns[i].width > 0)
                fixed += columns[i].width;
        }
        return Math.max(150, tablePage.width - fixed - Theme.spacingMedium * 2);
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
