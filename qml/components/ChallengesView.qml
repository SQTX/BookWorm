import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import BookWorm

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

    // Unit shown next to a challenge's numbers, per metric.
    function metricUnit(metric) {
        if (metric === "pages") return Theme.tr("pages");
        if (metric === "pages_per_day") return Theme.tr("pg/day");
        return Theme.tr("books");
    }

    // Current value formatted for display (the per-day average is rounded).
    function fmtCurrent(md) {
        return md.metric === "pages_per_day" ? Math.round(md.currentValue) : md.currentValue;
    }

    // Human label for a metric, used in the card and the create dialog.
    function metricLabel(metric) {
        if (metric === "pages") return Theme.tr("Pages read");
        if (metric === "pages_per_day") return Theme.tr("Pages per day");
        return Theme.tr("Books read");
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
                text: Theme.tr("Challenges")
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
                                            if (modelData.progress >= 1.0) return "\u2714 " + Theme.tr("Completed");
                                            var dl = new Date(modelData.deadline);
                                            var now = new Date();
                                            if (dl < now) return Theme.tr("Expired");
                                            return Theme.tr("Due:") + " " + modelData.deadline;
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
                                    text: challengesPage.fmtCurrent(modelData) + " / " + modelData.targetValue
                                          + " " + challengesPage.metricUnit(modelData.metric)
                                    color: Theme.textOnSurface
                                    font.pixelSize: Theme.fontSizeMedium
                                }

                                // Metric type chip
                                Rectangle {
                                    implicitWidth: metricChip.implicitWidth + Theme.spacingMedium
                                    implicitHeight: 20
                                    radius: 10
                                    color: Theme.surfaceVariant

                                    Text {
                                        id: metricChip
                                        anchors.centerIn: parent
                                        text: challengesPage.metricLabel(modelData.metric)
                                        color: Theme.textSecondary
                                        font.pixelSize: Theme.fontSizeSmall - 1
                                    }
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
                                            text: "\u23F1 " + Theme.tr("Elapsed:")
                                            color: Theme.textSecondary
                                            font.pixelSize: Theme.fontSizeSmall
                                        }

                                        Text {
                                            text: {
                                                var start = new Date(modelData.createdAt);
                                                var now = new Date();
                                                var diffMs = now - start;
                                                var days = Math.floor(diffMs / (1000 * 60 * 60 * 24));
                                                if (days < 1) return Theme.tr("< 1 day");
                                                if (days === 1) return Theme.tr("1 day");
                                                if (days < 30) return days + " " + Theme.tr("days");
                                                var months = Math.floor(days / 30);
                                                var remDays = days % 30;
                                                if (months === 1) return Theme.tr("1 month") + (remDays > 0 ? ", " + remDays + "d" : "");
                                                return months + " " + Theme.tr("months") + (remDays > 0 ? ", " + remDays + "d" : "");
                                            }
                                            color: Theme.textOnSurface
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.bold: true
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: "\u23F3 " + Theme.tr("Remaining:")
                                            color: Theme.textSecondary
                                            font.pixelSize: Theme.fontSizeSmall
                                        }

                                        Text {
                                            text: {
                                                var dl = new Date(modelData.deadline);
                                                var now = new Date();
                                                var diffMs = dl - now;
                                                if (diffMs <= 0) return Theme.tr("expired");
                                                var days = Math.ceil(diffMs / (1000 * 60 * 60 * 24));
                                                if (days === 1) return Theme.tr("1 day");
                                                if (days < 30) return days + " " + Theme.tr("days");
                                                var months = Math.floor(days / 30);
                                                var remDays = days % 30;
                                                if (months === 1) return Theme.tr("1 month") + (remDays > 0 ? ", " + remDays + "d" : "");
                                                return months + " " + Theme.tr("months") + (remDays > 0 ? ", " + remDays + "d" : "");
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

                                    // Remaining to the goal (metric-aware)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingMedium
                                        visible: modelData.progress < 1.0

                                        Text {
                                            text: "\u{1F3AF} " + Theme.tr("To go:")
                                            color: Theme.textSecondary
                                            font.pixelSize: Theme.fontSizeSmall
                                        }

                                        Text {
                                            text: {
                                                if (modelData.metric === "pages_per_day") {
                                                    // Average is a rate, not a countdown \u2014 show target vs current pace.
                                                    return Theme.tr("target") + " " + modelData.targetValue + " "
                                                           + Theme.tr("pg/day") + " \u00B7 " + Theme.tr("now")
                                                           + " " + Math.round(modelData.currentValue);
                                                }
                                                var left = Math.max(0, modelData.targetValue - modelData.currentValue);
                                                return left + " " + challengesPage.metricUnit(modelData.metric)
                                                       + " " + Theme.tr("left");
                                            }
                                            color: Theme.textOnSurface
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
                                          ? "\u25B2 " + Theme.tr("Hide books") : "\u25BC " + Theme.tr("Show books")
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
                    text: Theme.tr("No challenges yet. Click + to create one!")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeLarge
                }
            }
        }
    }

    // ── Add challenge dialog ──
    Dialog {
        id: addChallengeDialog
        title: ""
        modal: true
        standardButtons: Dialog.NoButton
        anchors.centerIn: parent
        width: Math.min(500, parent.width - 48)
        padding: 0

        // Two ways to set the deadline: a period from today, or an explicit date.
        property bool periodMode: true

        // Deadline the current inputs would produce, as a yyyy-MM-dd string.
        function previewDeadline() {
            if (!periodMode)
                return dateField.text;
            var d = new Date();
            var c = countSpin.value;
            var u = unitCombo.currentValue;
            if (u === "day")        d.setDate(d.getDate() + c);
            else if (u === "month") d.setMonth(d.getMonth() + c);
            else                    d.setFullYear(d.getFullYear() + c);
            return Qt.formatDate(d, "yyyy-MM-dd");
        }

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
            metricCombo.currentIndex = 0;
            targetSpin.value = 5;
            periodMode = true;
            unitCombo.currentIndex = 1;   // months
            countSpin.value = 3;
            var d = new Date();
            d.setMonth(d.getMonth() + 3);
            dateField.text = Qt.formatDate(d, "yyyy-MM-dd");
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Header
            Text {
                Layout.topMargin: Theme.spacingLarge
                Layout.leftMargin: Theme.spacingXL
                text: Theme.tr("New Challenge")
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
                    text: Theme.tr("Challenge name")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                }

                TextField {
                    id: challengeNameField
                    Layout.fillWidth: true
                    placeholderText: Theme.tr("e.g. Summer Reading")
                    font.pixelSize: Theme.fontSizeMedium
                    Material.accent: Theme.primary
                }

                // Metric type
                Text {
                    text: Theme.tr("Challenge type")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                }

                ComboBox {
                    id: metricCombo
                    Layout.fillWidth: true
                    font.pixelSize: Theme.fontSizeMedium
                    Material.accent: Theme.primary
                    textRole: "key"
                    valueRole: "value"
                    model: ListModel {
                        Component.onCompleted: {
                            append({ key: Theme.tr("Books read"),   value: "books" });
                            append({ key: Theme.tr("Pages read"),   value: "pages" });
                            append({ key: Theme.tr("Pages per day"), value: "pages_per_day" });
                        }
                    }
                }

                // Target value
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: metricCombo.currentValue === "pages_per_day"
                              ? Theme.tr("Target pages per day")
                              : metricCombo.currentValue === "pages"
                                ? Theme.tr("Number of pages")
                                : Theme.tr("Number of books")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    SpinBox {
                        id: targetSpin
                        editable: true
                        from: 1
                        to: 1000000
                        value: 5
                        Material.accent: Theme.primary
                    }
                }

                // Timeframe mode
                Text {
                    text: Theme.tr("Timeframe")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                }

                Row {
                    spacing: Theme.spacingSmall

                    Repeater {
                        model: [
                            { key: "Period",   period: true },
                            { key: "End date", period: false }
                        ]
                        Rectangle {
                            required property var modelData
                            readonly property bool sel: addChallengeDialog.periodMode === modelData.period
                            width: modeChipText.implicitWidth + Theme.spacingLarge
                            height: 30
                            radius: 15
                            color: sel ? Theme.primary : Theme.surfaceVariant
                            border.width: 1
                            border.color: sel ? "transparent" : Theme.divider

                            Text {
                                id: modeChipText
                                anchors.centerIn: parent
                                text: Theme.tr(parent.modelData.key)
                                color: parent.sel ? Theme.textOnPrimary : Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: parent.sel
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: addChallengeDialog.periodMode = parent.modelData.period
                            }
                        }
                    }
                }

                // Period inputs (unit + count)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingMedium
                    visible: addChallengeDialog.periodMode

                    SpinBox {
                        id: countSpin
                        editable: true
                        from: 1
                        to: 999
                        value: 3
                        Material.accent: Theme.primary
                    }

                    ComboBox {
                        id: unitCombo
                        Layout.fillWidth: true
                        font.pixelSize: Theme.fontSizeMedium
                        Material.accent: Theme.primary
                        textRole: "key"
                        valueRole: "value"
                        model: ListModel {
                            Component.onCompleted: {
                                append({ key: Theme.tr("days"),   value: "day" });
                                append({ key: Theme.tr("months"), value: "month" });
                                append({ key: Theme.tr("years"),  value: "year" });
                            }
                        }
                    }
                }

                // Explicit end date
                TextField {
                    Layout.fillWidth: true
                    id: dateField
                    visible: !addChallengeDialog.periodMode
                    placeholderText: "yyyy-MM-dd"
                    inputMask: "9999-99-99;_"
                    font.pixelSize: Theme.fontSizeMedium
                    Material.accent: Theme.primary
                }

                // Preview: resulting deadline
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: previewText.implicitHeight + Theme.spacingMedium * 2
                    radius: Theme.radiusSmall
                    color: Theme.surfaceVariant

                    Text {
                        id: previewText
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacingMedium
                        text: Theme.tr("Deadline:") + " " + addChallengeDialog.previewDeadline()
                        color: Theme.textOnSurface
                        font.pixelSize: Theme.fontSizeMedium
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
                    text: Theme.tr("Cancel")
                    flat: true
                    Material.foreground: Theme.textSecondary
                    onClicked: addChallengeDialog.reject()
                }

                Button {
                    text: Theme.tr("Create")
                    enabled: challengeNameField.text.trim() !== ""
                    Material.background: enabled ? Theme.primary : Theme.surfaceVariant
                    Material.foreground: enabled ? Theme.textOnPrimary : Theme.textSecondary
                    onClicked: {
                        // Editable SpinBoxes don't commit typed text until focus-loss.
                        targetSpin.value = targetSpin.valueFromText(targetSpin.contentItem.text, targetSpin.locale);
                        countSpin.value = countSpin.valueFromText(countSpin.contentItem.text, countSpin.locale);

                        var metric = metricCombo.currentValue;
                        var target = targetSpin.value;
                        var ok;
                        if (addChallengeDialog.periodMode)
                            ok = bookController.addChallenge(challengeNameField.text.trim(), metric,
                                                             target, "", unitCombo.currentValue, countSpin.value);
                        else
                            ok = bookController.addChallenge(challengeNameField.text.trim(), metric,
                                                             target, dateField.text, "custom", 0);
                        if (ok) {
                            challengesPage.loadChallenges();
                            addChallengeDialog.close();
                        }
                    }
                }
            }
        }
    }
}
