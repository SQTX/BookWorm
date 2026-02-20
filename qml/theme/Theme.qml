pragma Singleton
import QtQuick

QtObject {
    // Active theme key
    property string currentTheme: "minimalist_dark"

    // Helper for Material.theme binding in Main.qml
    property bool isDark: currentTheme !== "minimalist_light"

    function setTheme(name) {
        currentTheme = name;
    }

    // ── Core palette ──

    property color background: {
        switch (currentTheme) {
            case "minimalist_dark":  return "#121216";
            case "minimalist_light": return "#E8E8E8";
            case "classic":          return "#1D1617";
            default:                 return "#121216";
        }
    }

    property color surface: {
        switch (currentTheme) {
            case "minimalist_dark":  return "#23242C";
            case "minimalist_light": return "#F5F5F5";
            case "classic":          return "#2A2225";
            default:                 return "#23242C";
        }
    }

    property color surfaceVariant: {
        switch (currentTheme) {
            case "minimalist_dark":  return "#33363D";
            case "minimalist_light": return "#D7E5F0";
            case "classic":          return "#362D30";
            default:                 return "#33363D";
        }
    }

    property color primary: {
        switch (currentTheme) {
            case "minimalist_dark":  return "#949C9E";
            case "minimalist_light": return "#554940";
            case "classic":          return "#9F6932";
            default:                 return "#949C9E";
        }
    }

    property color primaryVariant: {
        switch (currentTheme) {
            case "minimalist_dark":  return "#636564";
            case "minimalist_light": return "#3A322C";
            case "classic":          return "#7A5025";
            default:                 return "#636564";
        }
    }

    property color secondary: {
        switch (currentTheme) {
            case "minimalist_dark":  return "#787675";
            case "minimalist_light": return "#879A77";
            case "classic":          return "#C4A265";
            default:                 return "#787675";
        }
    }

    property color error: {
        switch (currentTheme) {
            case "minimalist_dark":  return "#CF6679";
            case "minimalist_light": return "#B44040";
            case "classic":          return "#8B3A3A";
            default:                 return "#CF6679";
        }
    }

    // ── Text ──

    property color textOnBackground: {
        switch (currentTheme) {
            case "minimalist_dark":  return "#E1E1E6";
            case "minimalist_light": return "#1A1A1A";
            case "classic":          return "#D4C5B0";
            default:                 return "#E1E1E6";
        }
    }

    property color textOnSurface: {
        switch (currentTheme) {
            case "minimalist_dark":  return "#E1E1E6";
            case "minimalist_light": return "#1A1A1A";
            case "classic":          return "#D4C5B0";
            default:                 return "#E1E1E6";
        }
    }

    property color textOnPrimary: {
        switch (currentTheme) {
            case "minimalist_dark":  return "#121216";
            case "minimalist_light": return "#F5F5F5";
            case "classic":          return "#1D1617";
            default:                 return "#121216";
        }
    }

    property color textSecondary: {
        switch (currentTheme) {
            case "minimalist_dark":  return "#787675";
            case "minimalist_light": return "#73787C";
            case "classic":          return "#8A7E72";
            default:                 return "#787675";
        }
    }

    // ── Divider ──

    property color divider: {
        switch (currentTheme) {
            case "minimalist_dark":  return "#404443";
            case "minimalist_light": return "#C5C6C7";
            case "classic":          return "#443838";
            default:                 return "#404443";
        }
    }

    // ── Status colors ──

    property color statusReading: {
        switch (currentTheme) {
            case "minimalist_dark":  return "#7AAABA";
            case "minimalist_light": return "#5B8CA0";
            case "classic":          return "#5C8AAE";
            default:                 return "#7AAABA";
        }
    }

    property color statusRead: {
        switch (currentTheme) {
            case "minimalist_dark":  return "#8A9E8B";
            case "minimalist_light": return "#6B8A5E";
            case "classic":          return "#7A9A60";
            default:                 return "#8A9E8B";
        }
    }

    property color statusPlanned: {
        switch (currentTheme) {
            case "minimalist_dark":  return "#B0A080";
            case "minimalist_light": return "#C9AD93";
            case "classic":          return "#C4A265";
            default:                 return "#B0A080";
        }
    }

    property color statusAbandoned: {
        switch (currentTheme) {
            case "minimalist_dark":  return "#636564";
            case "minimalist_light": return "#73787C";
            case "classic":          return "#6A5A50";
            default:                 return "#636564";
        }
    }

    // ── Typography ──

    readonly property int fontSizeSmall:  12
    readonly property int fontSizeMedium: 14
    readonly property int fontSizeLarge:  18
    readonly property int fontSizeTitle:  24
    readonly property int fontSizeHeader: 32

    // ── Spacing ──

    readonly property int spacingSmall:  4
    readonly property int spacingMedium: 8
    readonly property int spacingLarge:  16
    readonly property int spacingXL:     24

    // ── Shapes ──

    readonly property int radiusSmall:  4
    readonly property int radiusMedium: 8
    readonly property int radiusLarge:  16

    // ── Helpers ──

    function statusColor(status) {
        switch (status) {
            case "reading":   return statusReading;
            case "read":      return statusRead;
            case "planned":   return statusPlanned;
            case "abandoned": return statusAbandoned;
            default:          return textSecondary;
        }
    }

    function statusLabel(status) {
        switch (status) {
            case "reading":   return "Reading";
            case "read":      return "Read";
            case "planned":   return "Planned";
            case "abandoned": return "Abandoned";
            default:          return status;
        }
    }
}
