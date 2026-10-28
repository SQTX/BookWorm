import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import BookWorm

/**
 * Record that a book changed hands.
 *
 * One dialog for both directions rather than two, because the fields are the
 * same and only the preposition differs: a book goes *to* somebody or comes
 * *from* somebody. Which one it is picks the wording, and nothing else.
 *
 * The name field completes against people already entered. Lending is repetitive
 * — the same handful of friends, over years — and retyping a name is how the
 * same person ends up in the list three times, spelled three ways.
 */
Dialog {
    id: root

    property int bookId: -1
    property string bookTitle: ""

    /** "lent" — you gave it away. "borrowed" — it is not yours. */
    property string direction: "lent"

    /** Emitted after a loan is written, so the caller can refresh. */
    signal saved()
    /** The book already has an open loan; the caller shows the message. */
    signal refused()

    title: Theme.tr("Lending")
    modal: true
    anchors.centerIn: Overlay.overlay
    closePolicy: Dialog.NoAutoClose
    width: 460

    background: Panel { elevated: true }

    function openFor(id, title, dir) {
        root.bookId = id;
        root.bookTitle = title;
        root.direction = dir || "lent";
        personField.text = "";
        noteField.text = "";
        dateField.text = new Date().toISOString().substring(0, 10);
        root.open();
        personField.forceActiveFocus();
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingMedium

        Text {
            Layout.fillWidth: true
            text: root.bookTitle
            color: Theme.textOnSurface
            font.pixelSize: Theme.fontSizeLarge
            font.bold: true
            elide: Text.ElideRight
        }

        SectionLabel { text: Theme.tr("Direction") }

        Row {
            spacing: Theme.spacingSmall

            Chip {
                text: Theme.tr("I lent it out")
                selected: root.direction === "lent"
                onClicked: root.direction = "lent"
            }
            Chip {
                text: Theme.tr("I borrowed it")
                selected: root.direction === "borrowed"
                onClicked: root.direction = "borrowed"
            }
        }

        SectionLabel {
            text: root.direction === "lent" ? Theme.tr("Who has it") : Theme.tr("Whose is it")
        }

        TextField {
            id: personField
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.controlHeight
            placeholderText: Theme.tr("Name")
            // Only completes; typing a name nobody has used yet must stay
            // possible, so nothing here rejects an unknown value.
            onTextEdited: {
                var all = loans.people();
                nameSuggestions.model = text.length === 0 ? [] : all.filter(function(p) {
                    return p.toLowerCase().indexOf(text.toLowerCase()) === 0 && p !== text;
                });
            }
            Keys.onReturnPressed: saveButton.clicked()
        }

        Flow {
            Layout.fillWidth: true
            spacing: Theme.spacingSmall
            visible: nameSuggestions.model.length > 0

            Repeater {
                id: nameSuggestions
                model: []
                Chip {
                    required property string modelData
                    text: modelData
                    onClicked: {
                        personField.text = modelData;
                        nameSuggestions.model = [];
                    }
                }
            }
        }

        SectionLabel { text: Theme.tr("Date") }

        TextField {
            id: dateField
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.controlHeight
            placeholderText: "YYYY-MM-DD"
            inputMask: "9999-99-99"
        }

        SectionLabel { text: Theme.tr("Note") + " (" + Theme.tr("optional") + ")" }

        TextField {
            id: noteField
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.controlHeight
            placeholderText: Theme.tr("Anything worth remembering")
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacingSmall
            spacing: Theme.spacingSmall

            Item { Layout.fillWidth: true }

            AppButton {
                text: Theme.tr("Cancel")
                variant: "ghost"
                onClicked: root.close()
            }

            AppButton {
                id: saveButton
                text: Theme.tr("Save")
                variant: "primary"
                enabled: personField.text.trim().length > 0
                onClicked: {
                    if (!enabled)
                        return;
                    var ok = loans.startLoan(root.bookId, root.direction,
                                             personField.text, dateField.text,
                                             noteField.text);
                    root.close();
                    if (ok)
                        root.saved();
                    else
                        root.refused();
                }
            }
        }
    }
}
