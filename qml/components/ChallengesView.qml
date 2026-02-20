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

    // Timer to refresh elapsed time every minute
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: challengesPage.loadChallenges()
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

                            // ── Timer / Stats row ──
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: timerCol.implicitHeight + Theme.spacingMedium * 2
                                radius: Theme.radiusSmall
                                color: Theme.surfaceVariant

                                ColumnLayout {
                                    id: timerCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: Theme.spacingMedium
                                    spacing: 6

                                    // Elapsed time
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingMedium

                                        Text {
                                            text: "\u23F1 Elapsed:"
                                            color: Theme.textSecondary
                                            font.pixelSize: Theme.fontSizeSmall
                                        }

                                        Text {
                                            text: {
                                                var start = new Date(modelData.createdAt);
                                                var now = new Date();
                                                var diffMs = now - start;
                                                var days = Math.floor(diffMs / (1000 * 60 * 60 * 24));
                                                if (days < 1) return "< 1 day";
                                                if (days === 1) return "1 day";
                                                if (days < 30) return days + " days";
                                                var months = Math.floor(days / 30);
                                                var remDays = days % 30;
                                                if (months === 1) return "1 month" + (remDays > 0 ? ", " + remDays + "d" : "");
                                                return months + " months" + (remDays > 0 ? ", " + remDays + "d" : "");
                                            }
                                            color: Theme.textOnSurface
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.bold: true
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: "\u23F3 Remaining:"
                                            color: Theme.textSecondary
                                            font.pixelSize: Theme.fontSizeSmall
                                        }

                                        Text {
                                            text: {
                                                var dl = new Date(modelData.deadline);
                                                var now = new Date();
                                                var diffMs = dl - now;
                                                if (diffMs <= 0) return "expired";
                                                var days = Math.ceil(diffMs / (1000 * 60 * 60 * 24));
                                                if (days === 1) return "1 day";
                                                if (days < 30) return days + " days";
                                                var months = Math.floor(days / 30);
                                                var remDays = days % 30;
                                                if (months === 1) return "1 month" + (remDays > 0 ? ", " + remDays + "d" : "");
                                                return months + " months" + (remDays > 0 ? ", " + remDays + "d" : "");
                                            }
                                            color: {
                                                var dl = new Date(modelData.deadline);
                                                var now = new Date();
                                                var diffMs = dl - now;
                                                if (diffMs <= 0) return Theme.error;
                                                var days = Math.ceil(diffMs / (1000 * 60 * 60 * 24));
                                                if (days <= 7) return Theme.error;
                                                return Theme.textOnSurface;
                                            }
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.bold: true
                                        }
                                    }

                                    // Average pages per day needed
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingMedium
                                        visible: modelData.progress < 1.0

                                        Text {
                                            text: "\u{1F4D6} Avg pages/day to finish:"
                                            color: Theme.textSecondary
                                            font.pixelSize: Theme.fontSizeSmall
                                        }

                                        Text {
                                            text: {
                                                var dl = new Date(modelData.deadline);
                                                var now = new Date();
                                                var daysLeft = Math.max(1, Math.ceil((dl - now) / (1000 * 60 * 60 * 24)));
                                                var booksLeft = Math.max(0, modelData.targetBooks - modelData.currentCount);
                                                var avgPagesPerBook = 400;
                                                var totalPagesLeft = booksLeft * avgPagesPerBook;
                                                var pagesPerDay = Math.ceil(totalPagesLeft / daysLeft);
                                                if (booksLeft <= 0) return "\u2714 done!";
                                                return pagesPerDay + " pages/day (" + booksLeft + " books \u00D7 400 pp)";
                                            }
                                            color: {
                                                var dl = new Date(modelData.deadline);
                                                var now = new Date();
                                                var daysLeft = Math.max(1, Math.ceil((dl - now) / (1000 * 60 * 60 * 24)));
                                                var booksLeft = Math.max(0, modelData.targetBooks - modelData.currentCount);
                                                var pagesPerDay = Math.ceil((booksLeft * 400) / daysLeft);
                                                if (pagesPerDay > 100) return Theme.error;
                                                if (pagesPerDay > 50) return Theme.statusPlanned;
                                                return Theme.statusRead;
                                            }
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.bold: true
                                        }
                                    }
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

    // ── Add challenge dialog (2 sliders) ──
    Dialog {
        id: addChallengeDialog
        title: ""
        modal: true
        standardButtons: Dialog.NoButton
        anchors.centerIn: parent
        width: Math.min(480, parent.width - 48)
        padding: 0

        Material.theme: Theme.isDark ? Material.Dark : Material.Light
        Material.accent: Theme.primary

        background: Rectangle {
            radius: Theme.radiusLarge
            color: Theme.surface
            border.width: 1
            border.color: Theme.divider
        }

        onOpened: {
            challengeNameField.text = "";
            booksSlider.value = 5;
            monthsSlider.value = 3;
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Header
            Text {
                Layout.topMargin: Theme.spacingLarge
                Layout.leftMargin: Theme.spacingXL
                text: "New Challenge"
                color: Theme.textOnSurface
                font.pixelSize: Theme.fontSizeTitle
                font.bold: true
            }

            Rectangle { Layout.fillWidth: true; Layout.topMargin: Theme.spacingMedium; height: 1; color: Theme.divider }

            // Content
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: Theme.spacingXL
                spacing: Theme.spacingLarge

                // Name
                Text {
                    text: "Challenge name"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                }

                TextField {
                    id: challengeNameField
                    Layout.fillWidth: true
                    placeholderText: "e.g. Summer Reading"
                    font.pixelSize: Theme.fontSizeMedium
                    Material.accent: Theme.primary
                }

                // Books slider
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Number of books"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: Math.round(booksSlider.value)
                            color: Theme.primary
                            font.pixelSize: Theme.fontSizeLarge
                            font.bold: true
                        }
                    }

                    Slider {
                        id: booksSlider
                        Layout.fillWidth: true
                        from: 1; to: 30
                        stepSize: 1
                        value: 5
                        snapMode: Slider.SnapAlways
                        Material.accent: Theme.primary
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "1"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }
                        Item { Layout.fillWidth: true }
                        Text { text: "30"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }
                    }
                }

                // Months slider
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Duration (months)"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: {
                                var m = Math.round(monthsSlider.value);
                                return m + (m === 1 ? " month" : " months");
                            }
                            color: Theme.primary
                            font.pixelSize: Theme.fontSizeLarge
                            font.bold: true
                        }
                    }

                    Slider {
                        id: monthsSlider
                        Layout.fillWidth: true
                        from: 1; to: 12
                        stepSize: 1
                        value: 3
                        snapMode: Slider.SnapAlways
                        Material.accent: Theme.primary
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "1"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }
                        Item { Layout.fillWidth: true }
                        Text { text: "12"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeSmall }
                    }
                }

                // Preview: calculated deadline & avg pages/day
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: previewCol.implicitHeight + Theme.spacingMedium * 2
                    radius: Theme.radiusSmall
                    color: Theme.surfaceVariant

                    ColumnLayout {
                        id: previewCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingMedium
                        spacing: 4

                        Text {
                            text: {
                                var now = new Date();
                                var months = Math.round(monthsSlider.value);
                                // End of the target month: day 0 of next month = last day of target month
                                var deadline = new Date(now.getFullYear(), now.getMonth() + months + 1, 0);
                                return "Deadline: " + deadline.toISOString().split("T")[0];
                            }
                            color: Theme.textOnSurface
                            font.pixelSize: Theme.fontSizeMedium
                        }

                        Text {
                            text: {
                                var months = Math.round(monthsSlider.value);
                                var books = Math.round(booksSlider.value);
                                var days = months * 30;
                                var totalPages = books * 400;
                                var ppd = Math.ceil(totalPages / days);
                                return "\u2248 " + ppd + " pages/day (avg 400 pages/book)";
                            }
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.divider }

            // Footer
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Theme.spacingLarge
                spacing: Theme.spacingMedium

                Item { Layout.fillWidth: true }

                Button {
                    text: "Cancel"
                    flat: true
                    Material.foreground: Theme.textSecondary
                    onClicked: addChallengeDialog.reject()
                }

                Button {
                    text: "Create"
                    enabled: challengeNameField.text.trim() !== ""
                    Material.background: enabled ? Theme.primary : Theme.surfaceVariant
                    Material.foreground: enabled ? Theme.textOnPrimary : Theme.textSecondary
                    onClicked: {
                        var now = new Date();
                        var months = Math.round(monthsSlider.value);
                        // End of the target month
                        var deadline = new Date(now.getFullYear(), now.getMonth() + months + 1, 0);
                        var deadlineStr = deadline.toISOString().split("T")[0];

                        bookController.addChallenge(
                            challengeNameField.text.trim(),
                            Math.round(booksSlider.value),
                            deadlineStr
                        );
                        challengesPage.loadChallenges();
                        addChallengeDialog.close();
                    }
                }
            }
        }
    }
}
