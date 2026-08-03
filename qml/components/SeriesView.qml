import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import BookWorm

Item {
    id: seriesPage

    signal bookSelected(int bookId)

    property var seriesData: []

    function reload() { seriesData = bookController.getSeriesList(); }

    Component.onCompleted: reload()

    Connections {
        target: bookController
        function onBooksChanged() { seriesPage.reload(); }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pageMargin
        spacing: Theme.sectionGap

        // Header
        PageHeader {
            Layout.fillWidth: true
            title: Theme.tr("Series")
            subtitle: seriesPage.seriesData.length > 0
                      ? seriesPage.seriesData.length + " " + Theme.tr("series")
                      : ""
        }

        // Empty state
        EmptyState {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: seriesPage.seriesData.length === 0
            icon: "qrc:/qt/qml/BookWorm/src/img/icons/book-cover.svg"
            title: Theme.tr("No series yet")
            hint: Theme.tr("Fill in the Series field on a book and it will show up here, grouped with the rest of its cycle.")
        }

        // Series list
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: seriesColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            visible: seriesPage.seriesData.length > 0

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Column {
                id: seriesColumn
                width: parent.width
                spacing: Theme.spacingMedium

                Repeater {
                    model: seriesPage.seriesData

                    // ── One series card ──
                    Panel {
                        id: seriesCard
                        required property var modelData
                        property bool expanded: false

                        width: seriesColumn.width
                        implicitHeight: cardColumn.implicitHeight + Theme.spacingLarge * 2
                        interactive: true
                        accent: Theme.statusRead

                        Behavior on implicitHeight {
                            NumberAnimation { duration: Theme.durationMedium; easing.type: Theme.easeOut }
                        }

                        Column {
                            id: cardColumn
                            x: Theme.spacingLarge
                            y: Theme.spacingLarge
                            width: parent.width - Theme.spacingLarge * 2
                            spacing: Theme.spacingMedium

                            // Header (click toggles expand)
                            Item {
                                width: parent.width
                                height: headerRow.implicitHeight

                                RowLayout {
                                    id: headerRow
                                    width: parent.width
                                    spacing: Theme.spacingMedium

                                    // One glyph that turns, rather than two that
                                    // swap — the rotation shows the panel opening.
                                    Text {
                                        text: "▸"
                                        color: seriesCard.expanded ? Theme.statusRead : Theme.textSecondary
                                        font.pixelSize: Theme.fontSizeMedium
                                        rotation: seriesCard.expanded ? 90 : 0

                                        Behavior on rotation {
                                            NumberAnimation { duration: Theme.durationMedium; easing.type: Theme.easeOut }
                                        }
                                        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 4

                                        Text {
                                            Layout.fillWidth: true
                                            text: seriesCard.modelData.name
                                            color: Theme.textOnSurface
                                            font.pixelSize: Theme.fontSizeLarge
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }

                                        // Progress bar (read / total)
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 6
                                            radius: 3
                                            color: Theme.surfaceVariant

                                            Rectangle {
                                                width: seriesCard.modelData.total > 0
                                                       ? parent.width * (seriesCard.modelData.read
                                                                         / seriesCard.modelData.total)
                                                       : 0
                                                height: parent.height
                                                radius: 3
                                                color: Theme.statusRead

                                                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                            }
                                        }
                                    }

                                    Text {
                                        text: seriesCard.modelData.read + " / " + seriesCard.modelData.total
                                        color: Theme.primary
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.bold: true
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: seriesCard.expanded = !seriesCard.expanded
                                }
                            }

                            // Books in the series (expanded)
                            Column {
                                width: parent.width
                                spacing: Theme.spacingSmall
                                visible: seriesCard.expanded

                                Repeater {
                                    model: seriesCard.expanded ? seriesCard.modelData.books : []

                                    Rectangle {
                                        id: bookRow
                                        required property var modelData
                                        width: parent.width
                                        height: 34
                                        radius: Theme.radiusControl
                                        color: bookMouse.containsMouse ? Theme.hover : "transparent"

                                        Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Theme.spacingLarge
                                            anchors.rightMargin: Theme.spacingSmall
                                            spacing: Theme.spacingMedium

                                            Rectangle {
                                                width: 10; height: 10; radius: 5
                                                Layout.alignment: Qt.AlignVCenter
                                                color: Theme.statusColor(bookRow.modelData.status)
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: bookRow.modelData.title
                                                color: Theme.textOnSurface
                                                font.pixelSize: Theme.fontSizeMedium
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                visible: bookRow.modelData.rating > 0
                                                text: "★ " + bookRow.modelData.rating
                                                color: Theme.primary
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.bold: true
                                            }

                                            Text {
                                                text: Theme.statusLabel(bookRow.modelData.status)
                                                color: Theme.textSecondary
                                                font.pixelSize: Theme.fontSizeSmall
                                            }
                                        }

                                        MouseArea {
                                            id: bookMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: seriesPage.bookSelected(bookRow.modelData.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Bottom spacer
                Item { width: parent.width; height: Theme.spacingLarge }
            }
        }
    }
}
