import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import WormBook

Item {
    id: statsPage

    Component.onCompleted: statsProvider.refresh()

    ScrollView {
        anchors.fill: parent
        clip: true

        ColumnLayout {
            width: statsPage.width
            spacing: Theme.spacingXL

            // Header
            Text {
                Layout.leftMargin: Theme.spacingXL
                Layout.topMargin: Theme.spacingXL
                text: "Statistics"
                color: Theme.textOnBackground
                font.pixelSize: Theme.fontSizeHeader
                font.bold: true
            }

            // Summary cards row
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXL
                Layout.rightMargin: Theme.spacingXL
                spacing: Theme.spacingLarge

                StatCard {
                    Layout.fillWidth: true
                    value: statsProvider.totalBooksRead
                    label: "Books Read"
                    accent: Theme.primary
                }

                StatCard {
                    Layout.fillWidth: true
                    value: statsProvider.totalPagesRead
                    label: "Pages Read"
                    accent: Theme.secondary
                }

                StatCard {
                    Layout.fillWidth: true
                    value: statsProvider.averageRating > 0
                           ? statsProvider.averageRating.toFixed(1)
                           : "\u2014"
                    label: "Avg Rating"
                    accent: Theme.statusPlanned
                }
            }

            // Charts row
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXL
                Layout.rightMargin: Theme.spacingXL
                Layout.preferredHeight: 350
                spacing: Theme.spacingLarge

                // Genre distribution (custom pie chart)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusMedium
                    color: Theme.surface

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingLarge
                        spacing: Theme.spacingMedium

                        Text {
                            text: "Genre Distribution"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeMedium
                            font.bold: true
                        }

                        // Genre bars (horizontal)
                        Repeater {
                            model: statsProvider.genreDistribution

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingMedium

                                Text {
                                    Layout.preferredWidth: 100
                                    text: modelData.genre
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignRight
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 20
                                    radius: 4
                                    color: Theme.surfaceVariant

                                    Rectangle {
                                        width: {
                                            var maxCount = 1;
                                            var data = statsProvider.genreDistribution;
                                            for (var i = 0; i < data.length; i++)
                                                if (data[i].count > maxCount) maxCount = data[i].count;
                                            return parent.width * (modelData.count / maxCount);
                                        }
                                        height: parent.height
                                        radius: 4
                                        color: statsPage.chartColors[index % statsPage.chartColors.length]
                                    }
                                }

                                Text {
                                    Layout.preferredWidth: 30
                                    text: modelData.count
                                    color: Theme.textOnSurface
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }
                        }

                        // Empty state
                        Text {
                            visible: statsProvider.genreDistribution.length === 0
                            text: "No genre data yet"
                            color: Theme.textSecondary
                            font.italic: true
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                // Books per month (bar chart)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusMedium
                    color: Theme.surface

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingLarge
                        spacing: Theme.spacingMedium

                        Text {
                            text: "Books per Month"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeMedium
                            font.bold: true
                        }

                        // Vertical bar chart
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Row {
                                anchors.fill: parent
                                anchors.bottomMargin: 24
                                spacing: 4

                                Repeater {
                                    model: statsProvider.booksPerMonth

                                    Item {
                                        width: (parent.width - (statsProvider.booksPerMonth.length - 1) * 4) / Math.max(statsProvider.booksPerMonth.length, 1)
                                        height: parent.height

                                        // Bar
                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: Math.min(parent.width - 4, 40)
                                            height: {
                                                var maxCount = 1;
                                                var data = statsProvider.booksPerMonth;
                                                for (var i = 0; i < data.length; i++)
                                                    if (data[i].count > maxCount) maxCount = data[i].count;
                                                return parent.height * (modelData.count / maxCount);
                                            }
                                            radius: 4
                                            color: Theme.primary

                                            // Count label on top
                                            Text {
                                                anchors.bottom: parent.top
                                                anchors.bottomMargin: 4
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: modelData.count
                                                color: Theme.textSecondary
                                                font.pixelSize: 11
                                            }
                                        }
                                    }
                                }
                            }

                            // Month labels at bottom
                            Row {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                spacing: 4

                                Repeater {
                                    model: statsProvider.booksPerMonth

                                    Text {
                                        width: (parent.width - (statsProvider.booksPerMonth.length - 1) * 4) / Math.max(statsProvider.booksPerMonth.length, 1)
                                        text: {
                                            var parts = modelData.month.split("-");
                                            return parts.length > 1 ? parts[1] + "/" + parts[0].substring(2) : modelData.month;
                                        }
                                        color: Theme.textSecondary
                                        font.pixelSize: 10
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }
                            }
                        }

                        // Empty state
                        Text {
                            visible: statsProvider.booksPerMonth.length === 0
                            text: "No monthly data yet"
                            color: Theme.textSecondary
                            font.italic: true
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }

            // Bottom spacer
            Item { Layout.preferredHeight: Theme.spacingXL }
        }
    }

    // Stat card component
    component StatCard: Rectangle {
        property var value: 0
        property string label: ""
        property color accent: Theme.primary

        implicitHeight: 100
        radius: Theme.radiusMedium
        color: Theme.surface

        ColumnLayout {
            anchors.centerIn: parent
            spacing: Theme.spacingSmall

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: String(value)
                color: accent
                font.pixelSize: 36
                font.bold: true
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: label
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeMedium
            }
        }
    }

    readonly property var chartColors: [
        "#BB86FC", "#03DAC6", "#CF6679", "#4FC3F7",
        "#81C784", "#FFB74D", "#F06292", "#64B5F6",
        "#AED581", "#FFD54F", "#BA68C8", "#4DD0E1"
    ]
}
