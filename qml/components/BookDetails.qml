import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import BookWorm

Item {
    id: detailsPage

    property int bookId: -1
    property var bookData: ({})
    property var quotes: []
    property var highlights: []

    signal back()
    signal bookDeleted()

    Component.onCompleted: loadData()

    function loadData() {
        bookData = bookController.getBookDetails(bookId);
        quotes = bookController.getQuotesForBook(bookId);
        highlights = bookController.getHighlightsForBook(bookId);
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: mainColumn.implicitHeight + Theme.spacingXL
        clip: true
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: mainColumn
            width: parent.width
            spacing: 0

            // ═══════════════════════════════════
            // Top bar
            // ═══════════════════════════════════
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Theme.spacingLarge
                spacing: Theme.spacingMedium

                Button {
                    text: "\u2190 " + Theme.tr("Back")
                    flat: true
                    Material.foreground: Theme.primary
                    onClicked: detailsPage.back()
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: Theme.tr("Edit")
                    flat: true
                    Material.foreground: Theme.secondary
                    onClicked: {
                        editDialog.editData = bookData;
                        editDialog.mode = "edit";
                        editDialog.open();
                    }
                }

                Button {
                    text: Theme.tr("Delete")
                    flat: true
                    Material.foreground: Theme.error
                    onClicked: deleteConfirm.open()
                }
            }

            // ═══════════════════════════════════
            // Main content: Cover + Info
            // ═══════════════════════════════════
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXL * 2
                Layout.rightMargin: Theme.spacingXL * 2
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

                // Info column
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

                    // Series
                    Text {
                        text: Theme.tr("Series: ") + (bookData.series || "")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeMedium
                        visible: (bookData.series || "") !== ""
                    }

                    // Meta info badges
                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMedium

                        MetaBadge {
                            text: Theme.typeLabel(bookData.itemType || "book")
                            visible: (bookData.itemType || "book") !== "book"
                        }
                        MetaBadge { text: Theme.tr("Non-fiction"); visible: bookData.isNonFiction || false }
                        MetaBadge { text: bookData.genre || ""; visible: text !== "" }
                        MetaBadge { text: bookData.language || ""; visible: text !== "" }
                        MetaBadge { text: (bookData.pageCount || 0) + " " + Theme.tr("pages"); visible: (bookData.pageCount || 0) > 0 }
                        MetaBadge { text: bookData.publisher || ""; visible: text !== "" }
                        MetaBadge { text: String(bookData.publicationYear || ""); visible: (bookData.publicationYear || 0) > 0 }
                        MetaBadge { text: "ISBN: " + (bookData.isbn || ""); visible: (bookData.isbn || "") !== "" }
                    }

                    // ── Reading progress bar (only for "reading" status) ──
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.maximumWidth: parent.width * 0.80
                        spacing: 4
                        visible: (bookData.status || "") === "reading" && (bookData.pageCount || 0) > 0

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingMedium

                            Text {
                                text: Theme.tr("Progress")
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeMedium
                                font.bold: true
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: (bookData.currentPage || 0) + " / " + (bookData.pageCount || 0) + " " + Theme.tr("pages")
                                color: Theme.textOnSurface
                                font.pixelSize: Theme.fontSizeMedium
                            }
                            Text {
                                property real pct: (bookData.pageCount || 0) > 0
                                    ? Math.round(((bookData.currentPage || 0) / (bookData.pageCount || 1)) * 100)
                                    : 0
                                text: pct + "%"
                                color: Theme.primary
                                font.pixelSize: Theme.fontSizeMedium
                                font.bold: true
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 8
                            radius: 4
                            color: Theme.surfaceVariant

                            Rectangle {
                                width: parent.width * Math.min(1.0,
                                    (bookData.pageCount || 0) > 0
                                        ? (bookData.currentPage || 0) / (bookData.pageCount || 1)
                                        : 0)
                                height: parent.height
                                radius: 4
                                color: Theme.statusReading
                            }
                        }
                    }

                    // ── Star rating (only for "read" status) ──
                    ColumnLayout {
                        spacing: 4
                        visible: (bookData.status || "") === "read"

                        Row {
                            spacing: 4

                            Repeater {
                                model: 6
                                Text {
                                    required property int index
                                    text: index < (bookData.rating || 0) ? "\u2605" : "\u2606"
                                    color: index < (bookData.rating || 0) ? Theme.primary : Theme.textSecondary
                                    font.pixelSize: 26
                                }
                            }

                            Text {
                                text: {
                                    var labels = ["", Theme.tr("Bad"), Theme.tr("Weak"), Theme.tr("Average"), Theme.tr("Good"), Theme.tr("Very good"), Theme.tr("Excellent")];
                                    var r = bookData.rating || 0;
                                    return r > 0 ? "  " + r + "/6 — " + labels[r] : "  " + Theme.tr("Not rated");
                                }
                                color: Theme.textOnSurface
                                font.pixelSize: Theme.fontSizeMedium
                                anchors.verticalCenter: parent.verticalCenter
                            }
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
                            text: Theme.tr("Started") + ": " + (bookData.startDate || "\u2014")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeMedium
                            visible: (bookData.startDate || "") !== ""
                        }
                        Text {
                            text: Theme.tr("Finished") + ": " + (bookData.endDate || "\u2014")
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

            // ═══════════════════════════════════
            // Review section (only for "read" books)
            // ═══════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXL * 2
                Layout.rightMargin: Theme.spacingXL * 2
                Layout.topMargin: Theme.spacingXL
                Layout.bottomMargin: 0
                implicitHeight: reviewCol.implicitHeight + Theme.spacingLarge * 2
                radius: Theme.radiusMedium
                color: Theme.surface
                visible: (bookData.status || "") === "read"

                ColumnLayout {
                    id: reviewCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    Text {
                        text: Theme.tr("MY REVIEW")
                        color: Theme.primary
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                    }

                    TextArea {
                        id: reviewArea
                        Layout.fillWidth: true
                        Layout.minimumHeight: 60
                        text: bookData.review || ""
                        placeholderText: Theme.tr("Write your review...")
                        wrapMode: TextArea.Wrap
                        font.pixelSize: Theme.fontSizeMedium
                        Material.accent: Theme.primary
                        onEditingFinished: {
                            bookController.updateReview(detailsPage.bookId, text);
                        }
                    }

                    Button {
                        text: Theme.tr("Save Review")
                        Layout.alignment: Qt.AlignRight
                        Material.background: Theme.primary
                        Material.foreground: Theme.textOnPrimary
                        font.pixelSize: Theme.fontSizeSmall
                        onClicked: {
                            bookController.updateReview(detailsPage.bookId, reviewArea.text);
                        }
                    }
                }
            }

            // ═══════════════════════════════════
            // Notes section
            // ═══════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXL * 2
                Layout.rightMargin: Theme.spacingXL * 2
                Layout.topMargin: Theme.spacingLarge
                implicitHeight: notesContent.implicitHeight + Theme.spacingLarge * 2
                radius: Theme.radiusMedium
                color: Theme.surface
                visible: (bookData.notes || "") !== ""

                ColumnLayout {
                    id: notesContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    Text {
                        text: Theme.tr("NOTES")
                        color: Theme.primary
                        font.pixelSize: Theme.fontSizeSmall
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

            // ═══════════════════════════════════
            // Quotes section
            // ═══════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXL * 2
                Layout.rightMargin: Theme.spacingXL * 2
                Layout.topMargin: Theme.spacingLarge
                implicitHeight: quotesColumn.implicitHeight + Theme.spacingLarge * 2
                radius: Theme.radiusMedium
                color: Theme.surface

                ColumnLayout {
                    id: quotesColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: Theme.tr("FAVORITE QUOTES")
                            color: Theme.primary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }

                        Item { Layout.fillWidth: true }

                        Button {
                            text: Theme.tr("+ Add Quote")
                            flat: true
                            Material.foreground: Theme.primary
                            font.pixelSize: Theme.fontSizeSmall
                            onClicked: addQuoteDialog.open()
                        }
                    }

                    Repeater {
                        model: detailsPage.quotes

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: quoteRow.implicitHeight + Theme.spacingMedium
                            radius: Theme.radiusSmall
                            color: Theme.surfaceVariant

                            RowLayout {
                                id: quoteRow
                                anchors.fill: parent
                                anchors.margins: Theme.spacingMedium
                                spacing: Theme.spacingMedium

                                Text {
                                    Layout.fillWidth: true
                                    text: "\u201C" + modelData.quote + "\u201D" +
                                          (modelData.page > 0 ? "  \u2014 p. " + modelData.page : "")
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
                    }

                    Text {
                        visible: detailsPage.quotes.length === 0
                        text: Theme.tr("No quotes yet")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeMedium
                        font.italic: true
                    }
                }
            }

            // ═══════════════════════════════════
            // Highlights section
            // ═══════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXL * 2
                Layout.rightMargin: Theme.spacingXL * 2
                Layout.topMargin: Theme.spacingLarge
                implicitHeight: highlightsCol.implicitHeight + Theme.spacingLarge * 2
                radius: Theme.radiusMedium
                color: Theme.surface

                ColumnLayout {
                    id: highlightsCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: Theme.tr("HIGHLIGHTS")
                            color: Theme.primary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }

                        Item { Layout.fillWidth: true }

                        Button {
                            text: Theme.tr("+ Add Highlight")
                            flat: true
                            Material.foreground: Theme.primary
                            font.pixelSize: Theme.fontSizeSmall
                            onClicked: addHighlightDialog.open()
                        }
                    }

                    Repeater {
                        model: detailsPage.highlights

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: hlCol.implicitHeight + Theme.spacingMedium
                            radius: Theme.radiusSmall
                            color: Theme.surfaceVariant

                            ColumnLayout {
                                id: hlCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.spacingMedium
                                spacing: 4

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingMedium

                                    Text {
                                        text: modelData.title
                                        color: Theme.textOnSurface
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.bold: true
                                        Layout.fillWidth: true
                                        wrapMode: Text.Wrap
                                    }

                                    Text {
                                        text: modelData.page > 0 ? "p. " + modelData.page : ""
                                        color: Theme.textSecondary
                                        font.pixelSize: Theme.fontSizeSmall
                                        visible: modelData.page > 0
                                    }

                                    ToolButton {
                                        text: "\u2715"
                                        font.pixelSize: 12
                                        Material.foreground: Theme.error
                                        onClicked: {
                                            bookController.removeHighlight(modelData.id);
                                            detailsPage.highlights = bookController.getHighlightsForBook(bookId);
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.note || ""
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                    wrapMode: Text.Wrap
                                    visible: (modelData.note || "") !== ""
                                }
                            }
                        }
                    }

                    Text {
                        visible: detailsPage.highlights.length === 0
                        text: Theme.tr("No highlights yet")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeMedium
                        font.italic: true
                    }
                }
            }

            // ═══════════════════════════════════
            // Summary (collapsible)
            // ═══════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXL * 2
                Layout.rightMargin: Theme.spacingXL * 2
                Layout.topMargin: Theme.spacingLarge
                implicitHeight: summaryCol.implicitHeight + Theme.spacingLarge * 2
                radius: Theme.radiusMedium
                color: Theme.surface

                property bool expanded: false

                ColumnLayout {
                    id: summaryCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: Theme.tr("SUMMARY")
                            color: Theme.primary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }

                        Text {
                            text: (bookData.summary || "") !== "" ? "" : Theme.tr("(empty)")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.italic: true
                        }

                        Item { Layout.fillWidth: true }

                        Button {
                            text: parent.parent.parent.parent.expanded ? "\u25B2 " + Theme.tr("Collapse") : "\u25BC " + Theme.tr("Expand")
                            flat: true
                            Material.foreground: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            onClicked: parent.parent.parent.parent.expanded = !parent.parent.parent.parent.expanded
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMedium
                        visible: parent.parent.expanded

                        TextArea {
                            id: summaryArea
                            Layout.fillWidth: true
                            Layout.minimumHeight: 80
                            text: bookData.summary || ""
                            placeholderText: Theme.tr("Write a brief summary of the book...")
                            wrapMode: TextArea.Wrap
                            font.pixelSize: Theme.fontSizeMedium
                            Material.accent: Theme.primary
                        }

                        Button {
                            text: Theme.tr("Save Summary")
                            Layout.alignment: Qt.AlignRight
                            Material.background: Theme.primary
                            Material.foreground: Theme.textOnPrimary
                            font.pixelSize: Theme.fontSizeSmall
                            onClicked: {
                                bookController.updateSummary(detailsPage.bookId, summaryArea.text);
                            }
                        }
                    }
                }
            }

            // Bottom spacer
            Item { Layout.preferredHeight: Theme.spacingXL }
        }
    }

    // ── Meta badge helper ──
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

    // ── Edit dialog ──
    BookForm {
        id: editDialog
        mode: "edit"
        onAccepted: {
            bookController.updateBook(bookData);
            detailsPage.loadData();
        }
    }

    // ── Delete confirmation ──
    Dialog {
        id: deleteConfirm
        title: Theme.tr("Delete Book")
        modal: true
        standardButtons: Dialog.Yes | Dialog.No
        anchors.centerIn: parent
        Material.theme: Theme.isDark ? Material.Dark : Material.Light
        Material.accent: Theme.primary

        Label {
            text: Theme.tr("Are you sure you want to delete") + " \"" + (bookData.title || "") + "\"?"
            wrapMode: Text.Wrap
        }

        onAccepted: {
            bookController.deleteBook(bookId);
            detailsPage.bookDeleted();
        }
    }

    // ── Add Quote dialog (fixed layout) ──
    Dialog {
        id: addQuoteDialog
        title: ""
        modal: true
        standardButtons: Dialog.NoButton
        anchors.centerIn: parent
        width: Math.min(520, parent.width - 48)
        padding: 0

        Material.theme: Theme.isDark ? Material.Dark : Material.Light
        Material.accent: Theme.primary

        background: Rectangle {
            radius: Theme.radiusLarge
            color: Theme.surface
            border.width: 1
            border.color: Theme.divider
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Header
            Text {
                Layout.topMargin: Theme.spacingLarge
                Layout.leftMargin: Theme.spacingXL
                text: Theme.tr("Add Quote")
                color: Theme.textOnSurface
                font.pixelSize: Theme.fontSizeTitle
                font.bold: true
            }

            Rectangle { Layout.fillWidth: true; Layout.topMargin: Theme.spacingMedium; height: 1; color: Theme.divider }

            // Content
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: Theme.spacingXL
                spacing: Theme.spacingLarge

                Text {
                    text: Theme.tr("Quote text")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                }

                TextArea {
                    id: quoteTextField
                    Layout.fillWidth: true
                    Layout.minimumHeight: 80
                    Layout.maximumHeight: 160
                    placeholderText: Theme.tr("Enter quote...")
                    wrapMode: TextArea.Wrap
                    font.pixelSize: Theme.fontSizeMedium
                    Material.accent: Theme.primary
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingLarge

                    Text {
                        text: Theme.tr("Page:")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeMedium
                    }

                    SpinBox {
                        id: quotePageField
                        from: 0; to: 99999
                        editable: true
                        value: 0
                        Layout.preferredWidth: 140
                        Material.accent: Theme.primary
                    }

                    Text {
                        text: Theme.tr("(0 = no page)")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                        font.italic: true
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.divider }

            // Footer
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Theme.spacingLarge
                spacing: Theme.spacingMedium

                Item { Layout.fillWidth: true }

                Button {
                    text: Theme.tr("Cancel")
                    flat: true
                    Material.foreground: Theme.textSecondary
                    onClicked: addQuoteDialog.reject()
                }

                Button {
                    text: Theme.tr("Add")
                    enabled: quoteTextField.text.trim() !== ""
                    Material.background: enabled ? Theme.primary : Theme.surfaceVariant
                    Material.foreground: enabled ? Theme.textOnPrimary : Theme.textSecondary
                    onClicked: {
                        bookController.addQuote(bookId, quoteTextField.text.trim(), quotePageField.value);
                        detailsPage.quotes = bookController.getQuotesForBook(bookId);
                        quoteTextField.text = "";
                        quotePageField.value = 0;
                        addQuoteDialog.close();
                    }
                }
            }
        }
    }

    // ── Add Highlight dialog ──
    Dialog {
        id: addHighlightDialog
        title: ""
        modal: true
        standardButtons: Dialog.NoButton
        anchors.centerIn: parent
        width: Math.min(520, parent.width - 48)
        padding: 0

        Material.theme: Theme.isDark ? Material.Dark : Material.Light
        Material.accent: Theme.primary

        background: Rectangle {
            radius: Theme.radiusLarge
            color: Theme.surface
            border.width: 1
            border.color: Theme.divider
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Header
            Text {
                Layout.topMargin: Theme.spacingLarge
                Layout.leftMargin: Theme.spacingXL
                text: Theme.tr("Add Highlight")
                color: Theme.textOnSurface
                font.pixelSize: Theme.fontSizeTitle
                font.bold: true
            }

            Rectangle { Layout.fillWidth: true; Layout.topMargin: Theme.spacingMedium; height: 1; color: Theme.divider }

            // Content
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: Theme.spacingXL
                spacing: Theme.spacingLarge

                Text {
                    text: Theme.tr("Title") + " *"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                }

                TextField {
                    id: hlTitleField
                    Layout.fillWidth: true
                    placeholderText: Theme.tr("Highlight name...")
                    font.pixelSize: Theme.fontSizeMedium
                    Material.accent: Theme.primary
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingLarge

                    Text {
                        text: Theme.tr("Page:")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeMedium
                    }

                    SpinBox {
                        id: hlPageField
                        from: 0; to: 99999
                        editable: true
                        value: 0
                        Layout.preferredWidth: 140
                        Material.accent: Theme.primary
                    }
                }

                Text {
                    text: Theme.tr("Note")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                }

                TextArea {
                    id: hlNoteField
                    Layout.fillWidth: true
                    Layout.minimumHeight: 60
                    Layout.maximumHeight: 120
                    placeholderText: Theme.tr("Important info...")
                    wrapMode: TextArea.Wrap
                    font.pixelSize: Theme.fontSizeMedium
                    Material.accent: Theme.primary
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.divider }

            // Footer
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Theme.spacingLarge
                spacing: Theme.spacingMedium

                Item { Layout.fillWidth: true }

                Button {
                    text: Theme.tr("Cancel")
                    flat: true
                    Material.foreground: Theme.textSecondary
                    onClicked: addHighlightDialog.reject()
                }

                Button {
                    text: Theme.tr("Add")
                    enabled: hlTitleField.text.trim() !== ""
                    Material.background: enabled ? Theme.primary : Theme.surfaceVariant
                    Material.foreground: enabled ? Theme.textOnPrimary : Theme.textSecondary
                    onClicked: {
                        bookController.addHighlight(bookId, hlTitleField.text.trim(),
                            hlPageField.value, hlNoteField.text.trim());
                        detailsPage.highlights = bookController.getHighlightsForBook(bookId);
                        hlTitleField.text = "";
                        hlPageField.value = 0;
                        hlNoteField.text = "";
                        addHighlightDialog.close();
                    }
                }
            }
        }
    }
}
