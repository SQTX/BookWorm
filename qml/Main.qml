import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
import WormBook

ApplicationWindow {
    id: root
    visible: true
    width: 1200
    height: 800
    minimumWidth: 900
    minimumHeight: 600
    title: "WormBook"
    color: Theme.background

    Material.theme: Theme.isDark ? Material.Dark : Material.Light
    Material.accent: Theme.primary

    property int currentPage: 0  // 0 = library, 1 = table, 2 = statistics, 3 = challenges

    // Persistence for settings
    Settings {
        id: appSettings
        property alias style: root.appStyle
        property alias language: root.appLanguage
    }

    Component.onCompleted: {
        Theme.setTheme(root.appStyle);
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Sidebar
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 64
            color: Theme.surface

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: Theme.spacingLarge
                anchors.bottomMargin: Theme.spacingLarge
                spacing: Theme.spacingSmall

                // Library button (card view)
                ToolButton {
                    Layout.alignment: Qt.AlignHCenter
                    width: 48; height: 48
                    icon.source: "qrc:/qt/qml/WormBook/src/img/icons/library-view.svg"
                    icon.width: 22; icon.height: 22
                    icon.color: currentPage === 0 ? Theme.primary : Theme.textSecondary

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3; height: 24
                        radius: 2
                        color: Theme.primary
                        visible: currentPage === 0
                    }

                    ToolTip.visible: hovered
                    ToolTip.text: root.appLanguage === "pl" ? "Biblioteka" : "Library"

                    onClicked: {
                        currentPage = 0;
                        stackView.replace(null, bookListComponent);
                    }
                }

                // Table button
                ToolButton {
                    Layout.alignment: Qt.AlignHCenter
                    width: 48; height: 48
                    icon.source: "qrc:/qt/qml/WormBook/src/img/icons/sheet-view.svg"
                    icon.width: 22; icon.height: 22
                    icon.color: currentPage === 1 ? Theme.primary : Theme.textSecondary

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3; height: 24
                        radius: 2
                        color: Theme.primary
                        visible: currentPage === 1
                    }

                    ToolTip.visible: hovered
                    ToolTip.text: root.appLanguage === "pl" ? "Tabela" : "Table"

                    onClicked: {
                        currentPage = 1;
                        stackView.replace(null, bookTableComponent);
                    }
                }

                // Statistics button
                ToolButton {
                    Layout.alignment: Qt.AlignHCenter
                    width: 48; height: 48
                    icon.source: "qrc:/qt/qml/WormBook/src/img/icons/stat-view.svg"
                    icon.width: 22; icon.height: 22
                    icon.color: currentPage === 2 ? Theme.primary : Theme.textSecondary

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3; height: 24
                        radius: 2
                        color: Theme.primary
                        visible: currentPage === 2
                    }

                    ToolTip.visible: hovered
                    ToolTip.text: root.appLanguage === "pl" ? "Statystyki" : "Statistics"

                    onClicked: {
                        currentPage = 2;
                        stackView.replace(null, statisticsComponent);
                    }
                }

                // Challenges button
                ToolButton {
                    Layout.alignment: Qt.AlignHCenter
                    width: 48; height: 48
                    icon.source: "qrc:/qt/qml/WormBook/src/img/icons/challenges.svg"
                    icon.width: 22; icon.height: 22
                    icon.color: currentPage === 3 ? Theme.primary : Theme.textSecondary

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3; height: 24
                        radius: 2
                        color: Theme.primary
                        visible: currentPage === 3
                    }

                    ToolTip.visible: hovered
                    ToolTip.text: root.appLanguage === "pl" ? "Wyzwania" : "Challenges"

                    onClicked: {
                        currentPage = 3;
                        stackView.replace(null, challengesComponent);
                    }
                }

                Item { Layout.fillHeight: true }

                // Tags button
                ToolButton {
                    Layout.alignment: Qt.AlignHCenter
                    width: 48; height: 48
                    icon.source: "qrc:/qt/qml/WormBook/src/img/icons/tags.svg"
                    icon.width: 20; icon.height: 20
                    icon.color: Theme.textSecondary

                    ToolTip.visible: hovered
                    ToolTip.text: root.appLanguage === "pl" ? "Tagi" : "Tags"

                    onClicked: tagsPopup.open()
                }

                // Export button
                ToolButton {
                    Layout.alignment: Qt.AlignHCenter
                    width: 48; height: 48
                    icon.source: "qrc:/qt/qml/WormBook/src/img/icons/export.svg"
                    icon.width: 20; icon.height: 20
                    icon.color: Theme.textSecondary

                    ToolTip.visible: hovered
                    ToolTip.text: root.appLanguage === "pl" ? "Eksportuj CSV" : "Export CSV"

                    onClicked: exportDialog.open()
                }

                // Import button
                ToolButton {
                    Layout.alignment: Qt.AlignHCenter
                    width: 48; height: 48
                    icon.source: "qrc:/qt/qml/WormBook/src/img/icons/inport.svg"
                    icon.width: 20; icon.height: 20
                    icon.color: Theme.textSecondary

                    ToolTip.visible: hovered
                    ToolTip.text: root.appLanguage === "pl" ? "Importuj CSV" : "Import CSV"

                    onClicked: importDialog.open()
                }

                // Settings button
                ToolButton {
                    Layout.alignment: Qt.AlignHCenter
                    width: 48; height: 48
                    icon.source: "qrc:/qt/qml/WormBook/src/img/icons/settings.svg"
                    icon.width: 22; icon.height: 22
                    icon.color: Theme.textSecondary

                    ToolTip.visible: hovered
                    ToolTip.text: root.appLanguage === "pl" ? "Ustawienia" : "Settings"

                    onClicked: settingsPopup.open()
                }

                Item { Layout.preferredHeight: Theme.spacingSmall }
            }
        }

        // Divider
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            color: Theme.divider
        }

        // Main content
        StackView {
            id: stackView
            Layout.fillWidth: true
            Layout.fillHeight: true
            initialItem: bookListComponent

            pushEnter: Transition {
                PropertyAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
            }
            pushExit: Transition {
                PropertyAnimation { property: "opacity"; from: 1; to: 0; duration: 200 }
            }
            replaceEnter: Transition {
                PropertyAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
            }
            replaceExit: Transition {
                PropertyAnimation { property: "opacity"; from: 1; to: 0; duration: 200 }
            }
        }
    }

    Component {
        id: bookListComponent
        BookListView {
            onBookSelected: function(bookId) {
                stackView.push(bookDetailsComponent, { bookId: bookId });
            }
        }
    }

    Component {
        id: bookDetailsComponent
        BookDetails {
            onBack: stackView.pop()
            onBookDeleted: stackView.pop()
        }
    }

    Component {
        id: bookTableComponent
        BookTableView {
            onBookSelected: function(bookId) {
                stackView.push(bookDetailsComponent, { bookId: bookId });
            }
        }
    }

    Component {
        id: statisticsComponent
        StatisticsView {}
    }

    Component {
        id: challengesComponent
        ChallengesView {}
    }

    // ── Settings ──

    property string appStyle: "minimalist_dark"
    property string appLanguage: "en"

    Popup {
        id: settingsPopup
        x: 80
        y: parent.height - height - 16
        width: 280
        padding: 0
        modal: true

        background: Rectangle {
            radius: Theme.radiusMedium
            color: Theme.surface
            border.width: 1
            border.color: Theme.divider
        }

        ColumnLayout {
            width: parent.width
            spacing: 0

            // Header
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                color: "transparent"

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingLarge
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.appLanguage === "pl" ? "Ustawienia" : "Settings"
                    color: Theme.textOnSurface
                    font.pixelSize: Theme.fontSizeLarge
                    font.bold: true
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.divider }

            // ── Language section ──
            Text {
                Layout.topMargin: Theme.spacingMedium
                Layout.leftMargin: Theme.spacingLarge
                text: root.appLanguage === "pl" ? "J\u0118ZYK" : "LANGUAGE"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }

            Repeater {
                model: [
                    { key: "en", label: "English" },
                    { key: "pl", label: "Polski" }
                ]

                Rectangle {
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    color: langMouse.containsMouse ? Theme.surfaceVariant : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingLarge
                        anchors.rightMargin: Theme.spacingLarge
                        spacing: Theme.spacingMedium

                        Text {
                            Layout.fillWidth: true
                            text: modelData.label
                            color: root.appLanguage === modelData.key
                                   ? Theme.primary : Theme.textOnSurface
                            font.pixelSize: Theme.fontSizeMedium
                            font.bold: root.appLanguage === modelData.key
                        }

                        Rectangle {
                            width: 18; height: 18; radius: 9
                            color: "transparent"
                            border.width: 2
                            border.color: root.appLanguage === modelData.key
                                          ? Theme.primary : Theme.textSecondary

                            Rectangle {
                                anchors.centerIn: parent
                                width: 10; height: 10; radius: 5
                                color: Theme.primary
                                visible: root.appLanguage === modelData.key
                            }
                        }
                    }

                    MouseArea {
                        id: langMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.appLanguage = modelData.key
                    }
                }
            }

            // ── Separator ──
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingMedium
                height: 1
                color: Theme.divider
            }

            // ── Style section ──
            Text {
                Layout.topMargin: Theme.spacingMedium
                Layout.leftMargin: Theme.spacingLarge
                text: root.appLanguage === "pl" ? "STYL APLIKACJI" : "APP STYLE"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }

            Repeater {
                model: [
                    { key: "minimalist_light", label: "Minimalist Light",
                      labelPl: "Minimalistyczny jasny" },
                    { key: "minimalist_dark",  label: "Minimalist Dark",
                      labelPl: "Minimalistyczny ciemny" },
                    { key: "classic",          label: "Classic",
                      labelPl: "Klasyczny" }
                ]

                Rectangle {
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    color: styleItemMouse.containsMouse ? Theme.surfaceVariant : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingLarge
                        anchors.rightMargin: Theme.spacingLarge
                        spacing: Theme.spacingMedium

                        Text {
                            Layout.fillWidth: true
                            text: root.appLanguage === "pl"
                                  ? modelData.labelPl : modelData.label
                            color: root.appStyle === modelData.key
                                   ? Theme.primary : Theme.textOnSurface
                            font.pixelSize: Theme.fontSizeMedium
                            font.bold: root.appStyle === modelData.key
                        }

                        Rectangle {
                            width: 18; height: 18; radius: 9
                            color: "transparent"
                            border.width: 2
                            border.color: root.appStyle === modelData.key
                                          ? Theme.primary : Theme.textSecondary

                            Rectangle {
                                anchors.centerIn: parent
                                width: 10; height: 10; radius: 5
                                color: Theme.primary
                                visible: root.appStyle === modelData.key
                            }
                        }
                    }

                    MouseArea {
                        id: styleItemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.appStyle = modelData.key;
                            Theme.setTheme(modelData.key);
                        }
                    }
                }
            }

            // ── Separator ──
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingMedium
                height: 1
                color: Theme.divider
            }

            // ── Reset data button ──
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                Layout.margins: Theme.spacingLarge
                radius: Theme.radiusSmall
                color: resetMouse.containsMouse ? "#D32F2F" : "#B71C1C"

                Text {
                    anchors.centerIn: parent
                    text: root.appLanguage === "pl" ? "Resetuj dane" : "Reset All Data"
                    color: "#FFFFFF"
                    font.pixelSize: Theme.fontSizeMedium
                    font.bold: true
                }

                MouseArea {
                    id: resetMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        settingsPopup.close();
                        resetConfirmDialog.open();
                    }
                }
            }

            Item { Layout.preferredHeight: Theme.spacingSmall }
        }
    }

    // ── Tags Popup ──
    Popup {
        id: tagsPopup
        x: 80
        y: Math.max(16, parent.height / 2 - height / 2)
        width: 340
        padding: 0
        modal: true

        property var tagsList: []
        property string newTagName: ""
        property string newTagColor: "#808080"

        readonly property var presetColors: [
            "#E57373", "#F06292", "#BA68C8", "#9575CD",
            "#7986CB", "#64B5F6", "#4FC3F7", "#4DD0E1",
            "#4DB6AC", "#81C784", "#AED581", "#DCE775",
            "#FFD54F", "#FFB74D", "#FF8A65", "#A1887F"
        ]

        onOpened: {
            tagsList = bookController.getAllTagsWithColors();
            newTagName = "";
            newTagColor = "#808080";
        }

        background: Rectangle {
            radius: Theme.radiusMedium
            color: Theme.surface
            border.width: 1
            border.color: Theme.divider
        }

        ColumnLayout {
            width: parent.width
            spacing: 0

            // Header
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                color: "transparent"

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingLarge
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.appLanguage === "pl" ? "Tagi" : "Tags"
                    color: Theme.textOnSurface
                    font.pixelSize: Theme.fontSizeLarge
                    font.bold: true
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.divider }

            // Tags list
            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(tagsCol.implicitHeight, 300)
                contentHeight: tagsCol.implicitHeight
                clip: true
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                ColumnLayout {
                    id: tagsCol
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: tagsPopup.tagsList

                        Rectangle {
                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            color: tagRowMouse.containsMouse ? Theme.surfaceVariant : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingLarge
                                anchors.rightMargin: Theme.spacingMedium
                                spacing: Theme.spacingMedium

                                // Color dot (clickable)
                                Rectangle {
                                    width: 20; height: 20; radius: 10
                                    color: modelData.color || "#808080"
                                    border.width: 1
                                    border.color: Qt.darker(modelData.color || "#808080", 1.3)

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            colorPickerPopup.tagId = modelData.id;
                                            colorPickerPopup.tagName = modelData.name;
                                            colorPickerPopup.selectedColor = modelData.color || "#808080";
                                            colorPickerPopup.isNewTag = false;
                                            colorPickerPopup.open();
                                        }
                                    }
                                }

                                // Editable name
                                TextField {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    topPadding: 4; bottomPadding: 4
                                    text: modelData.name
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: Theme.textOnSurface
                                    background: Rectangle {
                                        color: "transparent"
                                        border.width: parent.activeFocus ? 1 : 0
                                        border.color: Theme.primary
                                        radius: Theme.radiusSmall
                                    }
                                    onEditingFinished: {
                                        if (text.trim() !== "" && text.trim() !== modelData.name) {
                                            bookController.updateTag(modelData.id, text.trim(), modelData.color);
                                            tagsPopup.tagsList = bookController.getAllTagsWithColors();
                                        }
                                    }
                                }

                                // Delete button
                                ToolButton {
                                    width: 28; height: 28
                                    contentItem: Text {
                                        text: "\u2715"
                                        color: Theme.error
                                        font.pixelSize: 11
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: {
                                        bookController.deleteTag(modelData.id);
                                        tagsPopup.tagsList = bookController.getAllTagsWithColors();
                                    }
                                }
                            }

                            MouseArea {
                                id: tagRowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }
                        }
                    }

                    // Empty state
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: Theme.spacingLarge
                        Layout.bottomMargin: Theme.spacingLarge
                        visible: tagsPopup.tagsList.length === 0
                        text: root.appLanguage === "pl" ? "Brak tagów" : "No tags yet"
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeMedium
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.divider }

            // Add new tag section
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Theme.spacingMedium
                spacing: Theme.spacingSmall

                // Color picker for new tag
                Rectangle {
                    width: 24; height: 24; radius: 12
                    color: tagsPopup.newTagColor
                    border.width: 1
                    border.color: Qt.darker(tagsPopup.newTagColor, 1.3)

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            colorPickerPopup.tagId = -1;
                            colorPickerPopup.tagName = "";
                            colorPickerPopup.selectedColor = tagsPopup.newTagColor;
                            colorPickerPopup.isNewTag = true;
                            colorPickerPopup.open();
                        }
                    }
                }

                TextField {
                    id: newTagField
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    topPadding: 4; bottomPadding: 4
                    placeholderText: root.appLanguage === "pl" ? "Nowy tag..." : "New tag..."
                    font.pixelSize: Theme.fontSizeMedium
                    Material.accent: Theme.primary
                    text: tagsPopup.newTagName
                    onTextChanged: tagsPopup.newTagName = text
                    onAccepted: {
                        if (text.trim() !== "") {
                            bookController.addTag(text.trim(), tagsPopup.newTagColor);
                            tagsPopup.tagsList = bookController.getAllTagsWithColors();
                            text = "";
                            tagsPopup.newTagColor = "#808080";
                        }
                    }
                }

                RoundButton {
                    width: 32; height: 32
                    text: "+"
                    font.pixelSize: 16
                    font.bold: true
                    Material.background: Theme.primary
                    Material.foreground: Theme.textOnPrimary
                    enabled: newTagField.text.trim() !== ""
                    onClicked: {
                        bookController.addTag(newTagField.text.trim(), tagsPopup.newTagColor);
                        tagsPopup.tagsList = bookController.getAllTagsWithColors();
                        newTagField.text = "";
                        tagsPopup.newTagColor = "#808080";
                    }
                }
            }

            Item { Layout.preferredHeight: Theme.spacingSmall }
        }
    }

    // ── Color Picker Popup ──
    Popup {
        id: colorPickerPopup
        x: tagsPopup.x + tagsPopup.width + 8
        y: tagsPopup.y
        width: 200
        padding: Theme.spacingMedium
        modal: true

        property int tagId: -1
        property string tagName: ""
        property string selectedColor: "#808080"
        property bool isNewTag: false

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
                text: root.appLanguage === "pl" ? "Wybierz kolor" : "Pick color"
                color: Theme.textOnSurface
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
            }

            Grid {
                columns: 4
                spacing: 8

                Repeater {
                    model: tagsPopup.presetColors

                    Rectangle {
                        required property string modelData
                        width: 32; height: 32; radius: 16
                        color: modelData
                        border.width: colorPickerPopup.selectedColor === modelData ? 3 : 1
                        border.color: colorPickerPopup.selectedColor === modelData
                                      ? Theme.textOnSurface : Qt.darker(modelData, 1.3)

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                colorPickerPopup.selectedColor = modelData;
                                if (colorPickerPopup.isNewTag) {
                                    tagsPopup.newTagColor = modelData;
                                } else {
                                    bookController.updateTag(colorPickerPopup.tagId,
                                                             colorPickerPopup.tagName, modelData);
                                    tagsPopup.tagsList = bookController.getAllTagsWithColors();
                                }
                                colorPickerPopup.close();
                            }
                        }
                    }
                }
            }

            // Hex input
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSmall

                TextField {
                    id: hexInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    topPadding: 4; bottomPadding: 4
                    text: colorPickerPopup.selectedColor
                    font.pixelSize: Theme.fontSizeSmall
                    Material.accent: Theme.primary
                    maximumLength: 9
                    onAccepted: {
                        var c = text.trim();
                        if (c.match(/^#[0-9A-Fa-f]{6}$/)) {
                            colorPickerPopup.selectedColor = c;
                            if (colorPickerPopup.isNewTag) {
                                tagsPopup.newTagColor = c;
                            } else {
                                bookController.updateTag(colorPickerPopup.tagId,
                                                         colorPickerPopup.tagName, c);
                                tagsPopup.tagsList = bookController.getAllTagsWithColors();
                            }
                            colorPickerPopup.close();
                        }
                    }
                }

                Rectangle {
                    width: 24; height: 24; radius: 4
                    color: colorPickerPopup.selectedColor
                    border.width: 1
                    border.color: Theme.divider
                }
            }
        }
    }

    // ── Reset confirmation dialog ──
    Dialog {
        id: resetConfirmDialog
        title: ""
        modal: true
        standardButtons: Dialog.NoButton
        anchors.centerIn: parent
        width: Math.min(400, parent.width - 48)
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

            Text {
                Layout.topMargin: Theme.spacingLarge
                Layout.leftMargin: Theme.spacingXL
                text: root.appLanguage === "pl" ? "Resetowanie danych" : "Reset Data"
                color: "#D32F2F"
                font.pixelSize: Theme.fontSizeTitle
                font.bold: true
            }

            Rectangle { Layout.fillWidth: true; Layout.topMargin: Theme.spacingMedium; height: 1; color: Theme.divider }

            Text {
                Layout.fillWidth: true
                Layout.margins: Theme.spacingXL
                text: root.appLanguage === "pl"
                    ? "Czy na pewno chcesz usunąć wszystkie dane? Ta operacja jest nieodwracalna."
                    : "Are you sure you want to delete all data? This action cannot be undone."
                color: Theme.textOnSurface
                font.pixelSize: Theme.fontSizeMedium
                wrapMode: Text.Wrap
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.divider }

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Theme.spacingLarge
                spacing: Theme.spacingMedium

                Item { Layout.fillWidth: true }

                Button {
                    text: root.appLanguage === "pl" ? "Anuluj" : "Cancel"
                    flat: true
                    Material.foreground: Theme.textSecondary
                    onClicked: resetConfirmDialog.reject()
                }

                Button {
                    text: "OK"
                    Material.background: "#B71C1C"
                    Material.foreground: "#FFFFFF"
                    onClicked: {
                        bookController.resetAllData();
                        bookController.loadBooks();
                        resetConfirmDialog.close();
                        csvToast.show(root.appLanguage === "pl"
                            ? "Dane zostały zresetowane"
                            : "All data has been reset");
                    }
                }
            }
        }
    }

    // ── CSV Export/Import ──

    FileDialog {
        id: exportDialog
        title: root.appLanguage === "pl" ? "Eksportuj do CSV" : "Export to CSV"
        fileMode: FileDialog.SaveFile
        nameFilters: ["CSV files (*.csv)"]
        defaultSuffix: "csv"
        currentFile: "file:///wormbook_export.csv"

        onAccepted: {
            if (bookController.exportToCsv(selectedFile)) {
                csvToast.show(root.appLanguage === "pl"
                    ? "Eksport zakończony pomyślnie"
                    : "Export completed successfully");
            } else {
                csvToast.show(root.appLanguage === "pl"
                    ? "Błąd eksportu"
                    : "Export failed");
            }
        }
    }

    FileDialog {
        id: importDialog
        title: root.appLanguage === "pl" ? "Importuj z CSV" : "Import from CSV"
        fileMode: FileDialog.OpenFile
        nameFilters: ["CSV files (*.csv)"]

        onAccepted: {
            var count = bookController.importFromCsv(selectedFile);
            if (count >= 0) {
                csvToast.show(root.appLanguage === "pl"
                    ? "Zaimportowano " + count + " książek"
                    : "Imported " + count + " books");
            } else {
                csvToast.show(root.appLanguage === "pl"
                    ? "Błąd importu"
                    : "Import failed");
            }
        }
    }

    // Simple toast notification
    Rectangle {
        id: csvToast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 32
        width: toastLabel.implicitWidth + 48
        height: 40
        radius: 20
        color: Theme.surface
        border.width: 1
        border.color: Theme.divider
        opacity: 0
        visible: opacity > 0

        function show(msg) {
            toastLabel.text = msg;
            toastAnim.restart();
        }

        Text {
            id: toastLabel
            anchors.centerIn: parent
            color: Theme.textOnSurface
            font.pixelSize: Theme.fontSizeMedium
        }

        SequentialAnimation {
            id: toastAnim
            NumberAnimation { target: csvToast; property: "opacity"; to: 1; duration: 200 }
            PauseAnimation { duration: 2500 }
            NumberAnimation { target: csvToast; property: "opacity"; to: 0; duration: 400 }
        }
    }
}
