import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import BookWorm

/**
 * What is out of the house, what is in it that is not yours, and what has come
 * back.
 *
 * The two open sections come first and the history last, because the question
 * this page exists to answer is "where is my copy of X" — and a returned loan
 * cannot answer it. History is kept rather than deleted so the same name can be
 * recognised the next time, and so "I am sure I lent you this" has an answer.
 *
 * Open loans sort longest-out first. Without a due date there is nothing to be
 * overdue against, so age is the only signal available for "this one has
 * probably been forgotten" — and it is a good one.
 */
Item {
    id: root

    property var openLoans: []
    property var pastLoans: []
    property bool showHistory: false

    function reload() {
        root.openLoans = loans.openLoans();
        root.pastLoans = loans.history();
    }

    function ofDirection(list, dir) {
        return list.filter(function(l) { return l.direction === dir; });
    }

    Component.onCompleted: root.reload()

    Connections {
        target: loans
        function onChanged() { root.reload(); }
    }

    // A deleted book takes its loans with it (ON DELETE CASCADE), so the list
    // has to be rebuilt when the library changes, not only when a loan does.
    Connections {
        target: bookController
        function onBooksChanged() { root.reload(); }
    }

    Flickable {
        id: page
        anchors.fill: parent
        anchors.margins: Theme.pageMargin
        contentWidth: width
        contentHeight: column.height
        clip: true

        ScrollBar.vertical: ScrollBar {}

        ColumnLayout {
            id: column
            width: page.width
            spacing: Theme.sectionGap

            PageHeader {
                Layout.fillWidth: true
                title: Theme.tr("Lending")
                subtitle: loans.lentOutCount + " " + Theme.tr("lent out") + "  ·  "
                          + loans.borrowedCount + " " + Theme.tr("borrowed")

                AppButton {
                    text: root.showHistory ? Theme.tr("Hide history") : Theme.tr("Show history")
                    variant: "outline"
                    onClicked: root.showHistory = !root.showHistory
                }
            }

            LoanSection {
                Layout.fillWidth: true
                heading: Theme.tr("Lent out")
                hint: Theme.tr("Books somebody else has right now")
                rows: root.ofDirection(root.openLoans, "lent")
                accent: Theme.statusReading
            }

            LoanSection {
                Layout.fillWidth: true
                heading: Theme.tr("Borrowed")
                hint: Theme.tr("Books here that belong to somebody else")
                rows: root.ofDirection(root.openLoans, "borrowed")
                accent: Theme.statusPlanned
            }

            LoanSection {
                Layout.fillWidth: true
                visible: root.showHistory
                heading: Theme.tr("Returned")
                hint: Theme.tr("Loans that have come back")
                rows: root.pastLoans
                accent: Theme.textSecondary
                closed: true
            }

            EmptyState {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingXXL
                visible: root.openLoans.length === 0 && !root.showHistory
                title: Theme.tr("Nothing is out on loan")
                hint: Theme.tr("Right-click a book, or open it, to record that it changed hands.")
            }

            Item { Layout.preferredHeight: Theme.spacingXXL }
        }
    }

    /**
     * One titled block of loan rows.
     *
     * An inline component rather than three near-identical copies: the three
     * sections differ only in their heading, their accent and whether the rows
     * are still open, and that is exactly the difference a component should
     * carry.
     */
    component LoanSection: ColumnLayout {
        id: section

        property string heading: ""
        property string hint: ""
        property var rows: []
        property color accent: Theme.primary
        /** Returned loans: no action, and the dates read differently. */
        property bool closed: false

        spacing: Theme.spacingSmall
        visible: rows.length > 0 || closed

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSmall

            SectionLabel { text: section.heading }

            Rectangle {
                Layout.preferredWidth: countLabel.width + 14
                Layout.preferredHeight: 18
                radius: Theme.radiusPill
                color: section.accent
                opacity: 0.18

                Text {
                    id: countLabel
                    anchors.centerIn: parent
                    text: section.rows.length
                    color: Theme.textOnSurface
                    font.pixelSize: Theme.fontSizeSection
                    font.bold: true
                }
            }

            Item { Layout.fillWidth: true }
        }

        Text {
            Layout.fillWidth: true
            text: section.hint
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeSmall
            visible: section.rows.length > 0
        }

        Text {
            Layout.fillWidth: true
            Layout.bottomMargin: Theme.spacingSmall
            text: Theme.tr("Nothing here")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeSmall
            font.italic: true
            visible: section.rows.length === 0
        }

        Repeater {
            model: section.rows

            Panel {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 76
                interactive: true
                accent: section.accent

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.cardPadding
                    spacing: Theme.spacingMedium

                    Rectangle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 52
                        radius: 4
                        color: Theme.background
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: modelData.coverImagePath !== ""
                                    ? "file://" + modelData.coverImagePath : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: status === Image.Ready
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            text: modelData.title
                            color: Theme.textOnSurface
                            font.pixelSize: Theme.fontSizeMedium
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.author
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: modelData.note !== ""
                            text: modelData.note
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSection
                            font.italic: true
                            elide: Text.ElideRight
                        }
                    }

                    ColumnLayout {
                        Layout.preferredWidth: 200
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            text: (modelData.direction === "lent"
                                   ? Theme.tr("with") : Theme.tr("from")) + " " + modelData.counterparty
                            color: section.accent
                            font.pixelSize: Theme.fontSizeMedium
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: section.closed
                                  ? modelData.loanedOn + " → " + modelData.returnedOn
                                    + "  (" + modelData.days + " " + Theme.tr("days") + ")"
                                  : modelData.loanedOn + "  ·  " + modelData.days + " "
                                    + Theme.tr("days")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSection
                            elide: Text.ElideRight
                        }
                    }

                    AppButton {
                        visible: !section.closed
                        text: Theme.tr("Returned")
                        variant: "outline"
                        onClicked: loans.endLoan(modelData.id, "")
                    }

                    AppButton {
                        visible: section.closed
                        text: Theme.tr("Delete")
                        variant: "ghost"
                        onClicked: loans.deleteLoan(modelData.id)
                    }
                }
            }
        }
    }
}
