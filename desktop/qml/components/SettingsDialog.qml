import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import BookWorm

// Settings, rebuilt.
//
// This replaces a 280px popup pinned to the bottom-left corner that stacked
// language, theme, the whole backup configuration, restore and reset into one
// scrolling column. Four categories now sit in a rail on the left and each gets
// a page with room to breathe.
//
// State lives in Main.qml (it owns the `Settings` block that persists it); this
// dialog mirrors it through plain properties and reports changes back by signal,
// so no persistence logic is duplicated here.
Dialog {
    id: root

    // ── Mirrored settings ──
    property string language: "en"
    property string appStyle: "minimalist_dark"
    property int cardsPerRow: 6
    property bool priorityEnabled: true
    property string backupFolder: ""
    property bool backupAutomatic: false
    property int backupIntervalValue: 7
    property string backupIntervalUnit: "D"
    property string backupLastRun: ""

    // ── Actions handled by Main.qml ──
    signal chooseBackupFolderRequested()
    signal backupRequested()
    signal restoreRequested()
    signal resetRequested()
    signal exportCsvRequested()
    signal importCsvRequested()
    signal exportNotesRequested()
    signal aboutRequested()

    property int currentCategory: 0

    // Resolved once here rather than at each use site — the backup and restore
    // pages both gate several controls on these.
    readonly property bool canBackup:  backupManager.pgDumpPath() !== ""
    readonly property bool canRestore: backupManager.psqlPath() !== ""

    readonly property var categories: [
        { key: "General",    icon: "qrc:/qt/qml/BookWorm/src/img/icons/settings.svg" },
        { key: "Appearance", icon: "qrc:/qt/qml/BookWorm/src/img/icons/library-view.svg" },
        { key: "Backup",     icon: "qrc:/qt/qml/BookWorm/src/img/icons/export.svg" },
        { key: "Data",       icon: "qrc:/qt/qml/BookWorm/src/img/icons/sheet-view.svg" }
    ]

    modal: true
    anchors.centerIn: parent
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    width: Math.min(820, parent ? parent.width - Theme.spacingXXL * 2 : 820)
    height: Math.min(600, parent ? parent.height - Theme.spacingXXL * 2 : 600)

    Material.theme: Theme.isDark ? Material.Dark : Material.Light
    Material.accent: Theme.primary

    background: Panel {
        radius: Theme.radiusLarge
        elevated: true
    }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationMedium }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Theme.durationMedium; easing.type: Theme.easeOut }
        }
    }
    exit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.durationFast }
            NumberAnimation { property: "scale"; from: 1; to: 0.98; duration: Theme.durationFast }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ═══════════════════════════════════════════
        // Title bar
        // ═══════════════════════════════════════════
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 60

            Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingXL
                anchors.verticalCenter: parent.verticalCenter
                text: Theme.tr("Settings")
                color: Theme.textOnSurface
                font.pixelSize: Theme.fontSizeTitle
                font.bold: true
                font.letterSpacing: -0.5
            }

            Rectangle {
                id: closeButton
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingLarge
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                height: 32
                radius: 16
                color: closeMouse.containsMouse ? Theme.hover : "transparent"

                Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: closeMouse.containsMouse ? Theme.textOnSurface : Theme.textSecondary
                    font.pixelSize: 13
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.close()
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.outline }

        // ═══════════════════════════════════════════
        // Rail + content
        // ═══════════════════════════════════════════
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // ── Category rail ──
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 196
                color: Theme.isDark ? Qt.darker(Theme.surface, 1.18)
                                    : Qt.darker(Theme.surface, 1.03)

                // Slides between entries instead of jumping, so the eye can follow
                // which category took over. Kept a sibling of the Column so it is
                // not laid out as one of the rows.
                Rectangle {
                    id: railIndicator
                    x: 0
                    y: railColumn.y + root.currentCategory * (40 + Theme.spacingXS)
                    width: 3
                    height: 40
                    radius: 2
                    color: Theme.primary

                    Behavior on y {
                        NumberAnimation { duration: Theme.durationMedium; easing.type: Theme.easeOut }
                    }
                }

                Column {
                    id: railColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: Theme.spacingLarge
                    spacing: Theme.spacingXS

                    Repeater {
                        model: root.categories

                        Rectangle {
                            required property var modelData
                            required property int index

                            readonly property bool isSelected: root.currentCategory === index

                            width: railColumn.width
                            height: 40
                            color: isSelected ? Theme.hover
                                              : (railMouse.containsMouse ? Qt.rgba(Theme.hover.r, Theme.hover.g, Theme.hover.b, 0.5)
                                                                         : "transparent")

                            Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingLarge
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingMedium

                                ToolButton {
                                    anchors.verticalCenter: parent.verticalCenter
                                    focusPolicy: Qt.NoFocus
                                    hoverEnabled: false
                                    background: Item {}
                                    width: 18
                                    height: 18
                                    icon.source: modelData.icon
                                    icon.width: 16
                                    icon.height: 16
                                    icon.color: isSelected ? Theme.primary : Theme.textSecondary
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Theme.tr(modelData.key)
                                    color: isSelected ? Theme.textOnSurface : Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.bold: isSelected

                                    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                                }
                            }

                            MouseArea {
                                id: railMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.currentCategory = index
                            }
                        }
                    }
                }

                // App identity at the foot of the rail — fills what would otherwise
                // be dead space and gives the version a home.
                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingXS

                    Image {
                        Layout.alignment: Qt.AlignHCenter
                        source: "qrc:/qt/qml/BookWorm/src/img/png/main_icon.png"
                        sourceSize.width: 36
                        sourceSize.height: 36
                        opacity: 0.85
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "BookWorm 1.0.0"
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall - 1
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: Theme.tr("About BookWorm")
                        color: aboutMouse.containsMouse ? Theme.primary : Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall - 1
                        font.underline: aboutMouse.containsMouse

                        MouseArea {
                            id: aboutMouse
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.close();
                                root.aboutRequested();
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillHeight: true; width: 1; color: Theme.outline }

            // ── Content pane ──
            Flickable {
                id: contentFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: pageStack.implicitHeight + Theme.spacingXXL * 2
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                // Category pages cross-fade; a hard cut between two dense panes
                // makes the dialog feel like it reloaded.
                opacity: 1
                NumberAnimation {
                    id: pageFade
                    target: contentFlick
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: Theme.durationMedium
                }

                Connections {
                    target: root
                    function onCurrentCategoryChanged() {
                        contentFlick.contentY = 0;
                        pageFade.restart();
                    }
                }

                StackLayout {
                    id: pageStack
                    x: Theme.spacingXXL
                    y: Theme.spacingXXL
                    width: contentFlick.width - Theme.spacingXXL * 2
                    currentIndex: root.currentCategory

                    // ═══════════════════════════════
                    // 0 — General
                    // ═══════════════════════════════
                    ColumnLayout {
                        spacing: Theme.spacingLarge

                        SectionLabel { text: Theme.tr("Language") }

                        Panel {
                            Layout.fillWidth: true
                            Layout.preferredHeight: langColumn.implicitHeight + Theme.spacingMedium * 2

                            ColumnLayout {
                                id: langColumn
                                anchors.fill: parent
                                anchors.margins: Theme.spacingMedium
                                spacing: 0

                                Repeater {
                                    model: [
                                        { key: "en", label: "English",  native: "English" },
                                        { key: "pl", label: "Polski",   native: "Polish"  }
                                    ]

                                    Rectangle {
                                        required property var modelData

                                        readonly property bool isSelected: root.language === modelData.key

                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 44
                                        radius: Theme.radiusControl
                                        color: isSelected ? Theme.hover
                                                          : (langMouse.containsMouse ? Qt.rgba(Theme.hover.r, Theme.hover.g, Theme.hover.b, 0.5)
                                                                                     : "transparent")

                                        Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Theme.spacingLarge
                                            anchors.rightMargin: Theme.spacingLarge
                                            spacing: Theme.spacingMedium

                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.label
                                                color: isSelected ? Theme.textOnSurface : Theme.textSecondary
                                                font.pixelSize: Theme.fontSizeMedium
                                                font.bold: isSelected
                                            }

                                            RadioMark { checked: isSelected }
                                        }

                                        MouseArea {
                                            id: langMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.language = modelData.key
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: Theme.tr("The interface language changes immediately — no restart needed.")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.WordWrap
                        }

                        Item { Layout.fillHeight: true }
                    }

                    // ═══════════════════════════════
                    // 1 — Appearance
                    // ═══════════════════════════════
                    ColumnLayout {
                        spacing: Theme.spacingLarge

                        SectionLabel { text: Theme.tr("APP STYLE") }

                        // Themes are shown, not listed: three swatches of the actual
                        // background / surface / accent beat a radio button labelled
                        // "Classic".
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingMedium

                            Repeater {
                                model: [
                                    { key: "minimalist_light", label: "Minimalist Light" },
                                    { key: "minimalist_dark",  label: "Minimalist Dark"  },
                                    { key: "classic",          label: "Classic"          }
                                ]

                                Panel {
                                    required property var modelData

                                    readonly property bool isSelected: root.appStyle === modelData.key
                                    readonly property var swatch: Theme.previewColors(modelData.key)

                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 132
                                    interactive: true
                                    border.width: isSelected ? 2 : 1
                                    border.color: isSelected ? Theme.primary
                                                             : (hovered ? Theme.primary : Theme.outline)
                                    scale: themeMouse.pressed ? 0.98 : 1.0

                                    Behavior on scale { NumberAnimation { duration: Theme.durationFast } }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: Theme.spacingMedium
                                        spacing: Theme.spacingMedium

                                        // Miniature of the app: background, a surface
                                        // card on it, and the accent as a bar.
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 64
                                            radius: Theme.radiusSmall
                                            color: swatch[0]
                                            border.width: 1
                                            border.color: Theme.outline

                                            Rectangle {
                                                anchors.fill: parent
                                                anchors.margins: 8
                                                radius: 3
                                                color: swatch[1]

                                                Rectangle {
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.top: parent.top
                                                    anchors.margins: 6
                                                    height: 5
                                                    radius: 2.5
                                                    color: swatch[2]
                                                }

                                                Rectangle {
                                                    anchors.left: parent.left
                                                    anchors.top: parent.top
                                                    anchors.topMargin: 17
                                                    anchors.leftMargin: 6
                                                    width: parent.width * 0.55
                                                    height: 4
                                                    radius: 2
                                                    color: Qt.rgba(swatch[2].r, swatch[2].g, swatch[2].b, 0.45)
                                                }
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.spacingSmall

                                            Text {
                                                Layout.fillWidth: true
                                                text: Theme.tr(modelData.label)
                                                color: isSelected ? Theme.textOnSurface : Theme.textSecondary
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.bold: isSelected
                                                elide: Text.ElideRight
                                            }

                                            RadioMark { checked: isSelected; size: 16 }
                                        }
                                    }

                                    MouseArea {
                                        id: themeMouse
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.appStyle = modelData.key
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; Layout.topMargin: Theme.spacingSmall; height: 1; color: Theme.outline }

                        SectionLabel { text: Theme.tr("Library layout") }

                        Panel {
                            Layout.fillWidth: true
                            Layout.preferredHeight: layoutColumn.implicitHeight + Theme.spacingLarge * 2

                            ColumnLayout {
                                id: layoutColumn
                                anchors.fill: parent
                                anchors.margins: Theme.spacingLarge
                                spacing: Theme.spacingLarge

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingMedium

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        Text {
                                            text: Theme.tr("Cards per row")
                                            color: Theme.textOnSurface
                                            font.pixelSize: Theme.fontSizeMedium
                                        }

                                        Text {
                                            text: root.cardsPerRow === 0
                                                  ? Theme.tr("Fitted to the window width")
                                                  : Theme.tr("Fixed number of columns")
                                            color: Theme.textSecondary
                                            font.pixelSize: Theme.fontSizeSmall
                                        }
                                    }

                                    Chip {
                                        text: Theme.tr("Auto")
                                        selected: root.cardsPerRow === 0
                                        onClicked: root.cardsPerRow = root.cardsPerRow === 0 ? 6 : 0
                                    }

                                    Rectangle {
                                        width: 108
                                        height: 32
                                        radius: Theme.radiusControl
                                        color: Theme.surfaceVariant
                                        border.width: 1
                                        border.color: Theme.outline
                                        opacity: root.cardsPerRow === 0 ? 0.4 : 1.0
                                        enabled: root.cardsPerRow !== 0

                                        Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }

                                        StepperButton {
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            symbol: "−"
                                            // More columns = smaller cards.
                                            canStep: root.cardsPerRow < 8 && root.cardsPerRow !== 0
                                            onStepped: root.cardsPerRow += 1
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: root.cardsPerRow > 0 ? root.cardsPerRow : "—"
                                            color: Theme.textOnSurface
                                            font.pixelSize: Theme.fontSizeMedium
                                            font.bold: true
                                        }

                                        StepperButton {
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            symbol: "+"
                                            canStep: root.cardsPerRow > 2
                                            onStepped: root.cardsPerRow -= 1
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
                                            text: Theme.tr("Flagged books get their own section on top")
                                            color: Theme.textSecondary
                                            font.pixelSize: Theme.fontSizeSmall
                                        }
                                    }

                                    Switch {
                                        checked: root.priorityEnabled
                                        Material.accent: Theme.primary
                                        onToggled: root.priorityEnabled = checked
                                    }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }

                    // ═══════════════════════════════
                    // 2 — Backup
                    // ═══════════════════════════════
                    ColumnLayout {
                        spacing: Theme.spacingLarge

                        SectionLabel { text: Theme.tr("Backup") }

                        Text {
                            Layout.fillWidth: true
                            text: Theme.tr("A backup is a ZIP with the full database, every cover image and a manifest. CSV export is not a backup.")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.WordWrap
                            lineHeight: 1.3
                        }

                        Panel {
                            Layout.fillWidth: true
                            Layout.preferredHeight: backupColumn.implicitHeight + Theme.spacingLarge * 2

                            ColumnLayout {
                                id: backupColumn
                                anchors.fill: parent
                                anchors.margins: Theme.spacingLarge
                                spacing: Theme.spacingLarge

                                // Folder
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingMedium

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        Text {
                                            text: Theme.tr("Backup folder")
                                            color: Theme.textOnSurface
                                            font.pixelSize: Theme.fontSizeMedium
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: root.backupFolder !== "" ? root.backupFolder
                                                                           : Theme.tr("No folder chosen")
                                            color: root.backupFolder !== "" ? Theme.textSecondary : Theme.textSecondary
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.italic: root.backupFolder === ""
                                            elide: Text.ElideMiddle
                                        }
                                    }

                                    AppButton {
                                        variant: "outline"
                                        text: Theme.tr("Change")
                                        onClicked: root.chooseBackupFolderRequested()
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.outline }

                                // Automatic
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingMedium

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        Text {
                                            text: Theme.tr("Automatic backup")
                                            color: Theme.textOnSurface
                                            font.pixelSize: Theme.fontSizeMedium
                                        }

                                        Text {
                                            text: root.backupFolder === ""
                                                  ? Theme.tr("Choose a folder to enable automatic backup")
                                                  : Theme.tr("Checked once at every app start")
                                            color: Theme.textSecondary
                                            font.pixelSize: Theme.fontSizeSmall
                                        }
                                    }

                                    Switch {
                                        checked: root.backupAutomatic
                                        enabled: root.backupFolder !== ""
                                        Material.accent: Theme.primary
                                        onToggled: root.backupAutomatic = checked
                                    }
                                }

                                // Interval
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingMedium
                                    opacity: root.backupAutomatic && root.backupFolder !== "" ? 1.0 : 0.45
                                    enabled: root.backupAutomatic && root.backupFolder !== ""

                                    Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }

                                    Text {
                                        Layout.fillWidth: true
                                        text: Theme.tr("Every")
                                        color: Theme.textOnSurface
                                        font.pixelSize: Theme.fontSizeMedium
                                    }

                                    Rectangle {
                                        width: 96
                                        height: 32
                                        radius: Theme.radiusControl
                                        color: Theme.surfaceVariant
                                        border.width: 1
                                        border.color: Theme.outline

                                        StepperButton {
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            symbol: "−"
                                            canStep: root.backupIntervalValue > 1
                                            onStepped: root.backupIntervalValue -= 1
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: root.backupIntervalValue
                                            color: Theme.textOnSurface
                                            font.pixelSize: Theme.fontSizeMedium
                                            font.bold: true
                                        }

                                        StepperButton {
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            symbol: "+"
                                            canStep: root.backupIntervalValue < 99
                                            onStepped: root.backupIntervalValue += 1
                                        }
                                    }

                                    Row {
                                        spacing: Theme.spacingSmall

                                        Repeater {
                                            model: [
                                                { key: "D", label: "Days"   },
                                                { key: "M", label: "Months" },
                                                { key: "Y", label: "Years"  }
                                            ]

                                            Chip {
                                                required property var modelData
                                                text: Theme.tr(modelData.label)
                                                selected: root.backupIntervalUnit === modelData.key
                                                onClicked: root.backupIntervalUnit = modelData.key
                                            }
                                        }
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.outline }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingMedium

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.backupLastRun !== ""
                                              ? Theme.tr("Last backup") + ": " +
                                                Qt.formatDateTime(new Date(root.backupLastRun), "yyyy-MM-dd hh:mm")
                                              : Theme.tr("No backup yet")
                                        color: Theme.textSecondary
                                        font.pixelSize: Theme.fontSizeSmall
                                    }

                                    AppButton {
                                        variant: "primary"
                                        text: Theme.tr("Back Up Now")
                                        enabledState: root.canBackup
                                        onClicked: {
                                            root.close();
                                            root.backupRequested();
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: !root.canBackup
                                    text: Theme.tr("pg_dump not found — backup unavailable")
                                    color: Theme.error
                                    font.pixelSize: Theme.fontSizeSmall
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        SectionLabel { Layout.topMargin: Theme.spacingSmall; text: Theme.tr("Restore"); accent: Theme.danger }

                        Panel {
                            Layout.fillWidth: true
                            Layout.preferredHeight: restoreColumn.implicitHeight + Theme.spacingLarge * 2
                            border.color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.45)

                            ColumnLayout {
                                id: restoreColumn
                                anchors.fill: parent
                                anchors.margins: Theme.spacingLarge
                                spacing: Theme.spacingMedium

                                Text {
                                    Layout.fillWidth: true
                                    text: Theme.tr("Restoring replaces your entire library with the contents of an archive. A safety backup is taken first.")
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                    wrapMode: Text.WordWrap
                                    lineHeight: 1.3
                                }

                                AppButton {
                                    Layout.alignment: Qt.AlignRight
                                    variant: "danger"
                                    text: Theme.tr("Restore from Backup")
                                    enabledState: root.canRestore
                                    onClicked: {
                                        root.close();
                                        root.restoreRequested();
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: !root.canRestore
                                    text: Theme.tr("psql not found — restore unavailable")
                                    color: Theme.error
                                    font.pixelSize: Theme.fontSizeSmall
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }

                    // ═══════════════════════════════
                    // 3 — Data
                    // ═══════════════════════════════
                    ColumnLayout {
                        spacing: Theme.spacingLarge

                        SectionLabel { text: Theme.tr("Import and export") }

                        Panel {
                            Layout.fillWidth: true
                            Layout.preferredHeight: dataColumn.implicitHeight + Theme.spacingLarge * 2

                            ColumnLayout {
                                id: dataColumn
                                anchors.fill: parent
                                anchors.margins: Theme.spacingLarge
                                spacing: Theme.spacingLarge

                                Repeater {
                                    model: [
                                        { title: "Export CSV",
                                          hint:  "Books and their fields as a spreadsheet. Quotes, highlights and sessions are not included.",
                                          action: "export" },
                                        { title: "Import CSV",
                                          hint:  "Add books from a CSV file. Existing books are kept.",
                                          action: "import" },
                                        { title: "Export notes (Markdown)",
                                          hint:  "Quotes, highlights, summaries and reviews for the whole library in one file.",
                                          action: "notes" }
                                    ]

                                    RowLayout {
                                        required property var modelData
                                        required property int index

                                        Layout.fillWidth: true
                                        spacing: Theme.spacingMedium

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0

                                            Text {
                                                text: Theme.tr(modelData.title)
                                                color: Theme.textOnSurface
                                                font.pixelSize: Theme.fontSizeMedium
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: Theme.tr(modelData.hint)
                                                color: Theme.textSecondary
                                                font.pixelSize: Theme.fontSizeSmall
                                                wrapMode: Text.WordWrap
                                            }
                                        }

                                        AppButton {
                                            variant: "outline"
                                            text: Theme.tr(modelData.action === "import" ? "Import" : "Export")
                                            onClicked: {
                                                root.close();
                                                if (modelData.action === "export")      root.exportCsvRequested();
                                                else if (modelData.action === "import") root.importCsvRequested();
                                                else                                    root.exportNotesRequested();
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        SectionLabel { Layout.topMargin: Theme.spacingSmall; text: Theme.tr("Danger zone"); accent: Theme.danger }

                        Panel {
                            Layout.fillWidth: true
                            Layout.preferredHeight: resetRow.implicitHeight + Theme.spacingLarge * 2
                            border.color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.45)

                            RowLayout {
                                id: resetRow
                                anchors.fill: parent
                                anchors.margins: Theme.spacingLarge
                                spacing: Theme.spacingMedium

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    Text {
                                        text: Theme.tr("Reset All Data")
                                        color: Theme.textOnSurface
                                        font.pixelSize: Theme.fontSizeMedium
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: Theme.tr("Deletes every book, tag, quote, challenge and reading session. This cannot be undone.")
                                        color: Theme.textSecondary
                                        font.pixelSize: Theme.fontSizeSmall
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                AppButton {
                                    variant: "danger"
                                    text: Theme.tr("Reset")
                                    onClicked: {
                                        root.close();
                                        root.resetRequested();
                                    }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.outline }

        // ═══════════════════════════════════════════
        // Footer
        // ═══════════════════════════════════════════
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Theme.spacingLarge
            spacing: Theme.spacingMedium

            Text {
                Layout.fillWidth: true
                text: Theme.tr("Changes are saved as you make them")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
            }

            AppButton {
                variant: "primary"
                text: Theme.tr("Close")
                onClicked: root.close()
            }
        }
    }

    // ── Small pieces used only by this dialog ──

    component RadioMark: Rectangle {
        property bool checked: false
        property int size: 18

        width: size
        height: size
        radius: size / 2
        color: "transparent"
        border.width: 2
        border.color: checked ? Theme.primary : Theme.textSecondary

        Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

        Rectangle {
            anchors.centerIn: parent
            width: parent.checked ? parent.size * 0.55 : 0
            height: width
            radius: width / 2
            color: Theme.primary

            Behavior on width {
                NumberAnimation { duration: Theme.durationFast; easing.type: Theme.easeBack }
            }
        }
    }

    component StepperButton: Rectangle {
        property string symbol: "+"
        property bool canStep: true

        signal stepped()

        width: 32
        height: 30
        radius: Theme.radiusSmall
        color: stepMouse.containsMouse && canStep ? Theme.hover : "transparent"
        opacity: canStep ? 1.0 : 0.3

        Behavior on color { ColorAnimation { duration: Theme.durationFast } }

        Text {
            anchors.centerIn: parent
            text: parent.symbol
            color: Theme.textOnSurface
            font.pixelSize: 16
            font.bold: true
        }

        MouseArea {
            id: stepMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: parent.canStep
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.stepped()
        }
    }
}
