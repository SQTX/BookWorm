import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import BookWorm

Item {
    id: bookListPage

    signal bookSelected(int bookId)

    property int userCardsPerRow: 6  // persisted from Main.qml Settings
    property var availableYears: []

    // Context menu state
    property int contextBookId: -1
    property string contextBookStatus: ""
    property string contextBookTitle: ""
    property int contextBookPageCount: 0
    property int contextBookCurrentPage: 0

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
                text: Theme.tr("Library")
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
                        parts.push(Theme.typePlural(k) + ": " + dist[k]);
                    }
                    return parts.length > 0 ? parts.join("  \u00B7  ") : Theme.tr("0 books");
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
                placeholderText: "\u{1F50D} " + Theme.tr("Search title / author...")
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
                            { key: "Start",  value: "start" },
                            { key: "Finish", value: "finish" }
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
                                text: Theme.tr(modelData.key)
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

            // Sort ComboBox
            ComboBox {
                id: sortCombo
                Layout.preferredWidth: 160
                Layout.preferredHeight: 36
                font.pixelSize: Theme.fontSizeSmall
                Material.accent: Theme.primary

                model: ListModel {
                    id: sortModel
                    ListElement { key: "Default";       value: "default" }
                    ListElement { key: "Title A\u2192Z";    value: "title_asc" }
                    ListElement { key: "Title Z\u2192A";    value: "title_desc" }
                    ListElement { key: "Author A\u2192Z";   value: "author_asc" }
                    ListElement { key: "Author Z\u2192A";   value: "author_desc" }
                    ListElement { key: "Rating \u2193";     value: "rating_desc" }
                    ListElement { key: "Newest";        value: "date_desc" }
                    ListElement { key: "Oldest";        value: "date_asc" }
                    ListElement { key: "Pages \u2193";      value: "pages_desc" }
                }

                textRole: "key"
                valueRole: "value"

                displayText: Theme.tr(sortModel.get(currentIndex).key)

                onActivated: bookController.sortMode = currentValue
            }

            Item { Layout.fillWidth: true }

            // Status filter chips
            Row {
                spacing: Theme.spacingSmall

                Repeater {
                    model: [
                        { key: "All",       value: "" },
                        { key: "Reading",   value: "reading" },
                        { key: "Read",      value: "read" },
                        { key: "Planned",   value: "planned" },
                        { key: "Abandoned", value: "abandoned" }
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
                            text: Theme.tr(modelData.key)
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
                icon.source: "qrc:/qt/qml/BookWorm/src/img/icons/sheet-view.svg"
                icon.width: 18; icon.height: 18
                icon.color: Theme.textSecondary
                Material.background: Theme.surfaceVariant

                ToolTip.visible: hovered
                ToolTip.text: Theme.tr("Layout")

                onClicked: layoutPopup.open()
            }

            // Add book button
            RoundButton {
                width: 36; height: 36
                icon.source: "qrc:/qt/qml/BookWorm/src/img/icons/add-book.svg"
                icon.width: 18; icon.height: 18
                icon.color: Theme.textOnPrimary
                Material.background: Theme.primary
                onClicked: {
                    addDialog.mode = "add";
                    addDialog.editData = null;
                    addDialog.open();
                }
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
                    required property bool isNonFiction
                    required property string audioMode
                    required property string tags

                    BookCard {
                        id: bookCard
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
                        isNonFiction: cellDelegate.isNonFiction
                        audioMode: cellDelegate.audioMode
                        tags: cellDelegate.tags
                        onClicked: bookListPage.bookSelected(cellDelegate.bookId)
                        onRightClicked: (mx, my) => {
                            bookListPage.contextBookId = cellDelegate.bookId
                            bookListPage.contextBookStatus = cellDelegate.status
                            bookListPage.contextBookTitle = cellDelegate.title
                            bookListPage.contextBookPageCount = cellDelegate.pageCount
                            bookListPage.contextBookCurrentPage = cellDelegate.currentPage
                            var pos = bookCard.mapToItem(bookListPage, mx, my)
                            contextMenu.x = pos.x
                            contextMenu.y = pos.y
                            contextMenu.open()
                        }
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
                    text: searchField.text ? Theme.tr("No books match your search") : Theme.tr("No books yet. Click + to add one!")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeLarge
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════
    // Context Menu
    // ═══════════════════════════════════════════════════
    Menu {
        id: contextMenu

        background: Rectangle {
            implicitWidth: 200
            radius: Theme.radiusMedium
            color: Theme.surface
            border.width: 1
            border.color: Theme.divider
        }

        // ── "Start Reading" — only for planned ──
        MenuItem {
            text: Theme.tr("Start Reading")
            visible: bookListPage.contextBookStatus === "planned"
            height: visible ? implicitHeight : 0
            icon.source: "qrc:/qt/qml/BookWorm/src/img/icons/status-reading.svg"
            icon.color: Theme.statusReading
            onTriggered: {
                var data = bookController.getBookDetails(bookListPage.contextBookId);
                data["status"] = "reading";
                if (!data["startDate"])
                    data["startDate"] = new Date().toISOString().substring(0, 10);
                bookController.updateBook(data);
            }
        }

        // ── "Add Pages" — only for reading ──
        MenuItem {
            text: Theme.tr("Add Pages")
            visible: bookListPage.contextBookStatus === "reading"
            height: visible ? implicitHeight : 0
            icon.source: "qrc:/qt/qml/BookWorm/src/img/icons/book-cover.svg"
            icon.color: Theme.statusReading
            onTriggered: {
                addPagesSpinBox.to = bookListPage.contextBookPageCount;
                addPagesSpinBox.value = bookListPage.contextBookCurrentPage;
                addPagesDialog.open();
            }
        }

        // ── "Mark as Read" — only for reading ──
        MenuItem {
            text: Theme.tr("Mark as Read")
            visible: bookListPage.contextBookStatus === "reading"
            height: visible ? implicitHeight : 0
            icon.source: "qrc:/qt/qml/BookWorm/src/img/icons/status-read.svg"
            icon.color: Theme.statusRead
            onTriggered: {
                markStarRating.selectedRating = 0;
                markReviewField.text = "";
                markAsReadDialog.open();
            }
        }

        MenuSeparator {
            visible: bookListPage.contextBookStatus === "planned" || bookListPage.contextBookStatus === "reading"
            height: visible ? implicitHeight : 0
        }

        // ── "Edit" — all statuses ──
        MenuItem {
            text: Theme.tr("Edit")
            onTriggered: {
                var data = bookController.getBookDetails(bookListPage.contextBookId);
                addDialog.editData = data;
                addDialog.mode = "edit";
                addDialog.open();
            }
        }

        // ── "Delete" — all statuses ──
        MenuItem {
            text: Theme.tr("Delete")
            Material.foreground: Theme.error
            onTriggered: deleteConfirmDialog.open()
        }
    }

    // ═══════════════════════════════════════════════════
    // Delete Confirmation Dialog
    // ═══════════════════════════════════════════════════
    Dialog {
        id: deleteConfirmDialog
        title: Theme.tr("Delete Book")
        modal: true
        anchors.centerIn: parent
        width: 360
        standardButtons: Dialog.Cancel | Dialog.Yes

        Material.accent: Theme.primary

        background: Rectangle {
            radius: Theme.radiusMedium
            color: Theme.surface
            border.width: 1
            border.color: Theme.divider
        }

        Text {
            width: parent.width
            text: Theme.tr("Are you sure you want to delete") + " \"" + bookListPage.contextBookTitle + "\"?"
            color: Theme.textOnSurface
            font.pixelSize: Theme.fontSizeMedium
            wrapMode: Text.WordWrap
        }

        onAccepted: {
            bookController.deleteBook(bookListPage.contextBookId);
        }
    }

    // ═══════════════════════════════════════════════════
    // Add Pages Dialog
    // ═══════════════════════════════════════════════════
    Dialog {
        id: addPagesDialog
        title: Theme.tr("Update Progress")
        modal: true
        anchors.centerIn: parent
        width: 320
        standardButtons: Dialog.Cancel | Dialog.Ok

        Material.accent: Theme.primary

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
                text: Theme.tr("Current page") + ":"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingMedium

                SpinBox {
                    id: addPagesSpinBox
                    from: 0
                    to: 9999
                    editable: true
                    Layout.fillWidth: true
                    Material.accent: Theme.primary
                }

                Text {
                    text: "/ " + bookListPage.contextBookPageCount
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeMedium
                }
            }

            // Progress bar preview
            Rectangle {
                Layout.fillWidth: true
                height: 6
                radius: 3
                color: Theme.surfaceVariant

                Rectangle {
                    width: bookListPage.contextBookPageCount > 0
                        ? parent.width * Math.min(addPagesSpinBox.value / bookListPage.contextBookPageCount, 1.0)
                        : 0
                    height: parent.height
                    radius: 3
                    color: Theme.statusReading
                }
            }

            Text {
                text: {
                    var pct = bookListPage.contextBookPageCount > 0
                        ? Math.round((addPagesSpinBox.value / bookListPage.contextBookPageCount) * 100) : 0;
                    return pct + "%"
                }
                color: Theme.statusReading
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }
        }

        onAccepted: {
            var data = bookController.getBookDetails(bookListPage.contextBookId);
            data["currentPage"] = addPagesSpinBox.value;
            bookController.updateBook(data);
        }
    }

    // ═══════════════════════════════════════════════════
    // Mark as Read Dialog
    // ═══════════════════════════════════════════════════
    Dialog {
        id: markAsReadDialog
        title: Theme.tr("Mark as Read")
        modal: true
        anchors.centerIn: parent
        width: 380
        standardButtons: Dialog.Cancel | Dialog.Ok

        Material.accent: Theme.primary

        background: Rectangle {
            radius: Theme.radiusMedium
            color: Theme.surface
            border.width: 1
            border.color: Theme.divider
        }

        ColumnLayout {
            width: parent.width
            spacing: Theme.spacingMedium

            // Star rating
            Text {
                text: Theme.tr("Rating")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
            }

            Row {
                id: markStarRating
                property int selectedRating: 0
                readonly property var labels: ["", Theme.tr("Bad"), Theme.tr("Weak"), Theme.tr("Average"), Theme.tr("Good"), Theme.tr("Very good"), Theme.tr("Excellent")]
                Layout.alignment: Qt.AlignHCenter
                spacing: 4

                Repeater {
                    model: 6
                    Text {
                        required property int index
                        text: index < markStarRating.selectedRating ? "\u2605" : "\u2606"
                        color: index < markStarRating.selectedRating
                               ? Theme.primary : Theme.textSecondary
                        font.pixelSize: 32

                        MouseArea {
                            id: markStarMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (markStarRating.selectedRating === index + 1)
                                    markStarRating.selectedRating = 0;
                                else
                                    markStarRating.selectedRating = index + 1;
                            }
                        }

                        ToolTip.visible: markStarMouse.containsMouse
                        ToolTip.delay: 300
                        ToolTip.text: (index + 1) + " \u2014 " + markStarRating.labels[index + 1]
                    }
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: markStarRating.selectedRating > 0
                      ? markStarRating.selectedRating + " / 6 \u2014 " + markStarRating.labels[markStarRating.selectedRating]
                      : Theme.tr("Not rated")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
            }

            // Review
            Text {
                text: Theme.tr("Review")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                Layout.topMargin: Theme.spacingSmall
            }

            Rectangle {
                Layout.fillWidth: true
                height: 100
                radius: Theme.radiusSmall
                color: Theme.surfaceVariant
                border.width: 1
                border.color: Theme.divider

                Flickable {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingSmall
                    contentHeight: markReviewField.implicitHeight
                    clip: true

                    TextArea {
                        id: markReviewField
                        width: parent.width
                        placeholderText: Theme.tr("Write your review...")
                        color: Theme.textOnSurface
                        font.pixelSize: Theme.fontSizeMedium
                        wrapMode: TextArea.Wrap
                        background: null
                    }
                }
            }
        }

        onAccepted: {
            var data = bookController.getBookDetails(bookListPage.contextBookId);
            data["status"] = "read";
            data["endDate"] = new Date().toISOString().substring(0, 10);
            data["rating"] = markStarRating.selectedRating;
            data["currentPage"] = data["pageCount"];
            bookController.updateBook(data);
            if (markReviewField.text.trim())
                bookController.updateReview(bookListPage.contextBookId, markReviewField.text.trim());
        }
    }

    // ═══════════════════════════════════════════════════
    // Layout popup
    // ═══════════════════════════════════════════════════
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
                text: Theme.tr("Layout")
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
                    text: Theme.tr("Auto")
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
                            bookListPage.userCardsPerRow = 6;
                        }
                    }
                }
            }

            // Cards per row: +/- buttons
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSmall
                enabled: !autoSwitch.checked
                opacity: autoSwitch.checked ? 0.4 : 1.0

                Text {
                    text: Theme.tr("Cards per row")
                    color: Theme.textOnSurface
                    font.pixelSize: Theme.fontSizeSmall
                }

                Item { Layout.fillWidth: true }

                // Zoom out (more, smaller cards)
                Rectangle {
                    width: 32; height: 32
                    radius: Theme.radiusSmall
                    color: minusArea.containsMouse ? Theme.surfaceVariant : "transparent"
                    border.width: 1
                    border.color: Theme.divider
                    opacity: bookListPage.userCardsPerRow >= 8 ? 0.3 : 1.0

                    Text {
                        anchors.centerIn: parent
                        text: "\u2212"  // minus sign
                        color: Theme.textOnSurface
                        font.pixelSize: 18
                        font.bold: true
                    }

                    MouseArea {
                        id: minusArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (bookListPage.userCardsPerRow < 8)
                                bookListPage.userCardsPerRow += 1;
                        }
                    }
                }

                // Current value
                Text {
                    text: bookListPage.userCardsPerRow > 0 ? bookListPage.userCardsPerRow : "—"
                    color: Theme.textOnSurface
                    font.pixelSize: Theme.fontSizeMedium
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    Layout.preferredWidth: 28
                }

                // Zoom in (fewer, bigger cards)
                Rectangle {
                    width: 32; height: 32
                    radius: Theme.radiusSmall
                    color: plusArea.containsMouse ? Theme.surfaceVariant : "transparent"
                    border.width: 1
                    border.color: Theme.divider
                    opacity: bookListPage.userCardsPerRow <= 2 ? 0.3 : 1.0

                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        color: Theme.textOnSurface
                        font.pixelSize: 18
                        font.bold: true
                    }

                    MouseArea {
                        id: plusArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (bookListPage.userCardsPerRow > 2)
                                bookListPage.userCardsPerRow -= 1;
                        }
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════
    // Add/Edit book dialog
    // ═══════════════════════════════════════════════════
    BookForm {
        id: addDialog
        mode: "add"
        onAccepted: {
            if (mode === "edit")
                bookController.updateBook(bookData);
            else
                bookController.addBook(bookData);
        }
    }
}
