import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import WormBook

Item {
    id: detailsPage

    property int bookId: -1
    property var bookData: ({})
    property var quotes: []

    signal back()
    signal bookDeleted()

    Component.onCompleted: loadData()

    function loadData() {
        bookData = bookController.getBookDetails(bookId);
        quotes = bookController.getQuotesForBook(bookId);
    }

    ScrollView {
        anchors.fill: parent
        clip: true

        ColumnLayout {
            width: detailsPage.width
            spacing: 0

            // Top bar
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Theme.spacingLarge
                spacing: Theme.spacingMedium

                Button {
                    text: "\u2190 Back"
                    flat: true
                    Material.foreground: Theme.primary
                    onClicked: detailsPage.back()
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: "Edit"
                    flat: true
                    Material.foreground: Theme.secondary
                    onClicked: {
                        editDialog.editData = bookData;
                        editDialog.mode = "edit";
                        editDialog.open();
                    }
                }

                Button {
                    text: "Delete"
                    flat: true
                    Material.foreground: Theme.error
                    onClicked: deleteConfirm.open()
                }
            }

            // Main content
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXL
                Layout.rightMargin: Theme.spacingXL
                spacing: Theme.spacingXL

                // Cover
                Rectangle {
                    Layout.preferredWidth: 200
                    Layout.preferredHeight: 300
                    radius: Theme.radiusMedium
                    color: Theme.surfaceVariant

                    Image {
                        anchors.fill: parent
                        source: bookData.coverImagePath ? "file://" + bookData.coverImagePath : ""
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                        clip: true
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "\u{1F4D6}"
                        font.pixelSize: 72
                        visible: !bookData.coverImagePath
                        opacity: 0.4
                    }
                }

                // Info
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingMedium

                    // Title
                    Text {
                        text: bookData.title || ""
                        color: Theme.textOnSurface
                        font.pixelSize: Theme.fontSizeTitle
                        font.bold: true
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    // Author
                    Text {
                        text: bookData.author || ""
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeLarge
                    }

                    // Meta info row
                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMedium

                        MetaBadge {
                            text: {
                                var t = bookData.itemType || "book";
                                return t.charAt(0).toUpperCase() + t.slice(1);
                            }
                            visible: (bookData.itemType || "book") !== "book"
                        }
                        MetaBadge { text: "Non-fiction"; visible: bookData.isNonFiction || false }
                        MetaBadge { text: bookData.genre || ""; visible: text !== "" }
                        MetaBadge { text: bookData.language || ""; visible: text !== "" }
                        MetaBadge { text: (bookData.pageCount || 0) + " pages"; visible: (bookData.pageCount || 0) > 0 }
                        MetaBadge { text: bookData.publisher || ""; visible: text !== "" }
                        MetaBadge { text: String(bookData.publicationYear || ""); visible: (bookData.publicationYear || 0) > 0 }
                        MetaBadge { text: "ISBN: " + (bookData.isbn || ""); visible: (bookData.isbn || "") !== "" }
                    }

                    // Rating
                    Row {
                        spacing: 4
                        visible: (bookData.rating || 0) > 0

                        Repeater {
                            model: 6
                            Text {
                                text: index < (bookData.rating || 0) ? "\u2605" : "\u2606"
                                color: index < (bookData.rating || 0) ? Theme.primary : Theme.textSecondary
                                font.pixelSize: 22
                            }
                        }

                        Text {
                            text: " " + (bookData.rating || 0) + "/6"
                            color: Theme.textOnSurface
                            font.pixelSize: Theme.fontSizeMedium
                        }
                    }

                    // Status badge
                    Rectangle {
                        implicitWidth: statusText.implicitWidth + Theme.spacingXL
                        implicitHeight: 28
                        radius: 14
                        color: Theme.statusColor(bookData.status || "planned")

                        Text {
                            id: statusText
                            anchors.centerIn: parent
                            text: Theme.statusLabel(bookData.status || "planned")
                            color: "#000000"
                            font.pixelSize: Theme.fontSizeMedium
                            font.bold: true
                        }
                    }

                    // Dates
                    RowLayout {
                        spacing: Theme.spacingLarge
                        visible: (bookData.startDate || "") !== "" || (bookData.endDate || "") !== ""

                        Text {
                            text: "Started: " + (bookData.startDate || "—")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeMedium
                            visible: (bookData.startDate || "") !== ""
                        }
                        Text {
                            text: "Finished: " + (bookData.endDate || "—")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeMedium
                            visible: (bookData.endDate || "") !== ""
                        }
                    }

                    // Tags
                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall
                        visible: (bookData.tags || "") !== ""

                        Repeater {
                            model: (bookData.tags || "").split(", ").filter(function(t) { return t !== ""; })

                            Rectangle {
                                implicitWidth: tagText.implicitWidth + Theme.spacingLarge
                                implicitHeight: 24
                                radius: 12
                                color: Theme.primaryVariant

                                Text {
                                    id: tagText
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: Theme.textOnSurface
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }
                        }
                    }
                }
            }

            // Notes section
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: Theme.spacingXL
                Layout.preferredHeight: notesContent.implicitHeight + Theme.spacingXL * 2
                radius: Theme.radiusMedium
                color: Theme.surface
                visible: (bookData.notes || "") !== ""

                ColumnLayout {
                    id: notesContent
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    Text {
                        text: "Notes"
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeMedium
                        font.bold: true
                    }

                    Text {
                        Layout.fillWidth: true
                        text: bookData.notes || ""
                        color: Theme.textOnSurface
                        font.pixelSize: Theme.fontSizeMedium
                        wrapMode: Text.Wrap
                    }
                }
            }

            // Quotes section
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: Theme.spacingXL
                Layout.preferredHeight: quotesColumn.implicitHeight + Theme.spacingXL * 2
                radius: Theme.radiusMedium
                color: Theme.surface

                ColumnLayout {
                    id: quotesColumn
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "Favorite Quotes"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeMedium
                            font.bold: true
                        }

                        Item { Layout.fillWidth: true }

                        Button {
                            text: "+ Add Quote"
                            flat: true
                            Material.foreground: Theme.primary
                            font.pixelSize: Theme.fontSizeSmall
                            onClicked: addQuoteDialog.open()
                        }
                    }

                    // Quote list
                    Repeater {
                        model: detailsPage.quotes

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingMedium

                            Text {
                                Layout.fillWidth: true
                                text: "\u201C" + modelData.quote + "\u201D" +
                                      (modelData.page > 0 ? " (p. " + modelData.page + ")" : "")
                                color: Theme.textOnSurface
                                font.pixelSize: Theme.fontSizeMedium
                                font.italic: true
                                wrapMode: Text.Wrap
                            }

                            ToolButton {
                                text: "\u2715"
                                font.pixelSize: 12
                                Material.foreground: Theme.error
                                onClicked: {
                                    bookController.removeQuote(modelData.id);
                                    detailsPage.quotes = bookController.getQuotesForBook(bookId);
                                }
                            }
                        }
                    }

                    // Empty state
                    Text {
                        visible: detailsPage.quotes.length === 0
                        text: "No quotes yet"
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeMedium
                        font.italic: true
                    }
                }
            }

            // Bottom spacer
            Item { Layout.preferredHeight: Theme.spacingXL }
        }
    }

    // Meta badge helper
    component MetaBadge: Rectangle {
        property alias text: badgeText.text
        implicitWidth: badgeText.implicitWidth + Theme.spacingLarge
        implicitHeight: 24
        radius: Theme.radiusSmall
        color: Theme.surfaceVariant

        Text {
            id: badgeText
            anchors.centerIn: parent
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    // Edit dialog
    BookForm {
        id: editDialog
        mode: "edit"
        onAccepted: {
            bookController.updateBook(bookData);
            detailsPage.loadData();
        }
    }

    // Delete confirmation
    Dialog {
        id: deleteConfirm
        title: "Delete Book"
        modal: true
        standardButtons: Dialog.Yes | Dialog.No
        anchors.centerIn: parent
        Material.theme: Material.Dark

        Label {
            text: "Are you sure you want to delete \"" + (bookData.title || "") + "\"?"
            wrapMode: Text.Wrap
        }

        onAccepted: {
            bookController.deleteBook(bookId);
            detailsPage.bookDeleted();
        }
    }

    // Add quote dialog
    Dialog {
        id: addQuoteDialog
        title: "Add Quote"
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        anchors.centerIn: parent
        width: 450
        Material.theme: Material.Dark
        Material.accent: Theme.primary

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.spacingMedium

            TextArea {
                id: quoteTextField
                Layout.fillWidth: true
                Layout.preferredHeight: 100
                placeholderText: "Enter quote..."
                wrapMode: TextArea.Wrap
            }

            SpinBox {
                id: quotePageField
                from: 0; to: 99999
                editable: true
                value: 0

                Label {
                    text: "Page (0 = none):"
                    anchors.right: parent.left
                    anchors.rightMargin: Theme.spacingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.textSecondary
                }
            }
        }

        onAccepted: {
            if (quoteTextField.text.trim() !== "") {
                bookController.addQuote(bookId, quoteTextField.text, quotePageField.value);
                detailsPage.quotes = bookController.getQuotesForBook(bookId);
                quoteTextField.text = "";
                quotePageField.value = 0;
            }
        }
    }
}
