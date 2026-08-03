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
        PageHeader {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.pageMargin
            Layout.rightMargin: Theme.pageMargin
            Layout.topMargin: Theme.pageMargin
            title: Theme.tr("Statistics")
            subtitle: statsProvider.selectedYear === 0
                      ? Theme.tr("All time")
                      : String(statsProvider.selectedYear)
            // The TabBar directly below already draws a line; a second one here
            // would stack two rules a few pixels apart.
            showRule: false

            // Year filter ComboBox
            ComboBox {
                id: yearCombo
                Layout.preferredWidth: 200
                Layout.preferredHeight: Theme.controlHeight
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
            Layout.leftMargin: Theme.pageMargin
            Layout.rightMargin: Theme.pageMargin
            Material.accent: Theme.primary

            background: Rectangle {
                color: "transparent"

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Theme.outline
                }
            }

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
