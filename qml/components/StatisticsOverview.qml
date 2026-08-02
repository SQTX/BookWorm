import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCharts
import BookWorm

Item {
    id: statsPage

    Component.onCompleted: {
        statsProvider.refresh();
    }

    Connections {
        target: statsProvider
        function onDataChanged() { updateCharts(); }
    }

    readonly property var chartColors: [
        "#BB86FC", "#03DAC6", "#CF6679", "#4FC3F7",
        "#81C784", "#FFB74D", "#F06292", "#64B5F6",
        "#AED581", "#FFD54F", "#BA68C8", "#4DD0E1"
    ]

    readonly property var monthLabels: Theme.getMonthLabels()

    // Genre chart display mode: "bars" (default), "pie", or "treemap".
    property string genreChartMode: "bars"

    // Squarified treemap layout (Bruls, Huizing & van Wijk). Takes the genre
    // distribution and a WxH box, returns [{x,y,w,h,genre,count,index}] with each
    // tile's area proportional to its count and aspect ratios kept close to 1.
    function squarifyTreemap(data, W, H) {
        if (!data || data.length === 0 || W <= 0 || H <= 0)
            return [];

        var total = 0;
        for (var i = 0; i < data.length; i++)
            total += data[i].count;
        if (total <= 0)
            return [];

        // Scale counts to pixel area, then sort descending — squarify needs the
        // largest first to keep tiles near-square.
        var scale = (W * H) / total;
        var items = [];
        for (var j = 0; j < data.length; j++)
            items.push({ area: data[j].count * scale, genre: data[j].genre,
                         count: data[j].count, index: j });
        items.sort(function (a, b) { return b.area - a.area; });

        var out = [];
        var free = { x: 0, y: 0, w: W, h: H };

        function worst(row, side, extra) {
            var arr = extra ? row.concat([extra]) : row;
            var sum = 0, mn = Infinity, mx = 0;
            for (var k = 0; k < arr.length; k++) {
                var a = arr[k].area;
                sum += a; if (a < mn) mn = a; if (a > mx) mx = a;
            }
            if (sum <= 0) return Infinity;
            var s2 = sum * sum, side2 = side * side;
            return Math.max(side2 * mx / s2, s2 / (side2 * mn));
        }

        function placeRow(row) {
            var side = Math.min(free.w, free.h);
            var sum = 0;
            for (var k = 0; k < row.length; k++) sum += row[k].area;
            var thick = sum / side;   // strip depth, perpendicular to the short side
            if (free.w >= free.h) {
                // Vertical strip on the left; tiles stacked top→bottom.
                var oy = free.y;
                for (var m = 0; m < row.length; m++) {
                    var rh = row[m].area / thick;
                    out.push({ x: free.x, y: oy, w: thick, h: rh,
                               genre: row[m].genre, count: row[m].count, index: row[m].index });
                    oy += rh;
                }
                free.x += thick; free.w -= thick;
            } else {
                // Horizontal strip on top; tiles laid left→right.
                var ox = free.x;
                for (var n = 0; n < row.length; n++) {
                    var rw = row[n].area / thick;
                    out.push({ x: ox, y: free.y, w: rw, h: thick,
                               genre: row[n].genre, count: row[n].count, index: row[n].index });
                    ox += rw;
                }
                free.y += thick; free.h -= thick;
            }
        }

        var row = [];
        var idx = 0;
        while (idx < items.length) {
            var next = items[idx];
            var side = Math.min(free.w, free.h);
            if (row.length === 0 || worst(row, side, next) <= worst(row, side)) {
                row.push(next);
                idx++;
            } else {
                placeRow(row);
                row = [];
            }
        }
        if (row.length > 0)
            placeRow(row);

        return out;
    }

    function updateCharts() {
        // ── Update Pie Chart ──
        libraryPie.clear();
        var sd = statsProvider.statusDistribution;
        var readCount = sd.read || 0;
        var readingCount = sd.reading || 0;
        var plannedCount = sd.planned || 0;

        if (readCount > 0) {
            var s1 = libraryPie.append(Theme.tr("Read") + " (" + readCount + ")", readCount);
            s1.color = Theme.statusRead;
            s1.borderColor = Theme.surface;
            s1.borderWidth = 2;
            s1.labelVisible = true;
            s1.labelColor = Theme.textOnSurface;
            s1.labelFont.pixelSize = Theme.fontSizeSmall;
        }
        if (readingCount > 0) {
            var s2 = libraryPie.append(Theme.tr("Reading") + " (" + readingCount + ")", readingCount);
            s2.color = Theme.statusReading;
            s2.borderColor = Theme.surface;
            s2.borderWidth = 2;
            s2.labelVisible = true;
            s2.labelColor = Theme.textOnSurface;
            s2.labelFont.pixelSize = Theme.fontSizeSmall;
        }
        if (plannedCount > 0) {
            var s3 = libraryPie.append(Theme.tr("Planned") + " (" + plannedCount + ")", plannedCount);
            s3.color = Theme.statusPlanned;
            s3.borderColor = Theme.surface;
            s3.borderWidth = 2;
            s3.labelVisible = true;
            s3.labelColor = Theme.textOnSurface;
            s3.labelFont.pixelSize = Theme.fontSizeSmall;
        }

        // ── Update Monthly Bar Chart ──
        currentYearBarSet.values = [];
        prevYearLine.clear();

        var curData = statsProvider.booksPerMonthCurrentYear;
        var prevData = statsProvider.booksPerMonthPreviousYear;
        var maxVal = 1;
        var curValues = [];

        for (var i = 0; i < 12; i++) {
            var cv = (curData && curData[i]) ? curData[i].count : 0;
            var pv = (prevData && prevData[i]) ? prevData[i].count : 0;
            curValues.push(cv);
            prevYearLine.append(i, pv);
            if (cv > maxVal) maxVal = cv;
            if (pv > maxVal) maxVal = pv;
        }
        currentYearBarSet.values = curValues;
        monthlyCountAxis.max = maxVal + 1;

        // ── Update Genre Pie ──
        genrePie.clear();
        var gd = statsProvider.genreDistribution;
        for (var g = 0; g < gd.length; g++) {
            var slice = genrePie.append(gd[g].genre + " (" + gd[g].count + ")", gd[g].count);
            slice.color = statsPage.chartColors[g % statsPage.chartColors.length];
            slice.borderColor = Theme.surface;
            slice.borderWidth = 2;
            slice.labelVisible = true;
            slice.labelColor = Theme.textOnSurface;
            slice.labelFont.pixelSize = Theme.fontSizeSmall;
        }
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
            // Section 1: Summary Cards (5 cards)
            // ═══════════════════════════════════
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXL
                Layout.rightMargin: Theme.spacingXL
                Layout.topMargin: Theme.spacingXL
                spacing: Theme.spacingMedium

                StatCard {
                    Layout.fillWidth: true
                    value: statsProvider.totalBooks
                    label: Theme.tr("Total Books")
                    accent: Theme.primary
                }

                StatCard {
                    Layout.fillWidth: true
                    value: statsProvider.totalBooksRead
                    label: Theme.tr("Books Read")
                    accent: Theme.statusRead
                }

                StatCard {
                    Layout.fillWidth: true
                    value: statsProvider.totalPagesRead
                    label: Theme.tr("Pages Read")
                    accent: Theme.secondary
                }

                StatCard {
                    Layout.fillWidth: true
                    value: statsProvider.averagePagesPerBook > 0
                           ? Math.round(statsProvider.averagePagesPerBook)
                           : "\u2014"
                    label: Theme.tr("Avg Pages/Book")
                    accent: Theme.statusReading
                }

                StatCard {
                    Layout.fillWidth: true
                    value: statsProvider.averageCompletionPercent > 0
                           ? statsProvider.averageCompletionPercent.toFixed(1) + "%"
                           : "\u2014"
                    label: Theme.tr("Avg Completion")
                    accent: Theme.statusPlanned
                }
            }

            // ═══════════════════════════════════
            // Section 2: Library Composition + Rating
            // ═══════════════════════════════════
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXL
                Layout.rightMargin: Theme.spacingXL
                Layout.preferredHeight: 400
                spacing: Theme.spacingLarge

                // ── Pie Chart: Library Composition ──
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusMedium
                    color: Theme.surface

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingLarge
                        spacing: 0

                        Text {
                            text: Theme.tr("Library Composition")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeMedium
                            font.bold: true
                        }

                        ChartView {
                            id: pieChartView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            antialiasing: true
                            backgroundColor: "transparent"
                            plotAreaColor: "transparent"
                            legend.visible: true
                            legend.alignment: Qt.AlignBottom
                            legend.labelColor: Theme.textSecondary
                            legend.font.pixelSize: Theme.fontSizeSmall
                            animationOptions: ChartView.SeriesAnimations
                            margins.top: 20
                            margins.bottom: 0
                            margins.left: 0
                            margins.right: 0

                            PieSeries {
                                id: libraryPie
                                holeSize: 0.45
                                size: 0.75
                            }
                        }

                        // Empty state
                        Text {
                            visible: statsProvider.totalBooks === 0
                            text: Theme.tr("No books in library yet")
                            color: Theme.textSecondary
                            font.italic: true
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }

                // ── Right panel: Rating + Top Genre ──
                Rectangle {
                    Layout.preferredWidth: 280
                    Layout.fillHeight: true
                    radius: Theme.radiusMedium
                    color: Theme.surface

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingLarge
                        spacing: Theme.spacingLarge

                        // Avg Rating
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSmall

                            Text {
                                text: Theme.tr("Average Rating")
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeMedium
                                font.bold: true
                            }

                            Text {
                                text: statsProvider.averageRating > 0
                                      ? statsProvider.averageRating.toFixed(1) + " / 6"
                                      : "\u2014"
                                color: Theme.statusPlanned
                                font.pixelSize: 42
                                font.bold: true
                            }

                            // Star row
                            Row {
                                spacing: 4
                                Repeater {
                                    model: 6
                                    Text {
                                        text: (index + 1) <= Math.round(statsProvider.averageRating)
                                              ? "\u2605" : "\u2606"
                                        color: (index + 1) <= Math.round(statsProvider.averageRating)
                                               ? Theme.statusPlanned : Theme.textSecondary
                                        font.pixelSize: 22
                                    }
                                }
                            }
                        }

                        // Divider
                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.divider }

                        // Top Genre
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSmall

                            Text {
                                text: Theme.tr("Top Genre")
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeMedium
                                font.bold: true
                            }

                            Text {
                                text: {
                                    var gd = statsProvider.genreDistribution;
                                    if (gd.length > 0) return gd[0].genre;
                                    return "\u2014";
                                }
                                color: Theme.primary
                                font.pixelSize: Theme.fontSizeLarge
                                font.bold: true
                            }

                            Text {
                                visible: statsProvider.genreDistribution.length > 0
                                text: {
                                    var gd = statsProvider.genreDistribution;
                                    if (gd.length > 0) return gd[0].count + " " + Theme.tr("books");
                                    return "";
                                }
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeMedium
                            }
                        }

                        // Divider
                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.divider }

                        // Books read percentage
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSmall

                            Text {
                                text: Theme.tr("Read Rate")
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeMedium
                                font.bold: true
                            }

                            Text {
                                text: {
                                    if (statsProvider.totalBooks === 0) return "\u2014";
                                    var pct = (statsProvider.totalBooksRead / statsProvider.totalBooks * 100).toFixed(1);
                                    return pct + "%";
                                }
                                color: Theme.statusRead
                                font.pixelSize: Theme.fontSizeLarge
                                font.bold: true
                            }

                            Text {
                                text: statsProvider.totalBooksRead + " " + Theme.tr("of") + " " + statsProvider.totalBooks + " " + Theme.tr("books")
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }

            // ═══════════════════════════════════
            // Section 3: Monthly Comparison Chart
            // ═══════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXL
                Layout.rightMargin: Theme.spacingXL
                Layout.preferredHeight: 400
                radius: Theme.radiusMedium
                color: Theme.surface

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingSmall

                    Text {
                        text: {
                            var yr = statsProvider.selectedYear > 0 ? statsProvider.selectedYear : new Date().getFullYear();
                            return Theme.tr("Monthly Books Read") + " (" + yr + " vs " + (yr - 1) + ")";
                        }
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeMedium
                        font.bold: true
                    }

                    ChartView {
                        id: monthlyChartView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        antialiasing: true
                        backgroundColor: "transparent"
                        plotAreaColor: "transparent"
                        legend.visible: true
                        legend.alignment: Qt.AlignTop
                        legend.labelColor: Theme.textSecondary
                        legend.font.pixelSize: Theme.fontSizeSmall
                        animationOptions: ChartView.SeriesAnimations
                        margins.top: 0
                        margins.bottom: 0
                        margins.left: 0
                        margins.right: 0

                        // X-axis for bars (category)
                        BarCategoryAxis {
                            id: monthCategoryAxis
                            categories: statsPage.monthLabels
                            labelsColor: Theme.textSecondary
                            labelsFont.pixelSize: 11
                            gridVisible: false
                            lineVisible: false
                        }

                        // Y-axis for bars
                        ValueAxis {
                            id: monthlyCountAxis
                            min: 0
                            max: 5
                            tickCount: 6
                            labelFormat: "%d"
                            labelsColor: Theme.textSecondary
                            labelsFont.pixelSize: 11
                            gridLineColor: Theme.divider
                            lineVisible: false
                        }

                        BarSeries {
                            id: currentYearBars
                            name: String(statsProvider.selectedYear > 0 ? statsProvider.selectedYear : new Date().getFullYear())
                            axisX: monthCategoryAxis
                            axisY: monthlyCountAxis
                            barWidth: 0.6

                            BarSet {
                                id: currentYearBarSet
                                label: String(statsProvider.selectedYear > 0 ? statsProvider.selectedYear : new Date().getFullYear())
                                color: Theme.primary
                                borderColor: "transparent"
                            }
                        }

                        // Hidden ValueAxis for LineSeries X (0-11)
                        ValueAxis {
                            id: lineXAxis
                            min: -0.5
                            max: 11.5
                            visible: false
                        }

                        LineSeries {
                            id: prevYearLine
                            name: {
                                var yr = statsProvider.selectedYear > 0 ? statsProvider.selectedYear : new Date().getFullYear();
                                return String(yr - 1);
                            }
                            axisX: lineXAxis
                            axisY: monthlyCountAxis
                            color: Theme.statusPlanned
                            width: 2.5
                            style: Qt.DashLine
                        }
                    }

                    // Empty state
                    Text {
                        visible: {
                            var cur = statsProvider.booksPerMonthCurrentYear;
                            var prev = statsProvider.booksPerMonthPreviousYear;
                            var total = 0;
                            for (var i = 0; i < 12; i++) {
                                total += ((cur && cur[i]) ? cur[i].count : 0);
                                total += ((prev && prev[i]) ? prev[i].count : 0);
                            }
                            return total === 0;
                        }
                        text: Theme.tr("No monthly data yet")
                        color: Theme.textSecondary
                        font.italic: true
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }

            // ═══════════════════════════════════
            // Section 4: Yearly Stats Table
            // ═══════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXL
                Layout.rightMargin: Theme.spacingXL
                implicitHeight: yearlyColumn.implicitHeight + Theme.spacingLarge * 2
                radius: Theme.radiusMedium
                color: Theme.surface

                ColumnLayout {
                    id: yearlyColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    Text {
                        text: Theme.tr("Yearly Reading Stats")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeMedium
                        font.bold: true
                    }

                    // Header row
                    Row {
                        Layout.fillWidth: true

                        Text {
                            width: parent.width * 0.12
                            text: Theme.tr("Year")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }
                        Text {
                            width: parent.width * 0.15
                            text: Theme.tr("Books")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            width: parent.width * 0.25
                            text: Theme.tr("Total Pages")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            width: parent.width * 0.25
                            text: Theme.tr("Avg Pages")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            width: parent.width * 0.23
                            text: Theme.tr("Avg Rating")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.divider }

                    // Data rows
                    Repeater {
                        model: statsProvider.booksPerYear

                        Row {
                            required property var modelData
                            required property int index
                            width: parent.width

                            Text {
                                width: parent.width * 0.12
                                text: modelData.year
                                color: Theme.textOnSurface
                                font.pixelSize: Theme.fontSizeMedium
                                font.bold: true
                            }
                            Text {
                                width: parent.width * 0.15
                                text: modelData.count
                                color: Theme.primary
                                font.pixelSize: Theme.fontSizeMedium
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Text {
                                width: parent.width * 0.25
                                text: modelData.totalPages.toLocaleString()
                                color: Theme.textOnSurface
                                font.pixelSize: Theme.fontSizeMedium
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Text {
                                width: parent.width * 0.25
                                text: modelData.avgPages
                                color: Theme.textOnSurface
                                font.pixelSize: Theme.fontSizeMedium
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Text {
                                width: parent.width * 0.23
                                text: modelData.avgRating > 0
                                      ? modelData.avgRating.toFixed(1) + " \u2605"
                                      : "\u2014"
                                color: Theme.statusPlanned
                                font.pixelSize: Theme.fontSizeMedium
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    // Empty state
                    Text {
                        visible: statsProvider.booksPerYear.length === 0
                        text: Theme.tr("No yearly data yet")
                        color: Theme.textSecondary
                        font.italic: true
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: Theme.spacingMedium
                    }
                }
            }

            // ═══════════════════════════════════
            // Section 5: Genre Distribution (bars / pie / treemap)
            // ═══════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXL
                Layout.rightMargin: Theme.spacingXL
                implicitHeight: genreColumn.implicitHeight + Theme.spacingLarge * 2
                radius: Theme.radiusMedium
                color: Theme.surface

                ColumnLayout {
                    id: genreColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    // Header: title + chart-type switcher
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMedium

                        Text {
                            Layout.fillWidth: true
                            text: Theme.tr("Genre Distribution")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeMedium
                            font.bold: true
                        }

                        Repeater {
                            model: [
                                { key: "Bars",    value: "bars" },
                                { key: "Pie",     value: "pie" },
                                { key: "Treemap", value: "treemap" }
                            ]

                            Rectangle {
                                required property var modelData
                                readonly property bool isSelected:
                                    statsPage.genreChartMode === modelData.value

                                width: modeText.implicitWidth + Theme.spacingLarge
                                height: 28
                                radius: 14
                                color: isSelected ? Theme.primary : Theme.surfaceVariant
                                border.width: 1
                                border.color: isSelected ? "transparent" : Theme.divider

                                Text {
                                    id: modeText
                                    anchors.centerIn: parent
                                    text: Theme.tr(parent.modelData.key)
                                    color: parent.isSelected ? Theme.textOnPrimary : Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: parent.isSelected
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: statsPage.genreChartMode = parent.modelData.value
                                }
                            }
                        }
                    }

                    // ── View: horizontal bars ──
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMedium
                        visible: statsPage.genreChartMode === "bars"
                                 && statsProvider.genreDistribution.length > 0

                        Repeater {
                            model: statsProvider.genreDistribution

                            RowLayout {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                spacing: Theme.spacingMedium

                                Text {
                                    Layout.preferredWidth: 120
                                    text: modelData.genre
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignRight
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 24
                                    radius: 4
                                    color: Theme.surfaceVariant

                                    Rectangle {
                                        width: {
                                            var maxCount = 1;
                                            var data = statsProvider.genreDistribution;
                                            for (var i = 0; i < data.length; i++)
                                                if (data[i].count > maxCount) maxCount = data[i].count;
                                            return Math.max(4, parent.width * (modelData.count / maxCount));
                                        }
                                        height: parent.height
                                        radius: 4
                                        color: statsPage.chartColors[index % statsPage.chartColors.length]

                                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                    }
                                }

                                Text {
                                    Layout.preferredWidth: 35
                                    text: modelData.count
                                    color: Theme.textOnSurface
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.bold: true
                                }
                            }
                        }
                    }

                    // ── View: pie chart ──
                    ChartView {
                        id: genrePieView
                        Layout.fillWidth: true
                        Layout.preferredHeight: 400
                        visible: statsPage.genreChartMode === "pie"
                                 && statsProvider.genreDistribution.length > 0
                        antialiasing: true
                        backgroundColor: "transparent"
                        legend.visible: false
                        margins.top: 10
                        margins.bottom: 10
                        margins.left: 10
                        margins.right: 10

                        PieSeries {
                            id: genrePie
                            size: 0.8
                            holeSize: 0.35
                        }
                    }

                    // ── View: squarified treemap ──
                    Item {
                        id: treemapView
                        Layout.fillWidth: true
                        Layout.preferredHeight: 460
                        visible: statsPage.genreChartMode === "treemap"
                                 && statsProvider.genreDistribution.length > 0

                        Repeater {
                            model: statsPage.squarifyTreemap(statsProvider.genreDistribution,
                                                             treemapView.width, treemapView.height)

                            Rectangle {
                                required property var modelData
                                x: modelData.x
                                y: modelData.y
                                width: modelData.w
                                height: modelData.h
                                color: statsPage.chartColors[modelData.index % statsPage.chartColors.length]
                                border.width: 1
                                border.color: Theme.surface

                                // Full label (genre + count) when the tile is roomy.
                                Column {
                                    anchors.centerIn: parent
                                    width: parent.width - 8
                                    spacing: 0
                                    visible: parent.width > 46 && parent.height > 30

                                    Text {
                                        width: parent.width
                                        text: parent.parent.modelData.genre
                                        color: "#1A1A1A"
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.bold: true
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignHCenter
                                    }

                                    Text {
                                        width: parent.width
                                        text: parent.parent.modelData.count
                                        color: "#1A1A1A"
                                        font.pixelSize: Theme.fontSizeSmall
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }

                                // Count only, for tiles too small for the full label.
                                Text {
                                    anchors.centerIn: parent
                                    visible: parent.width > 22 && parent.height > 16
                                             && !(parent.width > 46 && parent.height > 30)
                                    text: parent.modelData.count
                                    color: "#1A1A1A"
                                    font.pixelSize: 10
                                }
                            }
                        }
                    }

                    // Empty state (shared by every mode)
                    Text {
                        visible: statsProvider.genreDistribution.length === 0
                        text: Theme.tr("No genre data yet")
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

    // ── Inline component: Stat Card ──
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
