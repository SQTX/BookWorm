import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Dialogs
import WormBook

Dialog {
    id: formDialog

    property string mode: "add"
    property var editData: null
    property var bookData: ({})
    property string coverPath: ""

    // Helper: is status "read"?
    readonly property bool isRead: statusCombo.currentIndex === 1

    title: ""
    modal: true
    standardButtons: Dialog.NoButton
    width: Math.min(600, parent.width - 48)
    height: Math.min(760, parent.height - 48)

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

    onOpened: {
        if (mode === "edit" && editData) {
            titleField.text       = editData.title || "";
            authorField.text      = editData.author || "";
            genreField.text       = editData.genre || "";
            pageCountField.value  = editData.pageCount || 0;
            startDateField.text   = editData.startDate || "";
            endDateField.text     = editData.endDate || "";
            starRating.rating     = editData.rating || 0;
            statusCombo.currentIndex = statusCombo.model.indexOf(editData.status || "planned");
            notesField.text       = editData.notes || "";
            isbnField.text        = editData.isbn || "";
            publisherField.text   = editData.publisher || "";
            pubYearField.value    = editData.publicationYear || 2024;
            languageField.text    = editData.language || "English";
            tagsField.text        = editData.tags || "";
            coverPath             = editData.coverImagePath || "";
            var itIdx = itemTypeCombo.model.indexOf(editData.itemType || "book");
            itemTypeCombo.currentIndex = itIdx >= 0 ? itIdx : 0;
            nonFictionSwitch.checked = editData.isNonFiction || false;
            currentPageField.value = editData.currentPage || 0;
        } else {
            clearForm();
        }
    }

    // Reset rating when status changes away from "read"
    onIsReadChanged: {
        if (!isRead)
            starRating.rating = 0;
    }

    function collectData() {
        bookData = {
            id:              mode === "edit" && editData ? editData.id : -1,
            title:           titleField.text,
            author:          authorField.text,
            genre:           genreField.text,
            pageCount:       pageCountField.value,
            startDate:       startDateField.text,
            endDate:         endDateField.text,
            rating:          starRating.rating,
            status:          statusCombo.model[statusCombo.currentIndex],
            notes:           notesField.text,
            isbn:            isbnField.text,
            publisher:       publisherField.text,
            publicationYear: pubYearField.value,
            language:        languageField.text,
            tags:            tagsField.text,
            coverImagePath:  coverPath,
            itemType:        itemTypeCombo.model[itemTypeCombo.currentIndex],
            isNonFiction:    nonFictionSwitch.checked,
            currentPage:     currentPageField.value
        };
    }

    function clearForm() {
        titleField.text      = "";
        authorField.text     = "";
        genreField.text      = "";
        pageCountField.value = 0;
        startDateField.text  = "";
        endDateField.text    = "";
        starRating.rating    = 0;
        statusCombo.currentIndex = 2;
        notesField.text      = "";
        isbnField.text       = "";
        publisherField.text  = "";
        pubYearField.value   = 2024;
        languageField.text   = "English";
        tagsField.text       = "";
        coverPath            = "";
        itemTypeCombo.currentIndex = 0;
        nonFictionSwitch.checked = false;
        currentPageField.value = 0;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Header ──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            color: "transparent"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingXL
                anchors.verticalCenter: parent.verticalCenter
                text: mode === "add" ? "Add New Book" : "Edit Book"
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
                        Layout.preferredWidth: 130
                        Layout.preferredHeight: 190

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

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "\u{1F4F7}"
                                    font.pixelSize: 36
                                    opacity: 0.5
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Add Cover"
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
                                    text: "Change"
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
                            placeholderText: "Title *"
                            font.pixelSize: Theme.fontSizeLarge
                            Material.accent: Theme.primary
                        }

                        TextField {
                            id: authorField
                            Layout.fillWidth: true
                            placeholderText: "Author *"
                            font.pixelSize: Theme.fontSizeMedium
                            Material.accent: Theme.primary
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingMedium

                            Text {
                                text: "Type:"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            ComboBox {
                                id: itemTypeCombo
                                Layout.fillWidth: true
                                model: ["book", "article", "newspaper", "magazine", "comic", "manga", "thesis", "other"]
                                Material.accent: Theme.primary
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingMedium

                            Switch {
                                id: nonFictionSwitch
                                Material.accent: Theme.secondary
                            }

                            ColumnLayout {
                                spacing: 0
                                Text {
                                    text: "Non-fiction / Technical"
                                    color: Theme.textOnSurface
                                    font.pixelSize: Theme.fontSizeMedium
                                }
                                Text {
                                    text: "Textbook, manual, professional"
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
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
                        model: ["reading", "read", "planned"]
                        currentIndex: 2
                    }

                    Repeater {
                        model: [
                            { label: "Reading",  value: "reading",  idx: 0 },
                            { label: "Read",     value: "read",     idx: 1 },
                            { label: "Planned",  value: "planned",  idx: 2 }
                        ]

                        Rectangle {
                            required property var modelData
                            required property int index

                            width: chipText.implicitWidth + Theme.spacingXL * 2
                            height: 36
                            radius: 18
                            color: statusCombo.currentIndex === modelData.idx
                                   ? Theme.statusColor(modelData.value)
                                   : Theme.surfaceVariant
                            border.width: 1
                            border.color: statusCombo.currentIndex === modelData.idx
                                          ? "transparent" : Theme.divider

                            Text {
                                id: chipText
                                anchors.centerIn: parent
                                text: modelData.label
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
                // Star rating (0-6) — only enabled when status = "read"
                // ═══════════════════════════════════
                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Theme.spacingSmall
                    opacity: formDialog.isRead ? 1.0 : 0.35

                    Row {
                        id: starRating
                        property int rating: 0
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 4

                        Repeater {
                            model: 6

                            Text {
                                required property int index
                                text: index < starRating.rating ? "\u2605" : "\u2606"
                                color: index < starRating.rating
                                       ? Theme.primary : Theme.textSecondary
                                font.pixelSize: 32

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: formDialog.isRead
                                    cursorShape: formDialog.isRead ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    enabled: formDialog.isRead
                                    onClicked: {
                                        if (starRating.rating === index + 1)
                                            starRating.rating = 0;
                                        else
                                            starRating.rating = index + 1;
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: {
                            if (!formDialog.isRead)
                                return "Rate after reading";
                            return starRating.rating > 0
                                   ? starRating.rating + " / 6"
                                   : "Not rated";
                        }
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
                            text: "DETAILS"
                            color: Theme.primary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: Theme.spacingMedium
                            rowSpacing: Theme.spacingMedium

                            // Row 1: Genre + Language
                            Text { text: "Genre"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }
                            Text { text: "Language"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }

                            TextField {
                                id: genreField
                                Layout.fillWidth: true
                                placeholderText: "e.g. Fantasy"
                                Material.accent: Theme.primary
                            }
                            TextField {
                                id: languageField
                                Layout.fillWidth: true
                                text: "English"
                                Material.accent: Theme.primary
                            }

                            // Row 2: Pages + Year
                            Text { text: "Pages"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }
                            Text { text: "Year"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }

                            SpinBox {
                                id: pageCountField
                                Layout.fillWidth: true
                                from: 0; to: 99999
                                editable: true
                                Material.accent: Theme.primary
                            }
                            SpinBox {
                                id: pubYearField
                                Layout.fillWidth: true
                                from: 1000; to: 2100
                                value: 2024
                                editable: true
                                Material.accent: Theme.primary
                            }

                            // Row 2b: Current page + (empty)
                            Text {
                                text: "Current page"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                visible: statusCombo.currentIndex === 0 // "reading"
                            }
                            Item { visible: statusCombo.currentIndex === 0 }

                            SpinBox {
                                id: currentPageField
                                Layout.fillWidth: true
                                from: 0; to: 99999
                                editable: true
                                Material.accent: Theme.primary
                                visible: statusCombo.currentIndex === 0 // "reading"
                            }
                            Item { visible: statusCombo.currentIndex === 0 }

                            // Row 3: ISBN + Publisher
                            Text { text: "ISBN"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }
                            Text { text: "Publisher"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }

                            TextField {
                                id: isbnField
                                Layout.fillWidth: true
                                placeholderText: "978-..."
                                Material.accent: Theme.primary
                            }
                            TextField {
                                id: publisherField
                                Layout.fillWidth: true
                                placeholderText: "Publisher name"
                                Material.accent: Theme.primary
                            }
                        }

                        Text { text: "Tags"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }
                        TextField {
                            id: tagsField
                            Layout.fillWidth: true
                            placeholderText: "sci-fi, classic, favorites..."
                            Material.accent: Theme.primary
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
                            text: "READING DATES"
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
                                Text { text: "Started"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }
                                TextField {
                                    id: startDateField
                                    Layout.fillWidth: true
                                    placeholderText: "YYYY-MM-DD"
                                    inputMask: "9999-99-99"
                                    Material.accent: Theme.primary
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text { text: "Finished"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }
                                TextField {
                                    id: endDateField
                                    Layout.fillWidth: true
                                    placeholderText: "YYYY-MM-DD"
                                    inputMask: "9999-99-99"
                                    Material.accent: Theme.primary
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
                            text: "NOTES"
                            color: Theme.primary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }

                        TextArea {
                            id: notesField
                            Layout.fillWidth: true
                            Layout.minimumHeight: 80
                            placeholderText: "Your thoughts about the book..."
                            wrapMode: TextArea.Wrap
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
            Layout.preferredHeight: 60
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
                        if (titleField.text.trim() === "") return "Title is required";
                        if (authorField.text.trim() === "") return "Author is required";
                        return "";
                    }
                    color: Theme.error
                    font.pixelSize: Theme.fontSizeSmall
                    font.italic: true
                    opacity: text !== "" ? 0.8 : 0
                }

                Button {
                    text: "Cancel"
                    flat: true
                    Material.foreground: Theme.textSecondary
                    onClicked: formDialog.reject()
                }

                Button {
                    text: mode === "add" ? "Add Book" : "Save"
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
        title: "Select Cover Image"
        nameFilters: ["Image files (*.png *.jpg *.jpeg *.webp)"]
        onAccepted: {
            var path = selectedFile.toString();
            if (path.startsWith("file://"))
                path = path.substring(7);
            formDialog.coverPath = path;
        }
    }
}
