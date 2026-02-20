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

                // App icon at bottom
                Image {
                    Layout.alignment: Qt.AlignHCenter
                    source: "qrc:/qt/qml/WormBook/src/img/png/main_icon.png"
                    sourceSize.width: 36
                    sourceSize.height: 36
                    fillMode: Image.PreserveAspectFit
                }
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
