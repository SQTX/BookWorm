import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtCharts
import BookWorm

Item {
    id: sessionsPage

    readonly property var dayLabels: Theme.getDayLabels()

    // Width of the pages label at its widest (3-digit count), so every row reserves
    // the same space and the Edit button never shifts with the digit count.
    readonly property real pagesLabelWidth: pagesLabelMetric.width
    TextMetrics {
        id: pagesLabelMetric
        font.pixelSize: Theme.fontSizeMedium
        font.bold: true
        text: "999 " + Theme.tr("pages")
    }
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

    // ── Reading heatmap (GitHub-style contribution calendar) ──
    // A selected year spans Jan–Dec; "all time" spans the trailing 53 weeks.
    // Columns are weeks (Monday-first), rows are weekdays.
    function heatmapFmt(d) { return Qt.formatDate(d, "yyyy-MM-dd"); }

    readonly property var heatmapWeeks: {
        var year = statsProvider.selectedYear;
        var start, end;
        if (year > 0) {
            start = new Date(year, 0, 1);
            end = new Date(year, 11, 31);
        } else {
            end = new Date(); end.setHours(0, 0, 0, 0);
            start = new Date(end); start.setDate(end.getDate() - 364);
        }
        // Snap the grid's first column back to the Monday on/before the start.
        var mondayOffset = (start.getDay() + 6) % 7;
        var gridStart = new Date(start);
        gridStart.setDate(start.getDate() - mondayOffset);

        var map = {};
        var data = statsProvider.heatmapDays;
        for (var i = 0; i < data.length; i++)
            map[heatmapFmt(data[i].date)] = data[i].pages;

        var weeks = [];
        var cur = new Date(gridStart);
        while (cur <= end) {
            var week = [];
            for (var d = 0; d < 7; d++) {
                var ds = heatmapFmt(cur);
                week.push({ ds: ds,
                            pages: (map[ds] || 0),
                            inRange: (cur >= start && cur <= end) });
                cur.setDate(cur.getDate() + 1);
            }
            weeks.push(week);
        }
        return weeks;
    }

    readonly property int heatmapMax: {
        var m = 0;
        var data = statsProvider.heatmapDays;
        for (var i = 0; i < data.length; i++)
            if (data[i].pages > m) m = data[i].pages;
        return m;
    }

    // Colour a cell by reading intensity; four buckets of the reading accent.
    function heatColor(pages, inRange) {
        if (!inRange) return "transparent";
        if (pages <= 0) return Theme.surfaceVariant;
        var maxP = heatmapMax > 0 ? heatmapMax : 1;
        var t = pages / maxP;
        var a = t < 0.25 ? 0.35 : t < 0.5 ? 0.55 : t < 0.75 ? 0.78 : 1.0;
        var c = Theme.statusReading;
        return Qt.rgba(c.r, c.g, c.b, a);
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
                Layout.leftMargin: Theme.pageMargin
                Layout.rightMargin: Theme.pageMargin
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
                Layout.leftMargin: Theme.pageMargin
                Layout.rightMargin: Theme.pageMargin
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

            // ═══════════════════════════════════
            // Completion projection (currently-reading books)
            // ═══════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.pageMargin
                Layout.rightMargin: Theme.pageMargin
                Layout.topMargin: Theme.spacingXL
                visible: statsProvider.readingProjections.length > 0
                implicitHeight: projectionColumn.implicitHeight + Theme.spacingLarge * 2
                radius: Theme.radiusCard
                color: Theme.surface

                ColumnLayout {
                    id: projectionColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    Text {
                        text: Theme.tr("Completion projection")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeMedium
                        font.bold: true
                    }

                    Repeater {
                        model: statsProvider.readingProjections

                        ColumnLayout {
                            id: projRow
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

                                    Text {
                                        Layout.fillWidth: true
                                        text: projRow.modelData.title
                                        color: Theme.textOnSurface
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: projRow.modelData.author + "  ·  "
                                              + projRow.modelData.pagesLeft + " " + Theme.tr("pages left")
                                        color: Theme.textSecondary
                                        font.pixelSize: Theme.fontSizeSmall
                                    }
                                }

                                // Right side: estimate or "not enough data"
                                ColumnLayout {
                                    Layout.alignment: Qt.AlignRight
                                    spacing: 2
                                    visible: projRow.modelData.hasEstimate

                                    Text {
                                        Layout.alignment: Qt.AlignRight
                                        text: "≈ " + Qt.formatDate(projRow.modelData.finishDate, "yyyy-MM-dd")
                                        color: Theme.primary
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.bold: true
                                    }

                                    Text {
                                        Layout.alignment: Qt.AlignRight
                                        text: Theme.tr("in") + " " + projRow.modelData.daysLeft + " "
                                              + Theme.tr("days") + "  ·  ~"
                                              + projRow.modelData.pacePerDay.toFixed(0) + " " + Theme.tr("pg/day")
                                        color: Theme.textSecondary
                                        font.pixelSize: Theme.fontSizeSmall
                                    }
                                }

                                Text {
                                    Layout.alignment: Qt.AlignRight
                                    visible: !projRow.modelData.hasEstimate
                                    text: Theme.tr("Not enough data to estimate")
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.italic: true
                                }
                            }

                            // Progress bar
                            Rectangle {
                                Layout.fillWidth: true
                                height: 6
                                radius: 3
                                color: Theme.surfaceVariant

                                Rectangle {
                                    width: projRow.modelData.pageCount > 0
                                           ? parent.width * Math.min(projRow.modelData.currentPage
                                                                     / projRow.modelData.pageCount, 1.0)
                                           : 0
                                    height: parent.height
                                    radius: 3
                                    color: Theme.statusReading
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Theme.divider
                                visible: projRow.index < statsProvider.readingProjections.length - 1
                            }
                        }
                    }
                }
            }

            // Empty state for the whole tab (no sessions recorded at all yet)
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.pageMargin
                Layout.rightMargin: Theme.pageMargin
                Layout.topMargin: Theme.spacingXL
                visible: !sessionsPage.hasAnyData
                implicitHeight: emptyColumn.implicitHeight + Theme.spacingLarge * 2
                radius: Theme.radiusCard
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
                Layout.leftMargin: Theme.pageMargin
                Layout.rightMargin: Theme.pageMargin
                Layout.preferredHeight: 320
                radius: Theme.radiusCard
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
                Layout.leftMargin: Theme.pageMargin
                Layout.rightMargin: Theme.pageMargin
                implicitHeight: weekdayColumn.implicitHeight + Theme.spacingLarge * 2
                radius: Theme.radiusCard
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
                                    color: weekdayBarHover.containsMouse
                                           ? Qt.lighter(Theme.statusReading, 1.25) : Theme.statusReading

                                    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }

                                MouseArea {
                                    id: weekdayBarHover
                                    anchors.fill: parent
                                    hoverEnabled: true
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
            // Section 3b: Reading activity heatmap
            // ═══════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.pageMargin
                Layout.rightMargin: Theme.pageMargin
                visible: statsProvider.heatmapDays.length > 0
                implicitHeight: heatmapColumn.implicitHeight + Theme.spacingLarge * 2
                radius: Theme.radiusCard
                color: Theme.surface

                readonly property real cell: 13
                readonly property real cellGap: 3

                ColumnLayout {
                    id: heatmapColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    Text {
                        text: Theme.tr("Reading activity")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeMedium
                        font.bold: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        // Weekday labels (Mon/Wed/Fri)
                        Column {
                            spacing: heatmapColumn.parent.cellGap
                            Repeater {
                                model: 7
                                Text {
                                    required property int index
                                    width: 28
                                    height: heatmapColumn.parent.cell
                                    text: index % 2 === 1 ? sessionsPage.dayLabels[index] : ""
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall - 2
                                    horizontalAlignment: Text.AlignRight
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }

                        // Weeks grid (scrolls horizontally if it overflows)
                        Flickable {
                            Layout.fillWidth: true
                            Layout.preferredHeight: heatmapColumn.parent.cell * 7
                                                    + heatmapColumn.parent.cellGap * 6
                            contentWidth: weeksRow.width
                            contentHeight: height
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            flickableDirection: Flickable.HorizontalFlick

                            Row {
                                id: weeksRow
                                spacing: heatmapColumn.parent.cellGap

                                Repeater {
                                    model: sessionsPage.heatmapWeeks

                                    Column {
                                        required property var modelData
                                        spacing: heatmapColumn.parent.cellGap

                                        Repeater {
                                            model: parent.modelData

                                            Rectangle {
                                                required property var modelData
                                                width: heatmapColumn.parent.cell
                                                height: heatmapColumn.parent.cell
                                                radius: 2
                                                color: sessionsPage.heatColor(modelData.pages, modelData.inRange)
                                                // Pop the hovered day and outline it.
                                                z: cellHover.containsMouse ? 1 : 0
                                                scale: cellHover.containsMouse && modelData.inRange ? 1.35 : 1.0
                                                border.width: cellHover.containsMouse && modelData.inRange ? 1 : 0
                                                border.color: Theme.textOnSurface
                                                Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                                                ToolTip.visible: cellHover.containsMouse && modelData.inRange
                                                ToolTip.text: modelData.ds + ": " + modelData.pages + " " + Theme.tr("pages")

                                                MouseArea {
                                                    id: cellHover
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Legend
                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 4

                        Text {
                            text: Theme.tr("Less")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall - 1
                        }
                        Repeater {
                            model: [0, 0.35, 0.55, 0.78, 1.0]
                            Rectangle {
                                required property var modelData
                                width: 11; height: 11; radius: 2
                                color: modelData === 0
                                       ? Theme.surfaceVariant
                                       : Qt.rgba(Theme.statusReading.r, Theme.statusReading.g,
                                                 Theme.statusReading.b, modelData)
                            }
                        }
                        Text {
                            text: Theme.tr("More")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall - 1
                        }
                    }
                }
            }

            // ═══════════════════════════════════
            // Section 4: Recent Sessions
            // ═══════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.pageMargin
                Layout.rightMargin: Theme.pageMargin
                implicitHeight: recentColumn.implicitHeight + Theme.spacingLarge * 2
                radius: Theme.radiusCard
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

                                ToolButton {
                                    id: editButton
                                    text: Theme.tr("Edit")
                                    onClicked: editSessionDialog.openFor(sessionRow.modelData)
                                    // No Material hover fill — hover just underlines the label.
                                    background: Item {}
                                    contentItem: Text {
                                        text: editButton.text
                                        color: Theme.textSecondary
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.underline: editButton.hovered
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }

                                Text {
                                    // Fixed width sized for a 3-digit count so the Edit button
                                    // to its left does not shift when the number is 1 or 2 digits.
                                    Layout.preferredWidth: sessionsPage.pagesLabelWidth
                                    horizontalAlignment: Text.AlignRight
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

    // ── Edit session dialog ──
    Dialog {
        id: editSessionDialog

        property int sessionId: -1
        property string bookTitle: ""

        anchors.centerIn: Overlay.overlay
        width: 380
        modal: true
        closePolicy: Dialog.NoAutoClose
        title: Theme.tr("Edit session")

        Material.theme: Theme.isDark ? Material.Dark : Material.Light
        Material.background: Theme.surface
        Material.foreground: Theme.textOnSurface

        // Prefill the fields from a recentSessions entry, then show.
        function openFor(session) {
            sessionId = session.id;
            bookTitle = session.title;
            dateField.text = Qt.formatDate(session.date, "yyyy-MM-dd");
            pagesSpin.value = session.pages;
            errorLabel.text = "";
            open();
        }

        ColumnLayout {
            width: parent.width
            spacing: Theme.spacingMedium

            Text {
                Layout.fillWidth: true
                text: editSessionDialog.bookTitle
                color: Theme.textOnSurface
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
                elide: Text.ElideRight
            }

            // Date
            Text {
                text: Theme.tr("Date")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
            }
            TextField {
                id: dateField
                Layout.fillWidth: true
                placeholderText: "yyyy-MM-dd"
                inputMask: "9999-99-99;_"
                color: Theme.textOnSurface
            }

            // Pages
            Text {
                text: Theme.tr("Pages read")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
            }
            SpinBox {
                id: pagesSpin
                Layout.fillWidth: true
                editable: true
                from: 0
                to: 99999
            }

            // Hint: 0 pages removes the session entirely.
            Text {
                Layout.fillWidth: true
                visible: pagesSpin.value === 0
                text: Theme.tr("Setting pages to 0 deletes this session")
                color: Theme.error
                font.pixelSize: Theme.fontSizeSmall
                font.italic: true
                wrapMode: Text.WordWrap
            }

            Text {
                id: errorLabel
                Layout.fillWidth: true
                visible: text.length > 0
                color: Theme.error
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingSmall
                spacing: Theme.spacingMedium

                Item { Layout.fillWidth: true }

                Button {
                    text: Theme.tr("Cancel")
                    flat: true
                    onClicked: editSessionDialog.close()
                }

                Button {
                    text: Theme.tr("Save")
                    highlighted: true
                    onClicked: {
                        // Editable SpinBox does not commit its text until focus-loss;
                        // force it before reading .value (see CLAUDE.md gotcha).
                        pagesSpin.value = pagesSpin.valueFromText(
                            pagesSpin.contentItem.text, pagesSpin.locale);

                        // 0 pages is a delete, not an edit.
                        if (pagesSpin.value === 0) {
                            bookController.deleteReadingSession(editSessionDialog.sessionId);
                            statsProvider.refresh();
                            editSessionDialog.close();
                            return;
                        }

                        var err = bookController.updateReadingSession(
                            editSessionDialog.sessionId, dateField.text, pagesSpin.value);

                        if (err === "") {
                            statsProvider.refresh();
                            editSessionDialog.close();
                        } else {
                            errorLabel.text = Theme.tr(err);
                        }
                    }
                }
            }
        }
    }

    // ── Inline component: Stat Card (matches StatisticsOverview.qml) ──
    component StatCard: Rectangle {
        id: statCard
        property var value: 0
        property string label: ""
        property color accent: Theme.primary

        implicitHeight: 90
        radius: Theme.radiusCard
        color: cardHover.containsMouse ? Theme.surfaceVariant : Theme.surface
        scale: cardHover.containsMouse ? 1.03 : 1.0
        border.width: cardHover.containsMouse ? 1 : 0
        border.color: accent

        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 140 } }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: Theme.spacingSmall

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: String(statCard.value)
                color: statCard.accent
                font.pixelSize: 30
                font.bold: true
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: statCard.label
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        MouseArea {
            id: cardHover
            anchors.fill: parent
            hoverEnabled: true
        }
    }
}
