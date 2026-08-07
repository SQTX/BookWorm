import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import BookWorm

Item {
    id: bookListPage

    signal bookSelected(int bookId)

    property int userCardsPerRow: 6  // persisted from Main.qml Settings
    property bool priorityEnabled: true  // persisted from Main.qml Settings
    property var availableYears: []

    // Context menu state
    property int contextBookId: -1
    property string contextBookStatus: ""
    property string contextBookTitle: ""
    property int contextBookPageCount: 0
    property int contextBookCurrentPage: 0
    property bool contextBookIsPriority: false

    onPriorityEnabledChanged: bookController.priorityEnabled = priorityEnabled

    // Shared by both grids so the card layout stays identical in each.
    function cellWidthFor(gridWidth) {
        if (bookListPage.userCardsPerRow > 0)
            return Math.floor(gridWidth / bookListPage.userCardsPerRow);

        // Auto: pick the column count whose resulting cell width lands closest to
        // 210px. Dividing by a fixed 196 and flooring used to leave the remainder
        // on the cells, so a wide window blew every card up to 260px+ and the grid
        // read as four posters rather than a library.
        var target = 210;
        var cols = Math.max(1, Math.round(gridWidth / target));
        if (gridWidth / cols > 260)
            cols += 1;
        return Math.floor(gridWidth / cols);
    }

    Component {
        id: bookCellDelegate

        Item {
            id: cellDelegate
            width: GridView.view.cellWidth
            height: GridView.view.cellHeight

            readonly property var ownerGrid: GridView.view

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
            required property bool isPriority
            required property string audioMode
            required property string tags
            required property int readCount

            BookCard {
                id: bookCard
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 8
                width: cellDelegate.width - 16
                height: cellDelegate.height - 16
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
                isPriority: cellDelegate.isPriority
                audioMode: cellDelegate.audioMode
                tags: cellDelegate.tags
                readCount: cellDelegate.readCount
                onClicked: bookListPage.bookSelected(cellDelegate.bookId)
                onRightClicked: (mx, my) => {
                    bookListPage.contextBookId = cellDelegate.bookId
                    bookListPage.contextBookStatus = cellDelegate.status
                    bookListPage.contextBookTitle = cellDelegate.title
                    bookListPage.contextBookPageCount = cellDelegate.pageCount
                    bookListPage.contextBookCurrentPage = cellDelegate.currentPage
                    bookListPage.contextBookIsPriority = cellDelegate.isPriority
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
                width: cellDelegate.ownerGrid ? cellDelegate.ownerGrid.width : 0
                height: 1
                color: Theme.divider
                opacity: 0.3
                visible: cellDelegate.x < cellDelegate.width
            }
        }
    }

    // One labelled status section in the Library grid (Reading / Planned / …).
    // Mirrors the Priority section: a coloured header, its own non-interactive
    // GridView, and a closing separator. Collapses to nothing when empty.
    component StatusSection: Column {
        id: section
        property var sectionModel: null
        property string label: ""
        property color accent: Theme.primary
        property real gridOpacity: 1.0

        width: parent ? parent.width : 0
        visible: sectionModel && sectionModel.count > 0
        height: visible ? implicitHeight : 0
        spacing: 0

        Item {
            width: parent.width
            height: sectionLabel.implicitHeight + Theme.spacingMedium

            SectionLabel {
                id: sectionLabel
                anchors.left: parent.left
                anchors.top: parent.top
                text: section.label
                accent: section.accent
            }

            // The count sits opposite the label so each section states its size
            // without a second row of chrome.
            Text {
                anchors.right: parent.right
                anchors.baseline: sectionLabel.baseline
                text: section.sectionModel ? section.sectionModel.count : 0
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        GridView {
            width: parent.width
            height: contentHeight
            interactive: false
            opacity: section.gridOpacity
            cellWidth: bookListPage.cellWidthFor(width)
            cellHeight: cellWidth * (316 / 196)
            model: section.sectionModel
            delegate: bookCellDelegate
        }

        Rectangle {
            width: parent.width
            height: 1
            color: section.accent
            opacity: 0.4
        }

        Item { width: parent.width; height: Theme.spacingMedium }
    }

    Component.onCompleted: {
        availableYears = bookController.getAvailableYears();
        bookController.priorityEnabled = priorityEnabled;
    }

    Connections {
        target: bookController
        function onBooksChanged() {
            bookListPage.availableYears = bookController.getAvailableYears();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pageMargin
        spacing: Theme.sectionGap

        // Header
        PageHeader {
            Layout.fillWidth: true
            title: Theme.tr("Library")
            subtitle: {
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

            // Layout button
            IconButton {
                iconSource: "qrc:/qt/qml/BookWorm/src/img/icons/sheet-view.svg"
                tooltip: Theme.tr("Layout")
                onClicked: layoutPopup.open()
            }

            // Add book — the primary action on this page, so it gets a label
            // rather than a 34px icon circle sitting next to an identical one.
            AppButton {
                variant: "primary"
                iconSource: "qrc:/qt/qml/BookWorm/src/img/icons/add-book.svg"
                text: Theme.tr("Add Book")
                onClicked: {
                    addDialog.mode = "add";
                    addDialog.editData = null;
                    addDialog.open();
                }
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
                Layout.preferredHeight: Theme.controlHeight
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
                Layout.preferredHeight: Theme.controlHeight
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

            // Start/Finish toggle — a segmented control, so it stays one object
            // rather than two loose chips.
            Rectangle {
                Layout.preferredHeight: Theme.chipHeight
                implicitWidth: modeRow.implicitWidth + Theme.spacingMedium
                radius: height / 2
                color: Theme.surfaceVariant
                border.width: 1
                border.color: Theme.outline
                visible: yearCombo.currentText !== "All"

                Row {
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

                            readonly property bool isSelected: bookController.filterYearMode === modelData.value

                            width: modeLabel.implicitWidth + Theme.spacingLarge
                            height: 22
                            radius: 11
                            color: isSelected ? Theme.primary
                                              : (modeMouse.containsMouse ? Theme.hover : "transparent")

                            Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                            Text {
                                id: modeLabel
                                anchors.centerIn: parent
                                text: Theme.tr(modelData.key)
                                color: parent.isSelected ? Theme.textOnPrimary : Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall - 1
                                font.bold: parent.isSelected
                            }

                            MouseArea {
                                id: modeMouse
                                anchors.fill: parent
                                hoverEnabled: true
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
                Layout.preferredHeight: Theme.controlHeight
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

            // Status filter chips — each carries its own status colour when active,
            // so the filter row echoes the section headers below it.
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

                    Chip {
                        required property var modelData
                        text: Theme.tr(modelData.key)
                        selected: bookController.filterStatus === modelData.value
                        accent: modelData.value === "" ? Theme.primary
                                                       : Theme.statusColor(modelData.value)
                        onClicked: bookController.filterStatus = modelData.value
                    }
                }
            }
        }

        // Book grid — priority section on top, then the rest.
        // Flickable + ScrollBar directly (nesting a Flickable in a ScrollView double-scrolls).
        Flickable {
            id: gridFlickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: gridColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar { }

            Column {
                id: gridColumn
                width: gridFlickable.width

                // ── Priority section ──
                Item {
                    width: parent.width
                    height: visible ? priorityLabel.implicitHeight + Theme.spacingMedium : 0
                    visible: bookController.priorityModel.count > 0

                    SectionLabel {
                        id: priorityLabel
                        anchors.left: parent.left
                        anchors.top: parent.top
                        text: Theme.tr("Priority")
                        accent: Theme.priority
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.baseline: priorityLabel.baseline
                        text: bookController.priorityModel.count
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                GridView {
                    id: priorityGrid
                    width: parent.width
                    height: visible ? contentHeight : 0
                    visible: bookController.priorityModel.count > 0
                    interactive: false
                    cellWidth: bookListPage.cellWidthFor(width)
                    cellHeight: cellWidth * (316 / 196)
                    model: bookController.priorityModel
                    delegate: bookCellDelegate
                }

                // Separator closing the priority section
                Rectangle {
                    width: parent.width
                    height: visible ? 1 : 0
                    visible: bookController.priorityModel.count > 0
                    color: Theme.priority
                    opacity: 0.5
                }

                Item {
                    width: parent.width
                    height: bookController.priorityModel.count > 0 ? Theme.spacingMedium : 0
                }

                // ── Status sections (default sort only; models empty otherwise) ──
                StatusSection {
                    sectionModel: bookController.readingModel
                    label: Theme.tr("Reading")
                    accent: Theme.statusReading
                }
                StatusSection {
                    sectionModel: bookController.plannedModel
                    label: Theme.tr("Planned")
                    accent: Theme.statusPlanned
                }
                StatusSection {
                    sectionModel: bookController.readModel
                    label: Theme.tr("Read")
                    accent: Theme.statusRead
                }
                StatusSection {
                    sectionModel: bookController.abandonedModel
                    label: Theme.tr("Abandoned")
                    accent: Theme.statusColor("abandoned")
                    gridOpacity: 0.7
                }

                // ── Flat grid — used only for explicit sorts (empty in default) ──
                GridView {
                    id: gridView
                    width: parent.width
                    height: contentHeight
                    interactive: false
                    cellWidth: bookListPage.cellWidthFor(width)
                    cellHeight: cellWidth * (316 / 196)
                    model: bookController.standardModel
                    delegate: bookCellDelegate
                }
            }

            // Empty state — distinguishes "you have no books" from "this filter
            // matched nothing", because the fix is different in each case.
            EmptyState {
                anchors.centerIn: parent
                width: parent.width
                visible: bookController.model.count === 0

                readonly property bool isFiltered: searchField.text !== ""
                                                   || bookController.filterStatus !== ""
                                                   || bookController.filterYear !== 0

                icon: isFiltered ? "qrc:/qt/qml/BookWorm/src/img/icons/library-view.svg"
                                 : "qrc:/qt/qml/BookWorm/src/img/icons/add-book.svg"
                title: isFiltered ? Theme.tr("No books match your search")
                                  : Theme.tr("Your library is empty")
                hint: isFiltered ? Theme.tr("Try a different search term, or clear the filters.")
                                 : Theme.tr("Add your first book to start tracking what you read.")
                actionText: isFiltered ? Theme.tr("Clear filters") : Theme.tr("Add Book")
                onActionClicked: {
                    if (isFiltered) {
                        searchField.text = "";
                        bookController.filterStatus = "";
                        bookController.filterYear = 0;
                        yearCombo.currentIndex = 0;
                    } else {
                        addDialog.mode = "add";
                        addDialog.editData = null;
                        addDialog.open();
                    }
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

        // ── Priority toggle — all statuses ──
        MenuItem {
            text: bookListPage.contextBookIsPriority
                  ? Theme.tr("Remove Priority")
                  : Theme.tr("Set Priority")
            icon.source: bookListPage.contextBookIsPriority
                         ? "qrc:/qt/qml/BookWorm/src/img/icons/star-empty.svg"
                         : "qrc:/qt/qml/BookWorm/src/img/icons/star-full.svg"
            icon.color: Theme.priority
            onTriggered: {
                var data = bookController.getBookDetails(bookListPage.contextBookId);
                data["isPriority"] = !bookListPage.contextBookIsPriority;
                bookController.updateBook(data);
            }
        }

        MenuSeparator { }

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
            // Force-commit typed text (editable SpinBox doesn't update value until Enter/focus-loss)
            addPagesSpinBox.value = addPagesSpinBox.valueFromText(addPagesSpinBox.contentItem.text, addPagesSpinBox.locale);
            bookController.updateReadingProgress(bookListPage.contextBookId, addPagesSpinBox.value);
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
            bookController.markAsRead(bookListPage.contextBookId,
                                      markStarRating.selectedRating,
                                      markReviewField.text);
        }
    }

    // ═══════════════════════════════════════════════════
    // Layout popup
    // ═══════════════════════════════════════════════════
    // Quick access to the two grid settings; the same values also live in
    // Settings → Appearance, both writing the persisted properties in Main.qml.
    Popup {
        id: layoutPopup
        x: parent.width - width - Theme.pageMargin
        y: 96
        width: 260
        padding: Theme.spacingLarge
        modal: true

        background: Panel {
            radius: Theme.radiusCard
            elevated: true
        }

        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationFast }
                NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Theme.durationMedium; easing.type: Theme.easeOut }
            }
        }

        ColumnLayout {
            width: parent.width
            spacing: Theme.spacingLarge

            SectionLabel { text: Theme.tr("Layout") }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingMedium

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingMedium

                    Text {
                        Layout.fillWidth: true
                        text: Theme.tr("Cards per row")
                        color: Theme.textOnSurface
                        font.pixelSize: Theme.fontSizeMedium
                    }

                    Chip {
                        text: Theme.tr("Auto")
                        selected: bookListPage.userCardsPerRow === 0
                        onClicked: bookListPage.userCardsPerRow =
                                   bookListPage.userCardsPerRow === 0 ? 6 : 0
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall
                    opacity: bookListPage.userCardsPerRow === 0 ? 0.4 : 1.0

                    Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }

                    // Zoom out (more, smaller cards)
                    AppButton {
                        variant: "outline"
                        text: "−"
                        Layout.preferredWidth: 44
                        enabledState: bookListPage.userCardsPerRow > 0
                                      && bookListPage.userCardsPerRow < 8
                        onClicked: bookListPage.userCardsPerRow += 1
                    }

                    Text {
                        Layout.fillWidth: true
                        text: bookListPage.userCardsPerRow > 0 ? bookListPage.userCardsPerRow : "—"
                        color: Theme.textOnSurface
                        font.pixelSize: Theme.fontSizeLarge
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // Zoom in (fewer, bigger cards)
                    AppButton {
                        variant: "outline"
                        text: "+"
                        Layout.preferredWidth: 44
                        enabledState: bookListPage.userCardsPerRow > 2
                        onClicked: bookListPage.userCardsPerRow -= 1
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.outline }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingMedium

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        text: Theme.tr("Prioritize books")
                        color: Theme.textOnSurface
                        font.pixelSize: Theme.fontSizeMedium
                    }

                    Text {
                        text: Theme.tr("Flagged books on top")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                Switch {
                    checked: bookListPage.priorityEnabled
                    Material.accent: Theme.primary
                    onToggled: bookListPage.priorityEnabled = checked
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
