import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Dialogs
import BookWorm

Dialog {
    id: formDialog

    property string mode: "add"
    property var editData: null
    property var bookData: ({})
    property string coverPath: ""
    property string audioModeSelection: "none"

    // Helper: is status "read"?
    readonly property bool isRead: statusCombo.currentIndex === 1

    // Compact field height
    readonly property int fieldHeight: 36
    readonly property int fieldTopPad: 6
    readonly property int fieldBotPad: 6

    title: ""
    modal: true
    closePolicy: Dialog.NoAutoClose
    standardButtons: Dialog.NoButton
    width: Math.min(620, parent.width - 48)
    height: Math.min(780, parent.height - 48)

    anchors.centerIn: parent

    Material.theme: Material.Dark
    Material.accent: Theme.primary

    header: Item {}
    padding: 0

    background: Rectangle {
        radius: Theme.radiusLarge
        color: Theme.surface
        border.width: 1
        border.color: Theme.divider
    }

    // ── Date helpers ──
    function isoToDisplay(iso) {
        if (!iso || iso.length === 0) return "";
        var parts = iso.split("-");
        if (parts.length !== 3) return iso;
        return parts[2] + "-" + parts[1] + "-" + parts[0];
    }

    function displayToIso(display) {
        if (!display || display.length === 0) return "";
        var clean = display.replace(/_/g, "");
        if (clean.length < 8) return "";
        var parts = display.split("-");
        if (parts.length !== 3) return "";
        return parts[2] + "-" + parts[1] + "-" + parts[0];
    }

    function todayDisplay() {
        var d = new Date();
        var dd = String(d.getDate()).padStart(2, '0');
        var mm = String(d.getMonth() + 1).padStart(2, '0');
        var yyyy = d.getFullYear();
        return dd + "-" + mm + "-" + yyyy;
    }

    // ── Autocomplete helpers ──
    property var allAuthors: []
    property var allPublishers: []

    function refreshAuthorSuggestions() {
        authorSuggestModel.clear();
        var query = authorField.text.trim().toLowerCase();
        if (query.length < 2) return;
        for (var i = 0; i < allAuthors.length; i++) {
            if (allAuthors[i].toLowerCase().indexOf(query) >= 0)
                authorSuggestModel.append({ name: allAuthors[i] });
        }
    }

    function refreshPublisherSuggestions() {
        publisherSuggestModel.clear();
        var query = publisherField.text.trim().toLowerCase();
        if (query.length < 2) return;
        for (var i = 0; i < allPublishers.length; i++) {
            if (allPublishers[i].toLowerCase().indexOf(query) >= 0)
                publisherSuggestModel.append({ name: allPublishers[i] });
        }
    }

    function refreshSeriesSuggestions() {
        seriesSuggestModel.clear();
        var query = seriesField.text.trim().toLowerCase();
        if (query.length < 2) return;
        var author = authorField.text.trim();
        // If author is set, show only that author's series; otherwise all series
        var pool = author.length > 0
            ? bookController.getSeriesForAuthor(author)
            : bookController.getAllSeries();
        for (var i = 0; i < pool.length; i++) {
            if (pool[i].toLowerCase().indexOf(query) >= 0)
                seriesSuggestModel.append({ name: pool[i] });
        }
    }

    onOpened: {
        // Load autocomplete data
        allAuthors = bookController.getAllAuthors();
        allPublishers = bookController.getAllPublishers();

        // Load genre suggestions (default + DB)
        genreTagModel.clear();
        var genres = bookController.getDefaultGenres();
        for (var g = 0; g < genres.length; g++)
            genreTagModel.append({ name: genres[g], selected: false });

        // Series suggestions loaded dynamically via refreshSeriesSuggestions()

        // Load tag suggestions
        tagSuggestionModel.clear();
        var tags = bookController.getAllTags();
        for (var t = 0; t < tags.length; t++)
            tagSuggestionModel.append({ name: tags[t], selected: false });

        if (mode === "edit" && editData) {
            titleField.text       = editData.title || "";
            authorField.text      = editData.author || "";
            pageCountField.value  = editData.pageCount || 0;
            startDateField.text   = isoToDisplay(editData.startDate || "");
            endDateField.text     = isoToDisplay(editData.endDate || "");
            starRating.rating     = editData.rating || 0;
            statusCombo.currentIndex = statusCombo.model.indexOf(editData.status || "planned");
            notesField.text       = editData.notes || "";
            isbnField.text        = editData.isbn || "";
            publisherField.text   = editData.publisher || "";
            pubYearField.value    = editData.publicationYear || 2024;
            coverPath             = editData.coverImagePath || "";
            var itIdx = itemTypeCombo.model.indexOf(editData.itemType || "book");
            itemTypeCombo.currentIndex = itIdx >= 0 ? itIdx : 0;
            nonFictionCheck.checked = editData.isNonFiction || false;
            audioModeSelection = editData.audioMode || "none";
            currentPageField.value = editData.currentPage || 0;

            // Select matching genre
            var editGenre = editData.genre || "";
            var foundGenre = false;
            for (var gi = 0; gi < genreTagModel.count; gi++) {
                if (genreTagModel.get(gi).name === editGenre) {
                    genreTagModel.setProperty(gi, "selected", true);
                    foundGenre = true;
                }
            }
            if (editGenre !== "" && !foundGenre) {
                genreTagModel.append({ name: editGenre, selected: true });
            }

            // Set series
            seriesField.text = editData.series || "";

            // Select matching language
            var editLang = editData.language || "English";
            var langIdx = languageCombo.find(editLang);
            languageCombo.currentIndex = langIdx >= 0 ? langIdx : 0;

            // Select matching tags
            var editTags = (editData.tags || "").split(",");
            for (var ti = 0; ti < editTags.length; ti++) {
                var tag = editTags[ti].trim();
                if (tag === "") continue;
                var foundTag = false;
                for (var si = 0; si < tagSuggestionModel.count; si++) {
                    if (tagSuggestionModel.get(si).name === tag) {
                        tagSuggestionModel.setProperty(si, "selected", true);
                        foundTag = true;
                        break;
                    }
                }
                if (!foundTag) {
                    tagSuggestionModel.append({ name: tag, selected: true });
                }
            }
        } else {
            clearForm();
        }
    }

    // Reset rating when status changes away from "read"
    onIsReadChanged: {
        if (!isRead)
            starRating.rating = 0;
    }

    function selectedGenre() {
        for (var i = 0; i < genreTagModel.count; i++) {
            if (genreTagModel.get(i).selected)
                return genreTagModel.get(i).name;
        }
        return "";
    }

    function selectedSeries() {
        return seriesField.text.trim();
    }

    function selectedTags() {
        var result = [];
        for (var i = 0; i < tagSuggestionModel.count; i++) {
            if (tagSuggestionModel.get(i).selected)
                result.push(tagSuggestionModel.get(i).name);
        }
        return result.join(", ");
    }

    function selectedAudioMode() {
        return audioModeSelection;
    }

    function collectData() {
        bookData = {
            id:              mode === "edit" && editData ? editData.id : -1,
            title:           titleField.text,
            author:          authorField.text,
            genre:           selectedGenre(),
            pageCount:       pageCountField.value,
            startDate:       displayToIso(startDateField.text),
            endDate:         displayToIso(endDateField.text),
            rating:          starRating.rating,
            status:          statusCombo.model[statusCombo.currentIndex],
            notes:           notesField.text,
            isbn:            isbnField.text,
            publisher:       publisherField.text,
            publicationYear: pubYearField.value,
            language:        languageCombo.currentText,
            tags:            selectedTags(),
            series:          selectedSeries(),
            coverImagePath:  coverPath,
            itemType:        itemTypeCombo.model[itemTypeCombo.currentIndex],
            isNonFiction:    nonFictionCheck.checked,
            audioMode:       selectedAudioMode(),
            currentPage:     currentPageField.value
        };
    }

    function clearForm() {
        titleField.text      = "";
        authorField.text     = "";
        pageCountField.value = 0;
        startDateField.text  = "";
        endDateField.text    = "";
        starRating.rating    = 0;
        statusCombo.currentIndex = 2;
        notesField.text      = "";
        isbnField.text       = "";
        publisherField.text  = "";
        pubYearField.value   = 2024;
        languageCombo.currentIndex = 0;
        coverPath            = "";
        itemTypeCombo.currentIndex = 0;
        nonFictionCheck.checked = false;
        audioModeSelection = "none";
        currentPageField.value = 0;

        for (var i = 0; i < genreTagModel.count; i++)
            genreTagModel.setProperty(i, "selected", false);
        seriesField.text = "";
        for (var k = 0; k < tagSuggestionModel.count; k++)
            tagSuggestionModel.setProperty(k, "selected", false);
    }

    // Models for genre, series, tag chips, and autocomplete
    ListModel { id: genreTagModel }
    ListModel { id: seriesSuggestModel }
    ListModel { id: tagSuggestionModel }
    ListModel { id: authorSuggestModel }
    ListModel { id: publisherSuggestModel }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Header ──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            color: "transparent"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingXL
                anchors.verticalCenter: parent.verticalCenter
                text: mode === "add" ? Theme.tr("Add New Book") : Theme.tr("Edit Book")
                color: Theme.textOnSurface
                font.pixelSize: Theme.fontSizeTitle
                font.bold: true
            }

            ToolButton {
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingMedium
                anchors.verticalCenter: parent.verticalCenter
                text: "\u2715"
                font.pixelSize: 16
                Material.foreground: Theme.textSecondary
                onClicked: formDialog.reject()
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.divider }

        // ── Scrollable content ──
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: contentColumn.implicitHeight + Theme.spacingXL
            clip: true
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: contentColumn
                width: parent.width
                spacing: Theme.spacingLarge

                // ═══════════════════════════════════
                // Top: Cover (left) + Title/Author (right)
                // ═══════════════════════════════════
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacingLarge
                    Layout.leftMargin: Theme.spacingXL
                    Layout.rightMargin: Theme.spacingXL
                    spacing: Theme.spacingXL

                    // Cover picker
                    Item {
                        Layout.preferredWidth: 120
                        Layout.preferredHeight: 175

                        Rectangle {
                            id: coverArea
                            anchors.fill: parent
                            radius: Theme.radiusMedium
                            color: Theme.surfaceVariant
                            border.width: coverMouse.containsMouse ? 2 : 0
                            border.color: Theme.primary

                            Image {
                                id: coverImage
                                anchors.fill: parent
                                source: coverPath ? "file://" + coverPath : ""
                                fillMode: Image.PreserveAspectCrop
                                visible: status === Image.Ready
                                clip: true
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: Theme.spacingSmall
                                visible: !coverImage.visible

                                Image {
                                    Layout.alignment: Qt.AlignHCenter
                                    source: "qrc:/qt/qml/BookWorm/src/img/icons/book-cover.svg"
                                    sourceSize.width: 36
                                    sourceSize.height: 36
                                    opacity: 0.4
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: Theme.tr("Add Cover")
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.radiusMedium
                                color: Qt.rgba(0, 0, 0, 0.5)
                                visible: coverImage.visible && coverMouse.containsMouse

                                Text {
                                    anchors.centerIn: parent
                                    text: Theme.tr("Change")
                                    color: "#FFFFFF"
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.bold: true
                                }
                            }

                            MouseArea {
                                id: coverMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: fileDialog.open()
                            }
                        }

                        ToolButton {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.topMargin: -6
                            anchors.rightMargin: -6
                            visible: coverPath !== ""
                            width: 22; height: 22

                            background: Rectangle { radius: 11; color: Theme.error }
                            contentItem: Text {
                                text: "\u2715"; color: "#FFFFFF"; font.pixelSize: 10
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: coverPath = ""
                        }
                    }

                    // Title + Author + Type + Non-fiction
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: Theme.spacingMedium

                        TextField {
                            id: titleField
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            topPadding: fieldTopPad
                            bottomPadding: fieldBotPad
                            placeholderText: Theme.tr("Title *")
                            font.pixelSize: Theme.fontSizeLarge
                            Material.accent: Theme.primary
                        }

                        // Author with autocomplete
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: fieldHeight

                            TextField {
                                id: authorField
                                anchors.fill: parent
                                topPadding: fieldTopPad
                                bottomPadding: fieldBotPad
                                placeholderText: Theme.tr("Author *")
                                font.pixelSize: Theme.fontSizeMedium
                                Material.accent: Theme.primary
                                onTextChanged: {
                                    formDialog.refreshAuthorSuggestions();
                                    if (authorSuggestModel.count > 0 && activeFocus)
                                        authorPopup.open();
                                    else
                                        authorPopup.close();
                                }
                                onActiveFocusChanged: {
                                    if (!activeFocus)
                                        authorCloseTimer.start();
                                }
                            }

                            Timer {
                                id: authorCloseTimer
                                interval: 150
                                onTriggered: authorPopup.close()
                            }

                            Popup {
                                id: authorPopup
                                y: parent.height + 2
                                width: parent.width
                                height: Math.min(authorSuggestList.contentHeight + 12, 160)
                                padding: 6
                                modal: false
                                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                                background: Rectangle {
                                    radius: Theme.radiusMedium
                                    color: Theme.surface
                                    border.width: 1
                                    border.color: Theme.divider
                                }

                                ListView {
                                    id: authorSuggestList
                                    anchors.fill: parent
                                    model: authorSuggestModel
                                    clip: true

                                    delegate: Rectangle {
                                        required property int index
                                        required property string name

                                        width: authorSuggestList.width
                                        height: 28
                                        color: suggestMouse.containsMouse ? Theme.surfaceVariant : "transparent"
                                        radius: Theme.radiusSmall

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left
                                            anchors.leftMargin: 8
                                            text: name
                                            color: Theme.textOnSurface
                                            font.pixelSize: Theme.fontSizeSmall
                                        }

                                        MouseArea {
                                            id: suggestMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                authorField.text = name;
                                                authorPopup.close();
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingMedium

                            Text {
                                text: Theme.tr("Type:")
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            ComboBox {
                                id: itemTypeCombo
                                Layout.fillWidth: true
                                Layout.preferredHeight: fieldHeight
                                model: ["book", "article", "newspaper", "magazine", "comic", "manga", "thesis", "workbook", "other"]
                                Material.accent: Theme.primary
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingMedium

                            CheckBox {
                                id: nonFictionCheck
                                Material.accent: Theme.secondary
                            }

                            Text {
                                text: Theme.tr("Technical book / Textbook")
                                color: Theme.textOnSurface
                                font.pixelSize: Theme.fontSizeMedium

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: nonFictionCheck.checked = !nonFictionCheck.checked
                                }
                            }
                        }

                        // Audiobook mode chips
                        Row {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSmall

                            Repeater {
                                model: [
                                    { key: "Standard",          value: "none" },
                                    { key: "Audiobook",         value: "audiobook" },
                                    { key: "Audiobook Support", value: "audiobook_support" }
                                ]

                                Rectangle {
                                    required property var modelData
                                    required property int index

                                    property bool isSelected: formDialog.audioModeSelection === modelData.value

                                    width: audioChipText.implicitWidth + Theme.spacingLarge * 2
                                    height: 28
                                    radius: 14
                                    color: isSelected ? Theme.secondary : "transparent"
                                    border.width: 1
                                    border.color: isSelected ? "transparent" : Theme.divider

                                    Text {
                                        id: audioChipText
                                        anchors.centerIn: parent
                                        text: Theme.tr(modelData.key)
                                        color: isSelected ? "#000000" : Theme.textSecondary
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.bold: isSelected
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: formDialog.audioModeSelection = modelData.value
                                    }
                                }
                            }
                        }
                    }
                }

                // ═══════════════════════════════════
                // Status chips
                // ═══════════════════════════════════
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Theme.spacingMedium

                    ComboBox {
                        id: statusCombo
                        visible: false
                        model: ["reading", "read", "planned", "abandoned"]
                        currentIndex: 2
                    }

                    Repeater {
                        model: [
                            { key: "Reading",   value: "reading",   idx: 0 },
                            { key: "Read",      value: "read",      idx: 1 },
                            { key: "Planned",   value: "planned",   idx: 2 },
                            { key: "Abandoned", value: "abandoned", idx: 3 }
                        ]

                        Rectangle {
                            required property var modelData
                            required property int index

                            width: chipText.implicitWidth + Theme.spacingXL * 2
                            height: 32
                            radius: 16
                            color: statusCombo.currentIndex === modelData.idx
                                   ? Theme.statusColor(modelData.value)
                                   : Theme.surfaceVariant
                            border.width: 1
                            border.color: statusCombo.currentIndex === modelData.idx
                                          ? "transparent" : Theme.divider

                            Text {
                                id: chipText
                                anchors.centerIn: parent
                                text: Theme.tr(modelData.key)
                                color: statusCombo.currentIndex === modelData.idx
                                       ? "#000000" : Theme.textSecondary
                                font.pixelSize: Theme.fontSizeMedium
                                font.bold: statusCombo.currentIndex === modelData.idx
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: statusCombo.currentIndex = modelData.idx
                            }
                        }
                    }
                }

                // ═══════════════════════════════════
                // Star rating (0-6) — hidden when status != "read"
                // ═══════════════════════════════════
                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Theme.spacingSmall
                    visible: formDialog.isRead

                    Row {
                        id: starRating
                        property int rating: 0
                        readonly property var labels: ["", Theme.tr("Bad"), Theme.tr("Weak"), Theme.tr("Average"), Theme.tr("Good"), Theme.tr("Very good"), Theme.tr("Excellent")]
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 4

                        Repeater {
                            model: 6

                            Text {
                                required property int index
                                text: index < starRating.rating ? "\u2605" : "\u2606"
                                color: index < starRating.rating
                                       ? Theme.primary : Theme.textSecondary
                                font.pixelSize: 28

                                MouseArea {
                                    id: starMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (starRating.rating === index + 1)
                                            starRating.rating = 0;
                                        else
                                            starRating.rating = index + 1;
                                    }
                                }

                                ToolTip.visible: starMouse.containsMouse
                                ToolTip.delay: 300
                                ToolTip.text: (index + 1) + " — " + starRating.labels[index + 1]
                            }
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: starRating.rating > 0
                              ? starRating.rating + " / 6 — " + starRating.labels[starRating.rating]
                              : Theme.tr("Not rated")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                // ═══════════════════════════════════
                // Details
                // ═══════════════════════════════════
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.spacingLarge
                    Layout.rightMargin: Theme.spacingLarge
                    implicitHeight: detailsCol.implicitHeight + Theme.spacingLarge * 2
                    radius: Theme.radiusMedium
                    color: Theme.surfaceVariant

                    ColumnLayout {
                        id: detailsCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingLarge
                        spacing: Theme.spacingMedium

                        Text {
                            text: Theme.tr("DETAILS")
                            color: Theme.primary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: Theme.spacingLarge
                            rowSpacing: Theme.spacingSmall

                            // Row 1: Genre label + Language label
                            Text { text: Theme.tr("Genre"); color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }
                            Text { text: Theme.tr("Language"); color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }

                            // Row 1 fields: Genre selector + Language ComboBox
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: fieldHeight
                                    radius: Theme.radiusSmall
                                    color: "transparent"
                                    border.width: 1
                                    border.color: genrePickerMouse.containsMouse ? Theme.primary : Theme.divider

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 4
                                        spacing: 4

                                        Text {
                                            Layout.fillWidth: true
                                            text: formDialog.selectedGenre() || Theme.tr("Select genre...")
                                            color: formDialog.selectedGenre() ? Theme.textOnSurface : Theme.textSecondary
                                            font.pixelSize: Theme.fontSizeSmall
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            text: "\u2715"
                                            color: Theme.textSecondary
                                            font.pixelSize: 10
                                            visible: formDialog.selectedGenre() !== ""

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    for (var i = 0; i < genreTagModel.count; i++)
                                                        genreTagModel.setProperty(i, "selected", false);
                                                }
                                            }
                                        }

                                        Text {
                                            text: "\u25BC"
                                            color: Theme.textSecondary
                                            font.pixelSize: 8
                                        }
                                    }

                                    MouseArea {
                                        id: genrePickerMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: genrePopup.open()
                                    }

                                    Popup {
                                        id: genrePopup
                                        y: parent.height + 2
                                        width: Math.max(parent.width, 300)
                                        height: Math.min(genrePopupCol.implicitHeight + 16, 300)
                                        padding: 6
                                        modal: false
                                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                                        onOpened: genreFilterInput.forceActiveFocus()

                                        background: Rectangle {
                                            radius: Theme.radiusMedium
                                            color: Theme.surface
                                            border.width: 1
                                            border.color: Theme.divider
                                        }

                                        Flickable {
                                            anchors.fill: parent
                                            contentHeight: genrePopupCol.implicitHeight
                                            clip: true
                                            flickableDirection: Flickable.VerticalFlick
                                            boundsBehavior: Flickable.StopAtBounds

                                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                            ColumnLayout {
                                                id: genrePopupCol
                                                width: parent.width
                                                spacing: 4

                                                TextField {
                                                    id: genreFilterInput
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 30
                                                    topPadding: 4
                                                    bottomPadding: 4
                                                    placeholderText: Theme.tr("Search or add genre...")
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    Material.accent: Theme.primary
                                                    onAccepted: {
                                                        if (text.trim() !== "") {
                                                            for (var i = 0; i < genreTagModel.count; i++)
                                                                genreTagModel.setProperty(i, "selected", false);
                                                            // Check if exists first
                                                            var found = false;
                                                            for (var j = 0; j < genreTagModel.count; j++) {
                                                                if (genreTagModel.get(j).name.toLowerCase() === text.trim().toLowerCase()) {
                                                                    genreTagModel.setProperty(j, "selected", true);
                                                                    found = true;
                                                                    break;
                                                                }
                                                            }
                                                            if (!found)
                                                                genreTagModel.append({ name: text.trim(), selected: true });
                                                            text = "";
                                                            genrePopup.close();
                                                        }
                                                    }
                                                }

                                                Flow {
                                                    Layout.fillWidth: true
                                                    spacing: 4

                                                    Repeater {
                                                        model: genreTagModel

                                                        Rectangle {
                                                            required property int index
                                                            required property string name
                                                            required property bool selected

                                                            visible: {
                                                                var filter = genreFilterInput.text.trim().toLowerCase();
                                                                return filter.length === 0 || name.toLowerCase().indexOf(filter) >= 0;
                                                            }

                                                            width: visible ? gpChipLabel.implicitWidth + 16 : 0
                                                            height: visible ? 26 : 0
                                                            radius: 13
                                                            color: selected ? Theme.primary : "transparent"
                                                            border.width: 1
                                                            border.color: selected ? "transparent" : Theme.divider

                                                            Text {
                                                                id: gpChipLabel
                                                                anchors.centerIn: parent
                                                                text: name
                                                                color: selected ? "#000000" : Theme.textSecondary
                                                                font.pixelSize: Theme.fontSizeSmall
                                                            }

                                                            MouseArea {
                                                                anchors.fill: parent
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    for (var i = 0; i < genreTagModel.count; i++)
                                                                        genreTagModel.setProperty(i, "selected", false);
                                                                    if (!selected)
                                                                        genreTagModel.setProperty(index, "selected", true);
                                                                    genreFilterInput.text = "";
                                                                    genrePopup.close();
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            ComboBox {
                                id: languageCombo
                                Layout.fillWidth: true
                                Layout.preferredHeight: fieldHeight
                                model: ["English", "Polish", "German", "French", "Spanish", "Italian", "Russian", "Japanese", "Chinese", "Korean", "Other"]
                                font.pixelSize: Theme.fontSizeSmall
                                Material.accent: Theme.primary
                            }

                            // Series with autocomplete (spans both columns)
                            Text { text: Theme.tr("Series"); color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall; Layout.columnSpan: 2 }

                            Item {
                                Layout.fillWidth: true
                                Layout.columnSpan: 2
                                Layout.preferredHeight: fieldHeight

                                TextField {
                                    id: seriesField
                                    anchors.fill: parent
                                    topPadding: fieldTopPad
                                    bottomPadding: fieldBotPad
                                    placeholderText: Theme.tr("Series name...")
                                    font.pixelSize: Theme.fontSizeSmall
                                    Material.accent: Theme.primary
                                    onTextChanged: {
                                        formDialog.refreshSeriesSuggestions();
                                        if (seriesSuggestModel.count > 0 && activeFocus)
                                            seriesPopup.open();
                                        else
                                            seriesPopup.close();
                                    }
                                    onActiveFocusChanged: {
                                        if (!activeFocus)
                                            seriesCloseTimer.start();
                                    }
                                }

                                Timer {
                                    id: seriesCloseTimer
                                    interval: 150
                                    onTriggered: seriesPopup.close()
                                }

                                Popup {
                                    id: seriesPopup
                                    y: parent.height + 2
                                    width: parent.width
                                    height: Math.min(seriesSuggestList.contentHeight + 12, 160)
                                    padding: 6
                                    modal: false
                                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                                    background: Rectangle {
                                        radius: Theme.radiusMedium
                                        color: Theme.surface
                                        border.width: 1
                                        border.color: Theme.divider
                                    }

                                    ListView {
                                        id: seriesSuggestList
                                        anchors.fill: parent
                                        model: seriesSuggestModel
                                        clip: true

                                        delegate: Rectangle {
                                            required property int index
                                            required property string name

                                            width: seriesSuggestList.width
                                            height: 28
                                            color: seriesSuggestMouse.containsMouse ? Theme.surfaceVariant : "transparent"
                                            radius: Theme.radiusSmall

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.left: parent.left
                                                anchors.leftMargin: 8
                                                text: name
                                                color: Theme.textOnSurface
                                                font.pixelSize: Theme.fontSizeSmall
                                            }

                                            MouseArea {
                                                id: seriesSuggestMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    seriesField.text = name;
                                                    seriesPopup.close();
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Row 2: Pages + Publication date
                            Text { text: Theme.tr("Pages"); color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }
                            Text { text: Theme.tr("Published Year"); color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }

                            SpinBox {
                                id: pageCountField
                                Layout.fillWidth: true
                                Layout.preferredHeight: fieldHeight
                                from: 0; to: 99999
                                editable: true
                                Material.accent: Theme.primary
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            SpinBox {
                                id: pubYearField
                                Layout.fillWidth: true
                                Layout.preferredHeight: fieldHeight
                                from: 1000; to: 2100
                                value: 2024
                                editable: true
                                Material.accent: Theme.primary
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            // Row 2b: Current page (only when reading)
                            Text {
                                text: Theme.tr("Current page")
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                visible: statusCombo.currentIndex === 0
                            }
                            Item { visible: statusCombo.currentIndex === 0 }

                            SpinBox {
                                id: currentPageField
                                Layout.fillWidth: true
                                Layout.preferredHeight: fieldHeight
                                from: 0; to: 99999
                                editable: true
                                Material.accent: Theme.primary
                                font.pixelSize: Theme.fontSizeSmall
                                visible: statusCombo.currentIndex === 0
                            }
                            Item { visible: statusCombo.currentIndex === 0 }

                            // Row 3: ISBN + Publisher (with autocomplete)
                            Text { text: Theme.tr("ISBN"); color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }
                            Text { text: Theme.tr("Publisher"); color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }

                            TextField {
                                id: isbnField
                                Layout.fillWidth: true
                                Layout.preferredHeight: fieldHeight
                                topPadding: fieldTopPad
                                bottomPadding: fieldBotPad
                                placeholderText: "978-..."
                                font.pixelSize: Theme.fontSizeSmall
                                Material.accent: Theme.primary
                            }

                            // Publisher with autocomplete
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: fieldHeight

                                TextField {
                                    id: publisherField
                                    anchors.fill: parent
                                    topPadding: fieldTopPad
                                    bottomPadding: fieldBotPad
                                    placeholderText: Theme.tr("Publisher name")
                                    font.pixelSize: Theme.fontSizeSmall
                                    Material.accent: Theme.primary
                                    onTextChanged: {
                                        formDialog.refreshPublisherSuggestions();
                                        if (publisherSuggestModel.count > 0 && activeFocus)
                                            publisherPopup.open();
                                        else
                                            publisherPopup.close();
                                    }
                                    onActiveFocusChanged: {
                                        if (!activeFocus)
                                            publisherCloseTimer.start();
                                    }
                                }

                                Timer {
                                    id: publisherCloseTimer
                                    interval: 150
                                    onTriggered: publisherPopup.close()
                                }

                                Popup {
                                    id: publisherPopup
                                    y: parent.height + 2
                                    width: parent.width
                                    height: Math.min(publisherSuggestList.contentHeight + 12, 140)
                                    padding: 6
                                    modal: false
                                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                                    background: Rectangle {
                                        radius: Theme.radiusMedium
                                        color: Theme.surface
                                        border.width: 1
                                        border.color: Theme.divider
                                    }

                                    ListView {
                                        id: publisherSuggestList
                                        anchors.fill: parent
                                        model: publisherSuggestModel
                                        clip: true

                                        delegate: Rectangle {
                                            required property int index
                                            required property string name

                                            width: publisherSuggestList.width
                                            height: 28
                                            color: pubSuggestMouse.containsMouse ? Theme.surfaceVariant : "transparent"
                                            radius: Theme.radiusSmall

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.left: parent.left
                                                anchors.leftMargin: 8
                                                text: name
                                                color: Theme.textOnSurface
                                                font.pixelSize: Theme.fontSizeSmall
                                            }

                                            MouseArea {
                                                id: pubSuggestMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    publisherField.text = name;
                                                    publisherPopup.close();
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                    }
                }

                // ═══════════════════════════════════
                // Reading Dates
                // ═══════════════════════════════════
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.spacingLarge
                    Layout.rightMargin: Theme.spacingLarge
                    implicitHeight: datesCol.implicitHeight + Theme.spacingLarge * 2
                    radius: Theme.radiusMedium
                    color: Theme.surfaceVariant

                    ColumnLayout {
                        id: datesCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingLarge
                        spacing: Theme.spacingMedium

                        Text {
                            text: Theme.tr("READING DATES")
                            color: Theme.primary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingLarge

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: Theme.tr("Started")
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    TextField {
                                        id: startDateField
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: fieldHeight
                                        topPadding: fieldTopPad
                                        bottomPadding: fieldBotPad
                                        placeholderText: "DD-MM-YYYY"
                                        font.pixelSize: Theme.fontSizeSmall
                                        Material.accent: Theme.primary
                                        validator: RegularExpressionValidator { regularExpression: /[0-9\-]*/ }
                                        maximumLength: 10
                                    }

                                    ToolButton {
                                        width: 28; height: 28
                                        icon.source: "qrc:/qt/qml/BookWorm/src/img/icons/calendar.svg"
                                        icon.width: 16; icon.height: 16
                                        icon.color: Theme.textSecondary
                                        ToolTip.visible: hovered
                                        ToolTip.text: Theme.tr("Set today")
                                        onClicked: startDateField.text = formDialog.todayDisplay()
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: Theme.tr("Finished")
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    TextField {
                                        id: endDateField
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: fieldHeight
                                        topPadding: fieldTopPad
                                        bottomPadding: fieldBotPad
                                        placeholderText: "DD-MM-YYYY"
                                        font.pixelSize: Theme.fontSizeSmall
                                        Material.accent: Theme.primary
                                        validator: RegularExpressionValidator { regularExpression: /[0-9\-]*/ }
                                        maximumLength: 10
                                    }

                                    ToolButton {
                                        width: 28; height: 28
                                        icon.source: "qrc:/qt/qml/BookWorm/src/img/icons/calendar.svg"
                                        icon.width: 16; icon.height: 16
                                        icon.color: Theme.textSecondary
                                        ToolTip.visible: hovered
                                        ToolTip.text: Theme.tr("Set today")
                                        onClicked: endDateField.text = formDialog.todayDisplay()
                                    }
                                }
                            }
                        }
                    }
                }

                // ═══════════════════════════════════
                // Notes
                // ═══════════════════════════════════
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.spacingLarge
                    Layout.rightMargin: Theme.spacingLarge
                    implicitHeight: notesCol.implicitHeight + Theme.spacingLarge * 2
                    radius: Theme.radiusMedium
                    color: Theme.surfaceVariant

                    ColumnLayout {
                        id: notesCol
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

                        TextArea {
                            id: notesField
                            Layout.fillWidth: true
                            Layout.minimumHeight: 70
                            placeholderText: Theme.tr("Your thoughts about the book...")
                            wrapMode: TextArea.Wrap
                            font.pixelSize: Theme.fontSizeSmall
                            Material.accent: Theme.primary
                        }
                    }
                }

                Item { Layout.preferredHeight: Theme.spacingMedium }
            }
        }

        // ── Footer ──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            color: "transparent"

            Rectangle {
                anchors.top: parent.top
                width: parent.width; height: 1
                color: Theme.divider
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingXL
                anchors.rightMargin: Theme.spacingXL
                spacing: Theme.spacingMedium

                Text {
                    Layout.fillWidth: true
                    text: {
                        if (titleField.text.trim() === "") return Theme.tr("Title is required");
                        if (authorField.text.trim() === "") return Theme.tr("Author is required");
                        return "";
                    }
                    color: Theme.error
                    font.pixelSize: Theme.fontSizeSmall
                    font.italic: true
                    opacity: text !== "" ? 0.8 : 0
                }

                Button {
                    text: Theme.tr("Cancel")
                    flat: true
                    Material.foreground: Theme.textSecondary
                    onClicked: formDialog.reject()
                }

                Button {
                    text: mode === "add" ? Theme.tr("Add Book") : Theme.tr("Save")
                    enabled: titleField.text.trim() !== "" && authorField.text.trim() !== ""
                    Material.background: enabled ? Theme.primary : Theme.surfaceVariant
                    Material.foreground: enabled ? Theme.textOnPrimary : Theme.textSecondary
                    onClicked: {
                        formDialog.collectData();
                        formDialog.accepted();
                        formDialog.close();
                    }
                }
            }
        }
    }

    FileDialog {
        id: fileDialog
        title: Theme.tr("Select Cover Image")
        nameFilters: ["Image files (*.png *.jpg *.jpeg *.webp)"]
        onAccepted: {
            var path = selectedFile.toString();
            if (path.startsWith("file://"))
                path = path.substring(7);
            formDialog.coverPath = path;
        }
    }
}
