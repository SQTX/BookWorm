import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import BookWorm

/**
 * Everything that can be earned, earned or not.
 *
 * The locked entries are the reason this page exists. A notification tells you
 * what you just did; only a list tells you what there is to do, and an
 * achievement whose shape nobody can see is not a goal but a surprise. So the
 * locked ones show their title, their requirement and how far along it is —
 * dimmed, but never hidden.
 */
Item {
    id: root

    /** Cached rather than re-read per delegate: entries() runs a dozen
     *  aggregate queries, and a GridView asks its model for a great deal more
     *  than it shows. */
    property var allEntries: []
    property string filter: "all"   // all | unlocked | locked

    function reload() {
        root.allEntries = achievements.entries();
    }

    function visibleEntries() {
        if (root.filter === "unlocked")
            return root.allEntries.filter(function(e) { return e.unlocked; });
        if (root.filter === "locked")
            return root.allEntries.filter(function(e) { return !e.unlocked; });
        return root.allEntries;
    }

    Component.onCompleted: root.reload()

    // Finishing a book unlocks things; so does adding one. The list has to
    // agree with the notification that just appeared over it.
    Connections {
        target: achievements
        function onChanged() { root.reload(); }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pageMargin
        spacing: Theme.sectionGap

        PageHeader {
            Layout.fillWidth: true
            title: Theme.tr("Achievements")
            subtitle: achievements.unlockedCount + " / " + achievements.totalCount + " "
                      + Theme.tr("unlocked")

            Row {
                spacing: Theme.spacingSmall

                Chip {
                    text: Theme.tr("All")
                    selected: root.filter === "all"
                    onClicked: root.filter = "all"
                }
                Chip {
                    text: Theme.tr("Unlocked")
                    selected: root.filter === "unlocked"
                    onClicked: root.filter = "unlocked"
                }
                Chip {
                    text: Theme.tr("Locked")
                    selected: root.filter === "locked"
                    onClicked: root.filter = "locked"
                }
            }
        }

        // Overall progress. One number at the top answers "how am I doing"
        // without counting tiles.
        Panel {
            Layout.fillWidth: true
            Layout.preferredHeight: 56

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.cardPadding
                spacing: Theme.spacingMedium

                Rectangle {
                    Layout.fillWidth: true
                    height: 8
                    radius: 4
                    color: Theme.surfaceVariant

                    Rectangle {
                        width: parent.width * (achievements.totalCount > 0
                                               ? achievements.unlockedCount / achievements.totalCount
                                               : 0)
                        height: parent.height
                        radius: parent.radius
                        color: Theme.primary
                        Behavior on width {
                            NumberAnimation { duration: Theme.durationSlow; easing.type: Theme.easeOut }
                        }
                    }
                }

                Text {
                    text: (achievements.totalCount > 0
                           ? Math.round(100 * achievements.unlockedCount / achievements.totalCount)
                           : 0) + "%"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeMedium
                }
            }
        }

        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            // Invisible items are dropped from a Layout, which is what leaves
            // the empty state the whole area rather than half of it.
            visible: count > 0

            model: root.visibleEntries()

            // Auto-fitting columns, the same rule the library grid uses, so the
            // two pages do not disagree about how wide a card wants to be.
            readonly property int columns: Math.max(1, Math.floor(width / 300))
            cellWidth: width / columns
            cellHeight: 116

            ScrollBar.vertical: ScrollBar {}

            delegate: Item {
                required property var modelData
                width: grid.cellWidth
                height: grid.cellHeight

                Panel {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingSmall / 2
                    interactive: true

                    // Earned entries carry the accent permanently; locked ones
                    // only while hovered, so the page can be read at a glance
                    // without reading any of it. The `hovered` term is not
                    // optional — assigning border.color replaces Panel's own
                    // binding, and dropping it would silently remove hover
                    // feedback from every locked card.
                    border.color: (modelData.unlocked || hovered) ? Theme.primary
                                                                  : Theme.outline

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.cardPadding
                        spacing: Theme.spacingMedium

                        Rectangle {
                            Layout.preferredWidth: 56
                            Layout.preferredHeight: 56
                            Layout.alignment: Qt.AlignVCenter
                            radius: Theme.radiusControl
                            color: Theme.background
                            clip: true

                            Image {
                                anchors.fill: parent
                                source: modelData.icon
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: status === Image.Ready
                                // Locked artwork is drained rather than
                                // replaced: the shape stays recognisable, so
                                // unlocking it is a change in the same picture
                                // instead of a different one appearing.
                                opacity: modelData.unlocked ? 1.0 : 0.28
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 3

                            Text {
                                Layout.fillWidth: true
                                text: Theme.tr(modelData.title)
                                color: modelData.unlocked ? Theme.textOnSurface : Theme.textSecondary
                                font.pixelSize: Theme.fontSizeMedium
                                font.bold: modelData.unlocked
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: Theme.tr(modelData.description)
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                elide: Text.ElideRight
                            }

                            // Progress only while it is still progress. On an
                            // earned achievement the bar would always be full,
                            // which tells the reader nothing and costs a line
                            // that the date can use instead.
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 14
                                visible: !modelData.unlocked

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: counter.left
                                    anchors.rightMargin: Theme.spacingSmall
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 5
                                    radius: 2.5
                                    color: Theme.surfaceVariant

                                    Rectangle {
                                        width: parent.width * modelData.progress
                                        height: parent.height
                                        radius: parent.radius
                                        color: Theme.primary
                                        opacity: 0.75
                                    }
                                }

                                Text {
                                    id: counter
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.current + " / " + modelData.target
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSection
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: modelData.unlocked
                                text: modelData.unlockedAt !== ""
                                      ? Theme.tr("Unlocked") + " "
                                        + modelData.unlockedAt.substring(0, 10)
                                      : Theme.tr("Unlocked")
                                color: Theme.primary
                                font.pixelSize: Theme.fontSizeSection
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }

        EmptyState {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: grid.count === 0
            compact: true
            title: root.filter === "unlocked"
                   ? Theme.tr("Nothing unlocked yet")
                   : Theme.tr("Everything is unlocked")
            hint: root.filter === "unlocked"
                  ? Theme.tr("Finish a book to earn your first one")
                  : Theme.tr("There is nothing left to earn")
        }
    }
}
