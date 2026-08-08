import QtQuick
import QtQuick.Effects
import BookWorm

// A surface that content sits on: cards, list rows, chart containers.
//
// Every view used to hand-roll `Rectangle { radius; border }`, which is why the
// panels drifted apart — three radii and two border colours across the codebase.
//
// Hover state comes from a HoverHandler rather than a MouseArea: a MouseArea here
// would sit above the caller's own children and swallow their hover events.
Rectangle {
    id: root

    // Opt in to hover feedback. Leave false for static containers.
    property bool interactive: false
    // Drawn instead of the outline while hovered.
    property color accent: Theme.primary
    // Costs a render layer — reserve it for elements that float above the page
    // (dialogs, popups), not for every card in a grid.
    property bool elevated: false

    readonly property bool hovered: hoverHandler.hovered

    color: Theme.surface
    radius: Theme.radiusCard
    border.width: 1
    border.color: (interactive && hovered) ? accent : Theme.outline

    Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }
    Behavior on color { ColorAnimation { duration: Theme.durationFast } }

    HoverHandler {
        id: hoverHandler
        enabled: root.interactive
        cursorShape: undefined
    }

    layer.enabled: root.elevated
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Theme.shadow
        shadowBlur: 0.7
        shadowVerticalOffset: 6
    }
}
