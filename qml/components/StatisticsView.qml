import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import BookWorm

Item {
    id: statisticsPage

    ColumnLayout {
        id: shellColumn
        anchors.fill: parent
        spacing: Theme.spacingLarge

        // ═══════════════════════════════════
        // Header + Year filter
        // ═══════════════════════════════════
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacingXL
            Layout.rightMargin: Theme.spacingXL
            Layout.topMargin: Theme.spacingXL

            Text {
                text: Theme.tr("Statistics")
                color: Theme.textOnBackground
                font.pixelSize: Theme.fontSizeHeader
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            // Year filter ComboBox
            ComboBox {
                id: yearCombo
                Layout.preferredWidth: 200
                Layout.preferredHeight: 36
                Material.accent: Theme.primary
                font.pixelSize: Theme.fontSizeMedium

                model: {
                    var years = statsProvider.availableYears;
                    var items = [Theme.tr("All time")];
                    for (var i = 0; i < years.length; i++)
                        items.push(String(years[i]));
                    return items;
                }

                currentIndex: {
                    if (statsProvider.selectedYear === 0) return 0;
                    var years = statsProvider.availableYears;
                    for (var i = 0; i < years.length; i++) {
                        if (years[i] === statsProvider.selectedYear)
                            return i + 1;
                    }
                    return 0;
                }

                onActivated: function(index) {
                    if (index === 0) {
                        statsProvider.selectedYear = 0;
                    } else {
                        var years = statsProvider.availableYears;
                        statsProvider.selectedYear = years[index - 1];
                    }
                }
            }
        }

        // ═══════════════════════════════════
        // Tabs
        // ═══════════════════════════════════
        TabBar {
            id: statsTabs
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacingXL
            Layout.rightMargin: Theme.spacingXL
            Material.accent: Theme.primary

            TabButton { text: Theme.tr("Overview") }
            TabButton { text: Theme.tr("Sessions") }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: statsTabs.currentIndex

            StatisticsOverview { }
            StatisticsSessions { }
        }
    }
}
