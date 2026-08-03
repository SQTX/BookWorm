pragma Singleton
import QtQuick
import "translations.js" as Translations

QtObject {
    // Active theme key
    property string currentTheme: "minimalist_dark"

    // Language
    property string language: "en"

    function tr(key) {
        // Reading 'language' creates QML binding dependency
        return Translations.translate(key, language);
    }

    function typePlural(typeKey) {
        return Translations.typePlural(typeKey, language);
    }

    function typeLabel(typeKey) {
        return Translations.typeLabel(typeKey, language);
    }

    function getMonthLabels() {
        return Translations.monthLabels(language);
    }

    function getDayLabels() {
        return Translations.dayLabels(language);
    }

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

    // A divider is too heavy for a card outline — cards sit on the background and
    // only need to be separated from it, not boxed in.
    property color outline: Qt.rgba(divider.r, divider.g, divider.b, 0.55)

    // ── Interaction ──

    // Derived from the text colour so it works in all three themes without adding
    // per-theme literals: a faint wash of the foreground over whatever is beneath.
    property color hover: Qt.rgba(textOnSurface.r, textOnSurface.g, textOnSurface.b, 0.07)
    property color pressed: Qt.rgba(textOnSurface.r, textOnSurface.g, textOnSurface.b, 0.13)
    property color shadow: Qt.rgba(0, 0, 0, isDark ? 0.45 : 0.16)

    // ── Destructive actions ──
    // These were repeated as literals in six places (reset, restore, both confirm
    // dialogs). Same values as before — only the definition moved here.
    readonly property color danger:      "#B71C1C"
    readonly property color dangerHover: "#D32F2F"
    readonly property color dangerText:  "#FFFFFF"

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

    // ── Priority ──

    // Kept red-leaning (hue ~20°) so it stays distinct from statusPlanned's
    // tan (~40°), which a flagged planned book shows on hover.
    property color priority: {
        switch (currentTheme) {
            case "minimalist_dark":  return "#DC6938";
            case "minimalist_light": return "#C1702A";
            case "classic":          return "#D5683A";
            default:                 return "#DC6938";
        }
    }

    // ── Typography ──

    readonly property int fontSizeSection: 11   // uppercase section labels
    readonly property int fontSizeSmall:  12
    readonly property int fontSizeMedium: 14
    readonly property int fontSizeLarge:  18
    readonly property int fontSizeTitle:  24
    // 32px pushed the page title into banner territory and cost ~20px of vertical
    // space on every screen before any content appeared.
    readonly property int fontSizeHeader: 26

    // ── Spacing ──

    readonly property int spacingXS:     2
    readonly property int spacingSmall:  4
    readonly property int spacingMedium: 8
    readonly property int spacingLarge:  16
    readonly property int spacingXL:     24
    readonly property int spacingXXL:    32

    // ── Layout metrics ──

    // Every page anchors its content at this margin so the five views line up with
    // each other when you switch between them. Kept tight on purpose: this is a
    // dense data app, not a marketing page, and 32px on every edge ate a visible
    // slice of the grid.
    readonly property int pageMargin:      20
    // Gap between the header, the toolbar and the content beneath them.
    readonly property int sectionGap:      12
    // Text and charts stop growing past this. Without it a maximised window on a
    // wide display stretches a two-column layout into unreadable full-width runs.
    readonly property int contentMaxWidth: 1440
    readonly property int controlHeight:   36
    readonly property int chipHeight:      28

    // ── Shapes ──

    readonly property int radiusSmall:   4
    readonly property int radiusMedium:  8
    readonly property int radiusLarge:   16
    readonly property int radiusControl: 8
    readonly property int radiusCard:    12
    readonly property int radiusPill:    999

    // ── Motion ──

    readonly property int durationFast:   120   // hover / press feedback
    readonly property int durationMedium: 200   // page and dialog transitions
    readonly property int durationSlow:   320   // entrances that should be noticed

    readonly property int easeOut:   Easing.OutCubic
    readonly property int easeInOut: Easing.InOutQuad
    readonly property int easeBack:  Easing.OutBack

    // ── Helpers ──

    // Swatches for the theme picker in Settings. These mirror the three palettes
    // above; keep them in sync when a palette changes.
    function previewColors(themeKey) {
        switch (themeKey) {
            case "minimalist_light": return ["#E8E8E8", "#F5F5F5", "#554940"];
            case "classic":          return ["#1D1617", "#2A2225", "#9F6932"];
            default:                 return ["#121216", "#23242C", "#949C9E"];
        }
    }

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
            case "reading":   return tr("Reading");
            case "read":      return tr("Read");
            case "planned":   return tr("Planned");
            case "abandoned": return tr("Abandoned");
            default:          return status;
        }
    }
}
