import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import BookWorm

Item {
    id: sessionsPage

    Text {
        anchors.centerIn: parent
        text: Theme.tr("No reading sessions yet")
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSizeLarge
    }
}
