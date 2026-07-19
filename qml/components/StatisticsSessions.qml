import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtCharts
import BookWorm

Item {
    id: sessionsPage

    readonly property var dayLabels: Theme.getDayLabels()
    // Backend returns weekday as 0 = Sunday ... 6 = Saturday. The UI wants
    // Monday-first order, so this maps display index -> backend weekday.
    readonly property var mondayFirstOrder: [1, 2, 3, 4, 5, 6, 0]

    // Whether any session data exists at all, across every section.
    readonly property bool hasAnyData: statsProvider.sessionPagesTotal > 0
                                        || statsProvider.recentSessions.length > 0

    // ── Pages-per-day chart data ──
    readonly property var dailyDateLabels: {
        var data = statsProvider.pagesPerDay;
        var out = [];
        for (var i = 0; i < data.length; i++)
            out.push(Qt.formatDate(data[i].date, "MM-dd"));
        return out;
    }
    readonly property var dailyPagesValues: {
        var data = statsProvider.pagesPerDay;
        var out = [];
        for (var i = 0; i < data.length; i++)
            out.push(data[i].pages);
        return out;
    }
    readonly property int dailyMaxPages: {
        var data = statsProvider.pagesPerDay;
        var m = 0;
        for (var i = 0; i < data.length; i++)
            if (data[i].pages > m) m = data[i].pages;
        return m;
    }

    // ── Weekday distribution data ──
    // Build all seven slots first (index = backend weekday, 0 = Sunday), then
    // populate from the returned list. Indexing the returned list positionally
    // would silently misassign pages to the wrong day whenever one day is missing.
    readonly property var weekdaySlots: {
        var slots = [0, 0, 0, 0, 0, 0, 0];
        var data = statsProvider.pagesByWeekday;
        for (var i = 0; i < data.length; i++) {
            var entry = data[i];
            if (entry.weekday >= 0 && entry.weekday <= 6)
                slots[entry.weekday] = entry.pages;
        }
        return slots;
    }
    readonly property int weekdayMaxPages: {
        var m = 0;
        for (var i = 0; i < weekdaySlots.length; i++)
            if (weekdaySlots[i] > m) m = weekdaySlots[i];
        return m;
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: mainColumn.implicitHeight
        clip: true
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: mainColumn
            width: parent.width
            spacing: Theme.spacingLarge

            // ═══════════════════════════════════
            // Audio mode filter — always visible, so a filter that matches nothing
            // can still be cleared without leaving the tab.
            // ═══════════════════════════════════
            Row {
                Layout.leftMargin: Theme.spacingXL
                Layout.rightMargin: Theme.spacingXL
                Layout.topMargin: Theme.spacingXL
                spacing: Theme.spacingSmall

                Repeater {
                    model: [
                        { key: "All",               value: "" },
                        { key: "Standard",          value: "none" },
                        { key: "Audiobook",         value: "audiobook" },
                        { key: "Audiobook Support", value: "audiobook_support" }
                    ]

                    Rectangle {
                        required property var modelData

                        readonly property bool isSelected:
                            statsProvider.sessionAudioFilter === modelData.value

                        width: audioFilterText.implicitWidth + Theme.spacingLarge
                        height: 28
                        radius: 14
                        color: isSelected ? Theme.primary : Theme.surfaceVariant
                        border.width: 1
                        border.color: isSelected ? "transparent" : Theme.divider

                        Text {
                            id: audioFilterText
                            anchors.centerIn: parent
                            text: Theme.tr(modelData.key)
                            color: parent.isSelected ? Theme.textOnPrimary : Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: parent.isSelected
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: statsProvider.sessionAudioFilter = modelData.value
                        }
                    }
                }
            }

            // ═══════════════════════════════════
            // Section 1: Summary Cards
            // ═══════════════════════════════════
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXL
                Layout.rightMargin: Theme.spacingXL
                Layout.topMargin: Theme.spacingXL
                spacing: Theme.spacingMedium
                visible: sessionsPage.hasAnyData

                StatCard {
                    Layout.fillWidth: true
                    value: statsProvider.currentStreak + " " + Theme.tr("days")
                    label: Theme.tr("Current streak")
                    accent: Theme.statusReading
                }

                StatCard {
                    Layout.fillWidth: true
                    value: statsProvider.longestStreak + " " + Theme.tr("days")
                    label: Theme.tr("Longest streak")
                    accent: Theme.statusRead
                }

                StatCard {
                    Layout.fillWidth: true
                    value: statsProvider.sessionPagesTotal
                    label: Theme.tr("Pages read")
                    accent: Theme.secondary
                }

                StatCard {
                    Layout.fillWidth: true
                    value: statsProvider.meanPagesPerReadingDay.toFixed(1)
                    label: Theme.tr("Pages per reading day")
                    accent: Theme.statusPlanned
                }
            }

            // Empty state for the whole tab (no sessions recorded at all yet)
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXL
                Layout.rightMargin: Theme.spacingXL
                Layout.topMargin: Theme.spacingXL
                visible: !sessionsPage.hasAnyData
                implicitHeight: emptyColumn.implicitHeight + Theme.spacingLarge * 2
                radius: Theme.radiusMedium
                color: Theme.surface

                ColumnLayout {
                    id: emptyColumn
                    anchors.centerIn: parent
                    spacing: Theme.spacingSmall

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: Theme.tr("No reading sessions yet")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeLarge
                        font.bold: true
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: Theme.tr("Sessions are recorded when you add pages")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                        font.italic: true
                    }
                }
            }

            // ═══════════════════════════════════
            // Section 2: Pages Per Day Chart
            // ═══════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXL
                Layout.rightMargin: Theme.spacingXL
                Layout.preferredHeight: 320
                radius: Theme.radiusMedium
                color: Theme.surface

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingSmall

                    Text {
                        text: Theme.tr("Pages per day")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeMedium
                        font.bold: true
                    }

                    ChartView {
                        id: dailyChartView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: sessionsPage.dailyPagesValues.length > 0
                        antialiasing: true
                        backgroundColor: "transparent"
                        plotAreaColor: "transparent"
                        legend.visible: false
                        animationOptions: ChartView.SeriesAnimations
                        margins.top: 0
                        margins.bottom: 0
                        margins.left: 0
                        margins.right: 0

                        BarCategoryAxis {
                            id: dailyCategoryAxis
                            categories: sessionsPage.dailyDateLabels
                            labelsColor: Theme.textSecondary
                            labelsFont.pixelSize: 10
                            gridVisible: false
                            lineVisible: false
                        }

                        ValueAxis {
                            id: dailyValueAxis
                            min: 0
                            max: Math.max(5, sessionsPage.dailyMaxPages + 1)
                            tickCount: 6
                            labelFormat: "%d"
                            labelsColor: Theme.textSecondary
                            labelsFont.pixelSize: 11
                            gridLineColor: Theme.divider
                            lineVisible: false
                        }

                        BarSeries {
                            axisX: dailyCategoryAxis
                            axisY: dailyValueAxis
                            barWidth: 0.6

                            BarSet {
                                label: Theme.tr("Pages per day")
                                color: Theme.statusReading
                                borderColor: "transparent"
                                values: sessionsPage.dailyPagesValues
                            }
                        }
                    }

                    // Empty state
                    Text {
                        visible: sessionsPage.dailyPagesValues.length === 0
                        Layout.fillHeight: true
                        Layout.alignment: Qt.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: Theme.tr("No reading sessions yet")
                        color: Theme.textSecondary
                        font.italic: true
                    }
                }
            }

            // ═══════════════════════════════════
            // Section 3: Weekday Distribution
            // ═══════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXL
                Layout.rightMargin: Theme.spacingXL
                implicitHeight: weekdayColumn.implicitHeight + Theme.spacingLarge * 2
                radius: Theme.radiusMedium
                color: Theme.surface

                ColumnLayout {
                    id: weekdayColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    Text {
                        text: Theme.tr("By weekday")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeMedium
                        font.bold: true
                    }

                    Repeater {
                        model: 7

                        RowLayout {
                            required property int index
                            readonly property int sourceWeekday: sessionsPage.mondayFirstOrder[index]
                            readonly property int pages: sessionsPage.weekdaySlots[sourceWeekday]

                            Layout.fillWidth: true
                            spacing: Theme.spacingMedium

                            Text {
                                Layout.preferredWidth: 40
                                text: sessionsPage.dayLabels[index]
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                horizontalAlignment: Text.AlignRight
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 20
                                radius: 4
                                color: Theme.surfaceVariant

                                Rectangle {
                                    width: sessionsPage.weekdayMaxPages > 0
                                           ? Math.max(4, parent.width * (pages / sessionsPage.weekdayMaxPages))
                                           : 4
                                    height: parent.height
                                    radius: 4
                                    color: Theme.statusReading

                                    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                }
                            }

                            Text {
                                Layout.preferredWidth: 35
                                text: pages
                                color: Theme.textOnSurface
                                font.pixelSize: Theme.fontSizeMedium
                                font.bold: true
                            }
                        }
                    }

                    // Empty state
                    Text {
                        visible: sessionsPage.weekdayMaxPages === 0
                        text: Theme.tr("No reading sessions yet")
                        color: Theme.textSecondary
                        font.italic: true
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: Theme.spacingMedium
                    }
                }
            }

            // ═══════════════════════════════════
            // Section 4: Recent Sessions
            // ═══════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXL
                Layout.rightMargin: Theme.spacingXL
                implicitHeight: recentColumn.implicitHeight + Theme.spacingLarge * 2
                radius: Theme.radiusMedium
                color: Theme.surface

                ColumnLayout {
                    id: recentColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    Text {
                        text: Theme.tr("Recent sessions")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeMedium
                        font.bold: true
                    }

                    Repeater {
                        model: statsProvider.recentSessions

                        ColumnLayout {
                            id: sessionRow
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: Theme.spacingSmall

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingMedium

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    RowLayout {
                                        spacing: Theme.spacingSmall

                                        Text {
                                            Layout.fillWidth: true
                                            text: sessionRow.modelData.title
                                            color: Theme.textOnSurface
                                            font.pixelSize: Theme.fontSizeMedium
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }

                                        // Subtle label for book-completion sessions
                                        Rectangle {
                                            visible: sessionRow.modelData.source === "completion"
                                            implicitWidth: completionLabel.implicitWidth + Theme.spacingMedium
                                            implicitHeight: completionLabel.implicitHeight + Theme.spacingSmall
                                            radius: Theme.radiusSmall
                                            color: Theme.statusRead

                                            Text {
                                                id: completionLabel
                                                anchors.centerIn: parent
                                                text: Theme.tr("Completed")
                                                color: Theme.textOnPrimary
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.bold: true
                                            }
                                        }
                                    }

                                    Text {
                                        text: sessionRow.modelData.author + " • "
                                              + Qt.formatDate(sessionRow.modelData.date, "yyyy-MM-dd")
                                        color: Theme.textSecondary
                                        font.pixelSize: Theme.fontSizeSmall
                                    }
                                }

                                Text {
                                    text: sessionRow.modelData.pages + " " + Theme.tr("pages")
                                    color: Theme.primary
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.bold: true
                                }

                                ToolButton {
                                    text: "✕"
                                    font.pixelSize: 12
                                    Material.foreground: Theme.error
                                    onClicked: {
                                        bookController.deleteReadingSession(sessionRow.modelData.id);
                                        statsProvider.refresh();
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Theme.divider
                                visible: sessionRow.index < statsProvider.recentSessions.length - 1
                            }
                        }
                    }

                    // Empty state
                    Text {
                        visible: statsProvider.recentSessions.length === 0
                        text: Theme.tr("No reading sessions yet")
                        color: Theme.textSecondary
                        font.italic: true
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: Theme.spacingMedium
                    }
                }
            }

            // Bottom spacer
            Item { Layout.preferredHeight: Theme.spacingXL }
        }
    }

    // ── Inline component: Stat Card (matches StatisticsOverview.qml) ──
    component StatCard: Rectangle {
        property var value: 0
        property string label: ""
        property color accent: Theme.primary

        implicitHeight: 90
        radius: Theme.radiusMedium
        color: Theme.surface

        ColumnLayout {
            anchors.centerIn: parent
            spacing: Theme.spacingSmall

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: String(value)
                color: accent
                font.pixelSize: 30
                font.bold: true
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: label
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
}
