import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Effects
import QtCore
import BookWorm
import Qt.labs.platform as Platform

ApplicationWindow {
    id: root
    visible: true
    width: 1200
    height: 800
    minimumWidth: 900
    minimumHeight: 600
    title: "BookWorm"
    color: Theme.background

    Material.theme: Theme.isDark ? Material.Dark : Material.Light
    Material.accent: Theme.primary

    property int currentPage: 0  // 0 library, 1 table, 2 statistics, 3 challenges, 4 series, 5 achievements

    // Coming back to the window is when a person expects to see what another
    // device did. The manager ignores the call when it has just exchanged, so
    // alt-tabbing does not turn into a request per focus.
    onActiveChanged: if (active) syncManager.syncIfStale()

    // Persistence for settings
    Settings {
        id: appSettings
        property alias style: root.appStyle
        property alias language: root.appLanguage
        property alias cardsPerRow: root.libraryCardsPerRow
        property alias priorityEnabled: root.libraryPriorityEnabled
        property alias backupFolder: root.backupFolder
        property alias backupAutomatic: root.backupAutomatic
        property alias backupIntervalValue: root.backupIntervalValue
        property alias backupIntervalUnit: root.backupIntervalUnit
        property alias backupLastRun: root.backupLastRun
    }

    // Returns true when an automatic backup is enabled, a folder is chosen, and the
    // configured interval has elapsed since the last successful run.
    function backupIsDue() {
        if (!root.backupAutomatic || root.backupFolder === "")
            return false;
        if (root.backupLastRun === "")
            return true;

        var last = new Date(root.backupLastRun);
        if (isNaN(last.getTime()))
            return true;   // unreadable timestamp — treat as never backed up

        var due = new Date(last);
        if (root.backupIntervalUnit === "D") {
            due.setDate(due.getDate() + root.backupIntervalValue);
        } else {
            // setMonth/setFullYear do not clamp the day, so 31 January + 1 month
            // rolls over into 3 March and quietly delays the backup. Clamp the day
            // to the target month's length instead.
            var day = due.getDate();
            due.setDate(1);
            if (root.backupIntervalUnit === "M")
                due.setMonth(due.getMonth() + root.backupIntervalValue);
            else
                due.setFullYear(due.getFullYear() + root.backupIntervalValue);
            var daysInMonth = new Date(due.getFullYear(), due.getMonth() + 1, 0).getDate();
            due.setDate(Math.min(day, daysInMonth));
        }

        // A clock set forward and later corrected leaves a timestamp in the future,
        // which would suppress backups until real time caught up. Treat that as due.
        if (last.getTime() > Date.now())
            return true;

        return new Date() >= due;
    }

    function runAutomaticBackup() {
        var folder = root.backupFolder.toString().replace("file://", "");
        var stamp = new Date().toISOString().substring(0, 10);
        var path = folder + "/bookworm-" + stamp + ".zip";
        backupManager.backupTo(path);
    }

    Component.onCompleted: {
        Theme.setTheme(root.appStyle);
        Theme.language = root.appLanguage;

        if (backupIsDue())
            runAutomaticBackup();
    }

    onAppLanguageChanged: Theme.language = root.appLanguage

    // ── Native macOS Menu Bar ──
    Platform.MenuBar {
        Platform.Menu {
            title: "BookWorm"
            Platform.MenuItem {
                text: Theme.tr("About BookWorm")
                onTriggered: aboutDialog.open()
            }
            Platform.MenuSeparator {}
            // Qt maps Ctrl to Cmd on macOS, so this is the standard ⌘, and it
            // shows up as such in the menu.
            Platform.MenuItem {
                text: Theme.tr("Settings") + "…"
                shortcut: "Ctrl+,"
                onTriggered: settingsDialog.open()
            }
            Platform.MenuSeparator {}
            Platform.MenuItem {
                text: Theme.tr("Check for Updates...")
                enabled: false
            }
        }
        Platform.Menu {
            title: Theme.tr("File")
            Platform.MenuItem {
                text: Theme.tr("Import CSV")
                onTriggered: importDialog.open()
            }
            Platform.MenuItem {
                text: Theme.tr("Export CSV")
                onTriggered: exportDialog.open()
            }
            Platform.MenuItem {
                text: Theme.tr("Export notes (Markdown)")
                onTriggered: exportNotesDialog.open()
            }
        }
        Platform.Menu {
            title: Theme.tr("View")
            Platform.Menu {
                title: Theme.tr("Languages")
                Platform.MenuItem {
                    text: "English"
                    checkable: true
                    checked: root.appLanguage === "en"
                    onTriggered: root.appLanguage = "en"
                }
                Platform.MenuItem {
                    text: "Polski"
                    checkable: true
                    checked: root.appLanguage === "pl"
                    onTriggered: root.appLanguage = "pl"
                }
            }
            Platform.Menu {
                title: Theme.tr("Theme")
                Platform.MenuItem {
                    text: Theme.tr("Minimalist Light")
                    checkable: true
                    checked: root.appStyle === "minimalist_light"
                    onTriggered: { root.appStyle = "minimalist_light"; Theme.setTheme("minimalist_light"); }
                }
                Platform.MenuItem {
                    text: Theme.tr("Minimalist Dark")
                    checkable: true
                    checked: root.appStyle === "minimalist_dark"
                    onTriggered: { root.appStyle = "minimalist_dark"; Theme.setTheme("minimalist_dark"); }
                }
                Platform.MenuItem {
                    text: Theme.tr("Classic")
                    checkable: true
                    checked: root.appStyle === "classic"
                    onTriggered: { root.appStyle = "classic"; Theme.setTheme("classic"); }
                }
            }
        }
        Platform.Menu {
            title: Theme.tr("Help")
        }
    }

    // ── About Dialog ──
    Dialog {
        id: aboutDialog
        title: ""
        modal: true
        standardButtons: Dialog.NoButton
        anchors.centerIn: parent
        width: 340
        padding: 0

        Material.theme: Theme.isDark ? Material.Dark : Material.Light

        background: Panel {
            radius: Theme.radiusLarge
            elevated: true
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Item { Layout.preferredHeight: Theme.spacingXL }

            Image {
                Layout.alignment: Qt.AlignHCenter
                source: "qrc:/qt/qml/BookWorm/src/img/png/main_icon.png"
                sourceSize.width: 80
                sourceSize.height: 80
            }

            Item { Layout.preferredHeight: Theme.spacingLarge }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "BookWorm"
                color: Theme.textOnSurface
                font.pixelSize: Theme.fontSizeTitle
                font.bold: true
            }

            Item { Layout.preferredHeight: Theme.spacingMedium }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Theme.tr("Version") + " 1.0.0"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeMedium
            }

            Item { Layout.preferredHeight: Theme.spacingLarge }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Copyright \u00A9 2024\u20132026 Jakub SQTX Sitarczyk."
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Theme.tr("All rights reserved.")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
            }

            Item { Layout.preferredHeight: Theme.spacingXL }

            Button {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: Theme.spacingLarge
                text: "OK"
                flat: true
                Material.foreground: Theme.primary
                onClicked: aboutDialog.close()
            }
        }
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
                    icon.source: "qrc:/qt/qml/BookWorm/src/img/icons/library-view.svg"
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
                    ToolTip.text: Theme.tr("Library")

                    onClicked: {
                        currentPage = 0;
                        stackView.replace(null, bookListComponent);
                    }
                }

                // Table button
                ToolButton {
                    Layout.alignment: Qt.AlignHCenter
                    width: 48; height: 48
                    icon.source: "qrc:/qt/qml/BookWorm/src/img/icons/sheet-view.svg"
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
                    ToolTip.text: Theme.tr("Table")

                    onClicked: {
                        currentPage = 1;
                        stackView.replace(null, bookTableComponent);
                    }
                }

                // Statistics button
                ToolButton {
                    Layout.alignment: Qt.AlignHCenter
                    width: 48; height: 48
                    icon.source: "qrc:/qt/qml/BookWorm/src/img/icons/stat-view.svg"
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
                    ToolTip.text: Theme.tr("Statistics")

                    onClicked: {
                        currentPage = 2;
                        stackView.replace(null, statisticsComponent);
                    }
                }

                // Challenges button
                ToolButton {
                    Layout.alignment: Qt.AlignHCenter
                    width: 48; height: 48
                    icon.source: "qrc:/qt/qml/BookWorm/src/img/icons/challenges.svg"
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
                    ToolTip.text: Theme.tr("Challenges")

                    onClicked: {
                        currentPage = 3;
                        stackView.replace(null, challengesComponent);
                    }
                }

                // Series button
                ToolButton {
                    Layout.alignment: Qt.AlignHCenter
                    width: 48; height: 48
                    icon.source: "qrc:/qt/qml/BookWorm/src/img/icons/book-cover.svg"
                    icon.width: 22; icon.height: 22
                    icon.color: currentPage === 4 ? Theme.primary : Theme.textSecondary

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3; height: 24
                        radius: 2
                        color: Theme.primary
                        visible: currentPage === 4
                    }

                    ToolTip.visible: hovered
                    ToolTip.text: Theme.tr("Series")

                    onClicked: {
                        currentPage = 4;
                        stackView.replace(null, seriesComponent);
                    }
                }

                // Achievements button
                ToolButton {
                    Layout.alignment: Qt.AlignHCenter
                    width: 48; height: 48
                    icon.source: "qrc:/qt/qml/BookWorm/src/img/icons/achievements.svg"
                    icon.width: 22; icon.height: 22
                    icon.color: currentPage === 5 ? Theme.primary : Theme.textSecondary

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3; height: 24
                        radius: 2
                        color: Theme.primary
                        visible: currentPage === 5
                    }

                    ToolTip.visible: hovered
                    ToolTip.text: Theme.tr("Achievements")

                    onClicked: {
                        currentPage = 5;
                        stackView.replace(null, achievementsComponent);
                    }
                }

                Item { Layout.fillHeight: true }

                // Separates navigation (above) from utilities (below); without it
                // the two groups read as one nine-icon list.
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: Theme.spacingSmall
                    width: 24
                    height: 1
                    color: Theme.outline
                }

                // Tags button
                ToolButton {
                    Layout.alignment: Qt.AlignHCenter
                    width: 48; height: 48
                    icon.source: "qrc:/qt/qml/BookWorm/src/img/icons/tags.svg"
                    icon.width: 20; icon.height: 20
                    icon.color: Theme.textSecondary

                    ToolTip.visible: hovered
                    ToolTip.text: Theme.tr("Tags")

                    onClicked: tagsPopup.open()
                }

                // Export button
                ToolButton {
                    Layout.alignment: Qt.AlignHCenter
                    width: 48; height: 48
                    icon.source: "qrc:/qt/qml/BookWorm/src/img/icons/export.svg"
                    icon.width: 20; icon.height: 20
                    icon.color: Theme.textSecondary

                    ToolTip.visible: hovered
                    ToolTip.text: Theme.tr("Export CSV")

                    onClicked: exportDialog.open()
                }

                // Import button
                ToolButton {
                    Layout.alignment: Qt.AlignHCenter
                    width: 48; height: 48
                    icon.source: "qrc:/qt/qml/BookWorm/src/img/icons/inport.svg"
                    icon.width: 20; icon.height: 20
                    icon.color: Theme.textSecondary

                    ToolTip.visible: hovered
                    ToolTip.text: Theme.tr("Import CSV")

                    onClicked: importDialog.open()
                }

                // Settings button
                ToolButton {
                    Layout.alignment: Qt.AlignHCenter
                    width: 48; height: 48
                    icon.source: "qrc:/qt/qml/BookWorm/src/img/icons/settings.svg"
                    icon.width: 22; icon.height: 22
                    icon.color: Theme.textSecondary

                    ToolTip.visible: hovered
                    ToolTip.text: Theme.tr("Settings")

                    onClicked: settingsDialog.open()
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
            userCardsPerRow: root.libraryCardsPerRow
            onUserCardsPerRowChanged: root.libraryCardsPerRow = userCardsPerRow
            priorityEnabled: root.libraryPriorityEnabled
            onPriorityEnabledChanged: root.libraryPriorityEnabled = priorityEnabled
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

    Component {
        id: seriesComponent
        SeriesView {
            onBookSelected: function(bookId) {
                stackView.push(bookDetailsComponent, { bookId: bookId });
            }
        }
    }

    Component {
        id: achievementsComponent
        AchievementsView {}
    }

    // ── Settings ──

    property string appStyle: "classic"
    property string appLanguage: Qt.locale().name.substring(0,2) === "pl" ? "pl" : "en"
    property int libraryCardsPerRow: 6  // default: 6 cards per row (0 = auto)
    property bool libraryPriorityEnabled: true  // default: priority hoisting on
    property string backupFolder: ""
    property bool backupAutomatic: false
    property int backupIntervalValue: 7
    property string backupIntervalUnit: "D"   // "D", "M" or "Y"
    property string backupLastRun: ""          // ISO date of the last successful run

    // Settings live here (Main.qml owns the persisted `Settings` block); the
    // dialog mirrors them and writes back through these handlers.
    SettingsDialog {
        id: settingsDialog

        language: root.appLanguage
        onLanguageChanged: root.appLanguage = language

        appStyle: root.appStyle
        onAppStyleChanged: {
            root.appStyle = appStyle;
            Theme.setTheme(appStyle);
        }

        cardsPerRow: root.libraryCardsPerRow
        onCardsPerRowChanged: root.libraryCardsPerRow = cardsPerRow

        priorityEnabled: root.libraryPriorityEnabled
        onPriorityEnabledChanged: root.libraryPriorityEnabled = priorityEnabled

        backupFolder: root.backupFolder

        backupAutomatic: root.backupAutomatic
        onBackupAutomaticChanged: root.backupAutomatic = backupAutomatic

        backupIntervalValue: root.backupIntervalValue
        onBackupIntervalValueChanged: root.backupIntervalValue = backupIntervalValue

        backupIntervalUnit: root.backupIntervalUnit
        onBackupIntervalUnitChanged: root.backupIntervalUnit = backupIntervalUnit

        backupLastRun: root.backupLastRun

        onChooseBackupFolderRequested: backupFolderDialog.open()
        onBackupRequested: backupSaveDialog.open()
        onRestoreRequested: restoreOpenDialog.open()
        onResetRequested: resetConfirmDialog.open()
        onExportCsvRequested: exportDialog.open()
        onImportCsvRequested: importDialog.open()
        onExportNotesRequested: exportNotesDialog.open()
        onAboutRequested: aboutDialog.open()
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

        background: Panel {
            radius: Theme.radiusCard
            elevated: true
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
                    text: Theme.tr("Tags")
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
                        text: Theme.tr("No tags yet")
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
                    placeholderText: Theme.tr("New tag...")
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

        background: Panel {
            radius: Theme.radiusCard
            elevated: true
        }

        ColumnLayout {
            width: parent.width
            spacing: Theme.spacingMedium

            Text {
                text: Theme.tr("Pick color")
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

        background: Panel {
            radius: Theme.radiusLarge
            elevated: true
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Text {
                Layout.topMargin: Theme.spacingLarge
                Layout.leftMargin: Theme.spacingXL
                text: Theme.tr("Reset Data")
                color: Theme.dangerHover
                font.pixelSize: Theme.fontSizeTitle
                font.bold: true
            }

            Rectangle { Layout.fillWidth: true; Layout.topMargin: Theme.spacingMedium; height: 1; color: Theme.divider }

            Text {
                Layout.fillWidth: true
                Layout.margins: Theme.spacingXL
                text: Theme.tr("Are you sure you want to delete all data? This action cannot be undone.")
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
                    text: Theme.tr("Cancel")
                    flat: true
                    Material.foreground: Theme.textSecondary
                    onClicked: resetConfirmDialog.reject()
                }

                Button {
                    text: "OK"
                    Material.background: Theme.danger
                    Material.foreground: Theme.dangerText
                    onClicked: {
                        bookController.resetAllData();
                        bookController.loadBooks();
                        resetConfirmDialog.close();
                        csvToast.show(Theme.tr("All data has been reset"));
                    }
                }
            }
        }
    }

    // ── CSV Export/Import ──

    FileDialog {
        id: exportDialog
        title: Theme.tr("Export to CSV")
        fileMode: FileDialog.SaveFile
        nameFilters: ["CSV files (*.csv)"]
        defaultSuffix: "csv"
        // "file:///name" is the filesystem ROOT, which macOS does not let us write to.
        // Default into Documents instead.
        currentFolder: StandardPaths.writableLocation(StandardPaths.DocumentsLocation)
        currentFile: currentFolder + "/bookworm_export.csv"

        onAccepted: {
            if (bookController.exportToCsv(selectedFile)) {
                csvToast.show(Theme.tr("Export completed successfully"));
            } else {
                csvToast.show(Theme.tr("Export failed"));
            }
        }
    }

    FileDialog {
        id: exportNotesDialog
        title: Theme.tr("Export notes (Markdown)")
        fileMode: FileDialog.SaveFile
        nameFilters: ["Markdown (*.md)"]
        defaultSuffix: "md"
        currentFolder: StandardPaths.writableLocation(StandardPaths.DocumentsLocation)
        currentFile: currentFolder + "/bookworm_notes.md"

        onAccepted: {
            var n = bookController.exportAllNotesToMarkdown(selectedFile);
            if (n >= 0)
                csvToast.show(Theme.tr("Exported notes for") + " " + n + " " + Theme.tr("books"));
            else
                csvToast.show(Theme.tr("Export failed"));
        }
    }

    FileDialog {
        id: importDialog
        title: Theme.tr("Import from CSV")
        fileMode: FileDialog.OpenFile
        nameFilters: ["CSV files (*.csv)"]

        onAccepted: {
            var count = bookController.importFromCsv(selectedFile);
            if (count >= 0) {
                csvToast.show(Theme.tr("Imported") + " " + count + " " + Theme.tr("books"));
            } else {
                csvToast.show(Theme.tr("Import failed"));
            }
        }
    }

    // ── Backup ──

    FileDialog {
        id: backupSaveDialog
        title: Theme.tr("Save Backup")
        fileMode: FileDialog.SaveFile
        nameFilters: ["ZIP archive (*.zip)"]
        defaultSuffix: "zip"
        // "file:///name" is the filesystem ROOT, which macOS does not let us write to —
        // the save appeared to work and then failed. Prefer the configured backup
        // folder, falling back to Documents.
        currentFolder: root.backupFolder !== ""
                       ? "file://" + root.backupFolder.replace(/\/+$/, "")
                       : StandardPaths.writableLocation(StandardPaths.DocumentsLocation)
        currentFile: currentFolder + "/bookworm-" + Qt.formatDate(new Date(), "yyyy-MM-dd") + ".zip"

        onAccepted: backupManager.backupTo(selectedFile)
    }

    FolderDialog {
        id: backupFolderDialog
        title: Theme.tr("Choose Backup Folder")
        // Strip the scheme once here, the way the CSV paths are handled, so the
        // settings row shows a plain path instead of file:///Users/...
        onAccepted: root.backupFolder = selectedFolder.toString().replace("file://", "")
    }

    // ── Restore ──

    FileDialog {
        id: restoreOpenDialog
        title: Theme.tr("Restore from Backup")
        fileMode: FileDialog.OpenFile
        nameFilters: ["ZIP archive (*.zip)"]
        // "file:///name" is the filesystem ROOT — see backupSaveDialog above. Default
        // to the configured backup folder, falling back to Documents.
        currentFolder: root.backupFolder !== ""
                       ? "file://" + root.backupFolder.replace(/\/+$/, "")
                       : StandardPaths.writableLocation(StandardPaths.DocumentsLocation)

        onAccepted: {
            var info = backupManager.inspectArchive(selectedFile);
            if (!info.valid) {
                csvToast.show(info.error);
                return;
            }
            restoreConfirmDialog.archivePath = selectedFile;
            restoreConfirmDialog.archiveBooks = info.bookCount;
            restoreConfirmDialog.open();
        }
    }

    // ── Restore confirmation dialog ──
    Dialog {
        id: restoreConfirmDialog
        title: ""
        modal: true
        standardButtons: Dialog.NoButton
        closePolicy: Dialog.NoAutoClose
        anchors.centerIn: parent
        width: Math.min(440, parent.width - 48)
        padding: 0

        // Declared here on the Dialog root — properties nested inside the layout
        // below are unreachable from these handlers, the way BookForm.qml learned.
        property string archivePath: ""
        property int archiveBooks: 0
        property string confirmText: ""

        onOpened: confirmText = ""
        onRejected: confirmText = ""

        Material.theme: Theme.isDark ? Material.Dark : Material.Light
        Material.accent: Theme.primary

        background: Panel {
            radius: Theme.radiusLarge
            elevated: true
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Text {
                Layout.topMargin: Theme.spacingLarge
                Layout.leftMargin: Theme.spacingXL
                text: Theme.tr("Restore replaces everything")
                color: Theme.dangerHover
                font.pixelSize: Theme.fontSizeTitle
                font.bold: true
            }

            Rectangle { Layout.fillWidth: true; Layout.topMargin: Theme.spacingMedium; height: 1; color: Theme.divider }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: Theme.spacingXL
                spacing: Theme.spacingSmall

                Text {
                    Layout.fillWidth: true
                    text: Theme.tr("Every book currently in your library will be permanently replaced by the contents of this archive. This action cannot be undone.")
                    color: Theme.textOnSurface
                    font.pixelSize: Theme.fontSizeMedium
                    wrapMode: Text.Wrap
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacingSmall
                    text: Theme.tr("Books now") + ": " + bookController.model.count
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                }

                Text {
                    Layout.fillWidth: true
                    text: Theme.tr("Books in archive") + ": " + restoreConfirmDialog.archiveBooks
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacingSmall
                    text: Theme.tr("Safety backup will be written to") + ": " + backupManager.safetyBackupDir()
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WrapAnywhere
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacingMedium
                    text: Theme.tr("Type %1 to confirm").replace("%1", Theme.tr("RESTORE"))
                    color: Theme.textOnSurface
                    font.pixelSize: Theme.fontSizeSmall
                }

                TextField {
                    id: restoreConfirmField
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    topPadding: 4; bottomPadding: 4
                    font.pixelSize: Theme.fontSizeMedium
                    Material.accent: Theme.primary
                    text: restoreConfirmDialog.confirmText
                    onTextChanged: restoreConfirmDialog.confirmText = text
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.divider }

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Theme.spacingLarge
                spacing: Theme.spacingMedium

                Item { Layout.fillWidth: true }

                Button {
                    text: Theme.tr("Cancel")
                    flat: true
                    Material.foreground: Theme.textSecondary
                    onClicked: restoreConfirmDialog.reject()
                }

                Button {
                    text: Theme.tr("Restore from Backup")
                    enabled: restoreConfirmDialog.confirmText === Theme.tr("RESTORE")
                    opacity: enabled ? 1.0 : 0.4
                    Material.background: Theme.danger
                    Material.foreground: Theme.dangerText
                    onClicked: {
                        var path = restoreConfirmDialog.archivePath;
                        restoreConfirmDialog.close();
                        // Show the overlay, then yield to the event loop before making
                        // the blocking restoreFrom() call — setting visible: true and
                        // calling restoreFrom() on the same line would never paint,
                        // because the event loop never runs between them. The 50ms
                        // delay gives the (separate) render thread a chance to actually
                        // draw and present the frame before the GUI thread freezes for
                        // the duration of the restore.
                        restoreOverlay.visible = true;
                        restoreStartTimer.pendingPath = path;
                        restoreStartTimer.start();
                    }
                }
            }
        }
    }

    // Deferred start for restoreFrom() — see the comment on restoreOverlay.visible
    // above for why this can't just be a direct call.
    Timer {
        id: restoreStartTimer
        interval: 50
        repeat: false
        property string pendingPath: ""
        onTriggered: backupManager.restoreFrom(pendingPath)
    }

    // ── Restore progress overlay ──
    // restoreFrom() runs synchronously on the GUI thread (a background-thread
    // pipeline is a larger change than this warrants). That means once the call
    // starts, the event loop cannot process anything else, including this
    // BusyIndicator's own animation — it will appear frozen for the duration rather
    // than spinning. What matters is that this whole overlay, including the
    // "Restoring…" label, has already been painted (via restoreStartTimer's 50ms
    // yield above) before that freeze begins, so a user watching it does not conclude
    // the app has hung and force-quit mid-load.
    Rectangle {
        id: restoreOverlay
        anchors.fill: parent
        z: 9999
        color: "#B3000000"
        visible: false

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: Theme.spacingMedium

            BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                running: restoreOverlay.visible
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Theme.tr("Restoring…")
                color: "#FFFFFF"
                font.pixelSize: Theme.fontSizeTitle
                font.bold: true
            }
        }
    }

    // ── Restore failure dialog ──
    // Failure messages here (especially the SAFETY BACKUP one) are the user's only
    // path back to their data if the load fails after the schema has already been
    // dropped. A toast fades in ~2.5s and clips multi-line text — this dialog stays
    // open until dismissed, wraps text, and exposes the safety backup path (when the
    // message carries one) in a selectable, copyable field.
    Dialog {
        id: restoreFailureDialog
        title: ""
        modal: true
        standardButtons: Dialog.NoButton
        closePolicy: Dialog.NoAutoClose
        anchors.centerIn: parent
        width: Math.min(520, parent.width - 48)
        padding: 0

        property string message: ""
        // Recognizes every path-bearing failure message restoreFrom() emits:
        // "SAFETY BACKUP: <path>", "(safety backup: <path>)", "(attempted: <path>)".
        // Messages with no recoverable path (e.g. "psql not found") leave this empty
        // and the copy field below simply does not appear.
        readonly property string safetyPath: {
            var m = message.match(/SAFETY BACKUP:\s*(.+?)(?:\n|$)/);
            if (m) return m[1].trim();
            m = message.match(/\(safety backup:\s*(.+?)\)/);
            if (m) return m[1].trim();
            m = message.match(/\(attempted:\s*(.+?)\)/);
            if (m) return m[1].trim();
            return "";
        }

        Material.theme: Theme.isDark ? Material.Dark : Material.Light
        Material.accent: Theme.primary

        background: Panel {
            radius: Theme.radiusLarge
            elevated: true
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Text {
                Layout.topMargin: Theme.spacingLarge
                Layout.leftMargin: Theme.spacingXL
                text: Theme.tr("Restore failed")
                color: Theme.dangerHover
                font.pixelSize: Theme.fontSizeTitle
                font.bold: true
            }

            Rectangle { Layout.fillWidth: true; Layout.topMargin: Theme.spacingMedium; height: 1; color: Theme.divider }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: Theme.spacingXL
                spacing: Theme.spacingSmall

                Flickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(failureMessageText.implicitHeight, 220)
                    clip: true
                    contentWidth: width
                    contentHeight: failureMessageText.implicitHeight
                    ScrollBar.vertical: ScrollBar {}

                    Text {
                        id: failureMessageText
                        width: parent.width
                        text: restoreFailureDialog.message
                        color: Theme.textOnSurface
                        font.pixelSize: Theme.fontSizeMedium
                        wrapMode: Text.WordWrap
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacingMedium
                    spacing: Theme.spacingSmall
                    visible: restoreFailureDialog.safetyPath !== ""

                    Text {
                        Layout.fillWidth: true
                        text: Theme.tr("Safety backup path")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        TextField {
                            id: safetyPathField
                            Layout.fillWidth: true
                            readOnly: true
                            selectByMouse: true
                            text: restoreFailureDialog.safetyPath
                            font.pixelSize: Theme.fontSizeSmall
                            Material.accent: Theme.primary
                        }

                        Button {
                            text: Theme.tr("Copy")
                            flat: true
                            onClicked: {
                                safetyPathField.selectAll();
                                safetyPathField.copy();
                                safetyPathField.deselect();
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.divider }

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Theme.spacingLarge
                spacing: Theme.spacingMedium

                Item { Layout.fillWidth: true }

                Button {
                    text: Theme.tr("Close")
                    Material.background: Theme.primary
                    Material.foreground: Theme.dangerText
                    onClicked: restoreFailureDialog.close()
                }
            }
        }
    }

    Connections {
        target: backupManager
        function onBackupFinished(ok, message) {
            csvToast.show(message);
            if (ok)
                root.backupLastRun = new Date().toISOString();
        }
        function onRestoreFinished(ok, message) {
            restoreOverlay.visible = false;
            if (ok) {
                csvToast.show(message);
                bookController.loadBooks();
                statsProvider.refresh();
            } else {
                restoreFailureDialog.message = message;
                restoreFailureDialog.open();
            }
        }
    }

    // ── Achievements ──
    //
    // Top-right, above everything, and outside the StackView on purpose: an
    // achievement can be earned on any page — the library, the table, a book's
    // own details — and a notification that only appeared on one of them would
    // miss most of the moments it exists for.
    AchievementToast {
        id: achievementToast
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Theme.pageMargin
        anchors.rightMargin: Theme.pageMargin
        z: 1000
    }

    Connections {
        target: achievements
        function onUnlocked(key, title, description, icon) {
            achievementToast.present(title, description, icon);
        }
    }

    // Simple toast notification
    Rectangle {
        id: csvToast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        // Stacks above the undo toast when both are up — they shared this anchor
        // and drew on top of each other.
        anchors.bottomMargin: undoToast.opacity > 0 ? 32 + undoToast.height + Theme.spacingMedium : 32
        width: toastLabel.implicitWidth + 48
        height: 40
        radius: 20
        color: Theme.surface
        border.width: 1
        border.color: Theme.outline
        opacity: 0
        visible: opacity > 0
        layer.enabled: visible
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowBlur: 0.6
            shadowVerticalOffset: 4
        }

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

    // Undo toast — shown after a delete, with an action to restore the book.
    Connections {
        target: bookController
        function onBookDeletedUndoable(title) {
            undoLabel.text = Theme.tr("Deleted") + " \"" + title + "\"";
            undoToast.opacity = 1;
            undoHideTimer.restart();
        }
    }

    Rectangle {
        id: undoToast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 32
        height: 44
        width: undoRow.implicitWidth + 32
        radius: 22
        color: Theme.surface
        border.width: 1
        border.color: Theme.outline
        layer.enabled: visible
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowBlur: 0.6
            shadowVerticalOffset: 4
        }
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 250 } }

        Timer {
            id: undoHideTimer
            interval: 6000
            onTriggered: undoToast.opacity = 0
        }

        Row {
            id: undoRow
            anchors.centerIn: parent
            spacing: Theme.spacingMedium

            Text {
                id: undoLabel
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.textOnSurface
                font.pixelSize: Theme.fontSizeMedium
            }

            Button {
                anchors.verticalCenter: parent.verticalCenter
                text: Theme.tr("Undo")
                flat: true
                Material.foreground: Theme.primary
                onClicked: {
                    undoHideTimer.stop();
                    undoToast.opacity = 0;
                    if (bookController.undoDelete())
                        csvToast.show(Theme.tr("Book restored"));
                }
            }
        }
    }
}
