import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import WormBook

Item {
    id: challengesPage

    property var challenges: []
    property int expandedId: -1

    Component.onCompleted: loadChallenges()

    Connections {
        target: bookController
        function onBooksChanged() { loadChallenges() }
    }

    function loadChallenges() {
        challenges = bookController.getChallenges();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingXL
        spacing: Theme.spacingLarge

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingLarge

            Text {
                text: "Challenges"
                color: Theme.textOnBackground
                font.pixelSize: Theme.fontSizeHeader
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            RoundButton {
                text: "+"
                font.pixelSize: 18
                font.bold: true
                width: 36; height: 36
                Material.background: Theme.primary
                Material.foreground: Theme.textOnPrimary
                onClicked: addChallengeDialog.open()
            }
        }

        // Challenge list
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: challengeColumn.implicitHeight
            clip: true
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: challengeColumn
                width: parent.width
                spacing: Theme.spacingMedium

                Repeater {
                    model: challengesPage.challenges

                    Rectangle {
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        implicitHeight: cardContent.implicitHeight + Theme.spacingLarge * 2
                        radius: Theme.radiusMedium
                        color: Theme.surface

                        ColumnLayout {
                            id: cardContent
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Theme.spacingLarge
                            spacing: Theme.spacingMedium

                            // Top row: name + deadline + delete
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingMedium

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: Theme.textOnSurface
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                // Deadline badge
                                Rectangle {
                                    implicitWidth: deadlineText.implicitWidth + Theme.spacingLarge
                                    implicitHeight: 24
                                    radius: 12
                                    color: {
                                        var dl = new Date(modelData.deadline);
                                        var now = new Date();
                                        if (modelData.progress >= 1.0) return Theme.statusRead;
                                        if (dl < now) return Theme.error;
                                        return Theme.surfaceVariant;
                                    }

                                    Text {
                                        id: deadlineText
                                        anchors.centerIn: parent
                                        text: {
                                            if (modelData.progress >= 1.0) return "\u2714 Completed";
                                            var dl = new Date(modelData.deadline);
                                            var now = new Date();
                                            if (dl < now) return "Expired";
                                            return "Due: " + modelData.deadline;
                                        }
                                        color: {
                                            if (modelData.progress >= 1.0) return "#000000";
                                            var dl = new Date(modelData.deadline);
                                            var now = new Date();
                                            if (dl < now) return "#FFFFFF";
                                            return Theme.textSecondary;
                                        }
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.bold: true
                                    }
                                }

                                ToolButton {
                                    text: "\u2715"
                                    font.pixelSize: 12
                                    Material.foreground: Theme.error
                                    onClicked: {
                                        bookController.deleteChallenge(modelData.id);
                                        challengesPage.loadChallenges();
                                    }
                                }
                            }

                            // Progress info
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingMedium

                                Text {
                                    text: modelData.currentCount + " / " + modelData.targetBooks + " books"
                                    color: Theme.textOnSurface
                                    font.pixelSize: Theme.fontSizeMedium
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: Math.round(modelData.progress * 100) + "%"
                                    color: modelData.progress >= 1.0 ? Theme.statusRead : Theme.primary
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.bold: true
                                }
                            }

                            // Progress bar
                            Rectangle {
                                Layout.fillWidth: true
                                height: 8
                                radius: 4
                                color: Theme.surfaceVariant

                                Rectangle {
                                    width: parent.width * modelData.progress
                                    height: parent.height
                                    radius: 4
                                    color: modelData.progress >= 1.0 ? Theme.statusRead : Theme.primary

                                    Behavior on width { NumberAnimation { duration: 300 } }
                                }
                            }

                            // Period info
                            Text {
                                text: modelData.createdAt + "  \u2192  " + modelData.deadline
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            // Expand/collapse books button
                            Rectangle {
                                Layout.fillWidth: true
                                height: 28
                                radius: Theme.radiusSmall
                                color: expandBtn.containsMouse ? Theme.surfaceVariant : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: challengesPage.expandedId === modelData.id
                                          ? "\u25B2 Hide books" : "\u25BC Show books (" + modelData.currentCount + ")"
                                    color: Theme.primary
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                MouseArea {
                                    id: expandBtn
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        challengesPage.expandedId =
                                            challengesPage.expandedId === modelData.id ? -1 : modelData.id;
                                    }
                                }
                            }

                            // Books list (expanded)
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                visible: challengesPage.expandedId === modelData.id

                                Repeater {
                                    model: challengesPage.expandedId === modelData.id
                                           ? bookController.getBooksForChallenge(modelData.id) : []

                                    Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: 32
                                        radius: Theme.radiusSmall
                                        color: Theme.surfaceVariant

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Theme.spacingMedium
                                            anchors.rightMargin: Theme.spacingMedium
                                            spacing: Theme.spacingMedium

                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.title
                                                color: Theme.textOnSurface
                                                font.pixelSize: Theme.fontSizeMedium
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                text: modelData.author
                                                color: Theme.textSecondary
                                                font.pixelSize: Theme.fontSizeSmall
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                text: modelData.endDate
                                                color: Theme.textSecondary
                                                font.pixelSize: Theme.fontSizeSmall
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Empty state
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Theme.spacingXL * 2
                    visible: challengesPage.challenges.length === 0
                    text: "No challenges yet. Click + to create one!"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeLarge
                }
            }
        }
    }

    // Add challenge dialog
    Dialog {
        id: addChallengeDialog
        title: "New Challenge"
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        anchors.centerIn: parent
        width: 400
        Material.theme: Material.Dark
        Material.accent: Theme.primary

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.spacingMedium

            TextField {
                id: challengeNameField
                Layout.fillWidth: true
                placeholderText: "Challenge name (e.g. Summer Reading)"
                Material.accent: Theme.primary
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingMedium

                Text {
                    text: "Target:"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeMedium
                }

                SpinBox {
                    id: challengeTargetField
                    from: 1; to: 999
                    value: 10
                    editable: true
                    Material.accent: Theme.primary
                }

                Text {
                    text: "books"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeMedium
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingMedium

                Text {
                    text: "Deadline:"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeMedium
                }

                TextField {
                    id: challengeDeadlineField
                    Layout.fillWidth: true
                    placeholderText: "YYYY-MM-DD"
                    inputMask: "9999-99-99"
                    Material.accent: Theme.primary
                }
            }
        }

        onAccepted: {
            if (challengeNameField.text.trim() !== "" && challengeDeadlineField.text.trim() !== "") {
                bookController.addChallenge(
                    challengeNameField.text,
                    challengeTargetField.value,
                    challengeDeadlineField.text
                );
                challengeNameField.text = "";
                challengeTargetField.value = 10;
                challengeDeadlineField.text = "";
                challengesPage.loadChallenges();
            }
        }
    }
}
