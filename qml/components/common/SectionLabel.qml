import QtQuick
import BookWorm

// The small uppercase label that opens a section ("LANGUAGE", "READING", …).
// Uppercasing happens through font.capitalization so translations stay readable
// in translations.js and Polish diacritics survive.
Text {
    property color accent: Theme.textSecondary

    color: accent
    font.pixelSize: Theme.fontSizeSection
    font.bold: true
    font.letterSpacing: 1.2
    font.capitalization: Font.AllUppercase
    verticalAlignment: Text.AlignVCenter
}
