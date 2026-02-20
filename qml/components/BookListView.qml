import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import WormBook

Item {
    id: bookListPage

    signal bookSelected(int bookId)

    property int userCardsPerRow: 0  // 0 = auto
    property var availableYears: []

    Component.onCompleted: {
        availableYears = bookController.getAvailableYears();
    }

    Connections {
        target: bookController
        function onBooksChanged() {
            bookListPage.availableYears = bookController.getAvailableYears();
        }
    }

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

            // Year filter ComboBox
            ComboBox {
                id: yearCombo
                Layout.preferredWidth: 90
                Layout.preferredHeight: 36
                font.pixelSize: Theme.fontSizeSmall
                Material.accent: Theme.primary

                model: {
                    var items = ["All"];
                    var years = bookListPage.availableYears;
                    for (var i = 0; i < years.length; i++)
                        items.push(String(years[i]));
                    return items;
                }

                onCurrentTextChanged: {
                    if (currentText === "All")
                        bookController.filterYear = 0;
                    else
                        bookController.filterYear = parseInt(currentText);
                }
            }

            // Start/Finish toggle
            Rectangle {
                Layout.preferredHeight: 28
                implicitWidth: modeRow.implicitWidth + Theme.spacingMedium * 2
                radius: 14
                color: Theme.surfaceVariant
                visible: yearCombo.currentText !== "All"

                RowLayout {
                    id: modeRow
                    anchors.centerIn: parent
                    spacing: 2

                    Repeater {
                        model: [
                            { label: "Start",  value: "start" },
                            { label: "Finish", value: "finish" }
                        ]

                        Rectangle {
                            required property var modelData
                            required property int index
                            width: modeLabel.implicitWidth + Theme.spacingMedium
                            height: 24
                            radius: 12
                            color: bookController.filterYearMode === modelData.value
                                   ? Theme.primary : "transparent"

                            Text {
                                id: modeLabel
                                anchors.centerIn: parent
                                text: modelData.label
                                color: bookController.filterYearMode === modelData.value
                                       ? Theme.textOnPrimary : Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall - 1
                                font.bold: bookController.filterYearMode === modelData.value
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: bookController.filterYearMode = modelData.value
                            }
                        }
                    }
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

            // Layout button
            RoundButton {
                width: 36; height: 36
                icon.source: "qrc:/qt/qml/WormBook/src/img/icons/sheet-view.svg"
                icon.width: 18; icon.height: 18
                icon.color: Theme.textSecondary
                Material.background: Theme.surfaceVariant

                ToolTip.visible: hovered
                ToolTip.text: "Layout"

                onClicked: layoutPopup.open()
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

                cellWidth: {
                    if (bookListPage.userCardsPerRow > 0) {
                        return Math.floor(width / bookListPage.userCardsPerRow);
                    }
                    // Auto: fit as many ~196px cards as possible
                    var cols = Math.max(1, Math.floor(width / 196));
                    return Math.floor(width / cols);
                }
                cellHeight: cellWidth * (316 / 196)

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
                        width: gridView.cellWidth - 16
                        height: gridView.cellHeight - 16
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

    // Layout popup
    Popup {
        id: layoutPopup
        x: parent.width - width - Theme.spacingXL
        y: 100
        width: 220
        padding: Theme.spacingMedium
        modal: true

        background: Rectangle {
            radius: Theme.radiusMedium
            color: Theme.surface
            border.width: 1
            border.color: Theme.divider
        }

        ColumnLayout {
            width: parent.width
            spacing: Theme.spacingMedium

            Text {
                text: "Layout"
                color: Theme.textOnSurface
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.divider }

            // Auto switch
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingMedium

                Text {
                    Layout.fillWidth: true
                    text: "Auto"
                    color: Theme.textOnSurface
                    font.pixelSize: Theme.fontSizeMedium
                }

                Switch {
                    id: autoSwitch
                    checked: bookListPage.userCardsPerRow === 0
                    Material.accent: Theme.primary
                    onToggled: {
                        if (checked) {
                            bookListPage.userCardsPerRow = 0;
                        } else {
                            bookListPage.userCardsPerRow = cardsSpinBox.value;
                        }
                    }
                }
            }

            // Cards per row
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingMedium
                enabled: !autoSwitch.checked
                opacity: autoSwitch.checked ? 0.4 : 1.0

                Text {
                    text: "Cards per row"
                    color: Theme.textOnSurface
                    font.pixelSize: Theme.fontSizeSmall
                }

                Item { Layout.fillWidth: true }

                SpinBox {
                    id: cardsSpinBox
                    from: 2; to: 8
                    value: 4
                    editable: true
                    Material.accent: Theme.primary
                    Layout.preferredWidth: 100

                    onValueChanged: {
                        if (!autoSwitch.checked) {
                            bookListPage.userCardsPerRow = value;
                        }
                    }
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
