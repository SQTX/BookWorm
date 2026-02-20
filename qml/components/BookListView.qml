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

            // Book count
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
            spacing: Theme.spacingMedium

            // Search field
            TextField {
                id: searchField
                Layout.preferredWidth: 300
                placeholderText: "Search by title or author..."
                Material.accent: Theme.primary
                onTextChanged: bookController.searchQuery = text
            }

            Item { Layout.fillWidth: true }

            // Status filter chips
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

            // Add book button
            RoundButton {
                icon.source: "qrc:/qt/qml/WormBook/src/img/icons/add-book.svg"
                icon.width: 20; icon.height: 20
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

                delegate: BookCard {
                    width: 180
                    height: 300
                    onClicked: bookListPage.bookSelected(bookId)
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
