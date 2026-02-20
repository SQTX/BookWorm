pragma Singleton
import QtQuick

QtObject {
    // Core palette (dark theme)
    readonly property color background:      "#121212"
    readonly property color surface:         "#1E1E2E"
    readonly property color surfaceVariant:  "#2A2A3C"
    readonly property color primary:         "#BB86FC"
    readonly property color primaryVariant:  "#3700B3"
    readonly property color secondary:       "#03DAC6"
    readonly property color error:           "#CF6679"
    readonly property color textOnBackground: "#E1E1E6"
    readonly property color textOnSurface:   "#E1E1E6"
    readonly property color textOnPrimary:   "#000000"
    readonly property color textSecondary:   "#A0A0B0"
    readonly property color divider:         "#2C2C3A"

    // Status colors
    readonly property color statusReading:   "#4FC3F7"
    readonly property color statusRead:      "#81C784"
    readonly property color statusPlanned:   "#FFB74D"

    // Typography
    readonly property int fontSizeSmall:     12
    readonly property int fontSizeMedium:    14
    readonly property int fontSizeLarge:     18
    readonly property int fontSizeTitle:     24
    readonly property int fontSizeHeader:    32

    // Spacing
    readonly property int spacingSmall:      4
    readonly property int spacingMedium:     8
    readonly property int spacingLarge:      16
    readonly property int spacingXL:         24

    // Shapes
    readonly property int radiusSmall:       4
    readonly property int radiusMedium:      8
    readonly property int radiusLarge:       16

    function statusColor(status) {
        switch(status) {
            case "reading": return statusReading;
            case "read":    return statusRead;
            case "planned": return statusPlanned;
            default:        return textSecondary;
        }
    }

    function statusLabel(status) {
        switch(status) {
            case "reading": return "Reading";
            case "read":    return "Read";
            case "planned": return "Planned";
            default:        return status;
        }
    }
}
