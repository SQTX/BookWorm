import QtQuick
import QtQuick.Effects
import QtMultimedia
import BookWorm

/**
 * The unlock notification: artwork, title, one line of description, a sound.
 *
 * Top-right and self-dismissing, the shape a game console uses, because that
 * shape has already solved the problem — it is legible without being read,
 * ignorable while something else is happening, and gone before it is in the way.
 *
 * Queued rather than stacked. Several achievements can be earned by one action
 * (finishing a book can cross a book count, a page count and a series at once),
 * and three panels sliding in together is a wall rather than three moments.
 * They are shown one after another, each with its own entrance.
 *
 * Nothing here is interactive: it sits above the page and must not take a click
 * meant for what is underneath, so there is no MouseArea and the whole item is
 * invisible to the mouse when it is not showing.
 */
Item {
    id: root

    /** Where the panel rests once it has arrived. Also its width. */
    readonly property int panelWidth: 340
    readonly property int panelHeight: 88

    /** How long one notification stays on screen once it has slid in. */
    readonly property int dwellMs: 4200

    /** Waiting to be shown. Each entry is {title, description, icon}. */
    property var queue: []
    property bool showing: false

    width: panelWidth
    height: panelHeight
    // Never in the way: the whole thing is out of the hit-testing path unless a
    // notification is actually up, and even then it takes no input.
    visible: showing
    enabled: false

    /** Add one to the queue, and start the run if nothing is on screen. */
    function present(title, description, icon) {
        var pending = root.queue;
        pending.push({ title: title, description: description, icon: icon });
        root.queue = pending;

        if (!root.showing)
            root.next();
    }

    function next() {
        if (root.queue.length === 0) {
            root.showing = false;
            return;
        }

        var pending = root.queue;
        var item = pending.shift();
        root.queue = pending;

        titleText.text = Theme.tr(item.title);
        descriptionText.text = Theme.tr(item.description);
        artwork.source = item.icon;

        root.showing = true;
        sequence.restart();
        // Restarted rather than played: a second notification arriving while the
        // first is fading would otherwise be silent, because the player is
        // already in the playing state and play() on a playing source does
        // nothing.
        chime.stop();
        chime.play();
    }

    MediaPlayer {
        id: chime
        source: "qrc:/qt/qml/BookWorm/src/sound/achievement-unlocked.mp3"
        audioOutput: AudioOutput { volume: 0.7 }
    }

    /**
     * Slides in from the right edge and back out again.
     *
     * `slideOffset` is animated and the panel's x is bound to it. Animating the
     * anchor margin directly is not possible — a Behavior cannot attach to a
     * member of a grouped property — and this application has made that mistake
     * before.
     */
    property real slideOffset: panelWidth + Theme.spacingLarge

    SequentialAnimation {
        id: sequence

        ParallelAnimation {
            NumberAnimation {
                target: root; property: "slideOffset"; to: 0
                duration: Theme.durationSlow; easing.type: Theme.easeBack
            }
            NumberAnimation {
                target: panel; property: "opacity"; from: 0; to: 1
                duration: Theme.durationMedium
            }
        }

        PauseAnimation { duration: root.dwellMs }

        ParallelAnimation {
            NumberAnimation {
                target: root; property: "slideOffset"; to: root.panelWidth + Theme.spacingLarge
                duration: Theme.durationMedium; easing.type: Theme.easeInOut
            }
            NumberAnimation {
                target: panel; property: "opacity"; to: 0
                duration: Theme.durationMedium
            }
        }

        // Straight into the next one rather than through a gap: a queue that
        // pauses between entries reads as the application having stopped.
        ScriptAction { script: root.next() }
    }

    /**
     * Two rounded rectangles, not a rectangle with a border and a bar on top.
     *
     * The accent plate is the full panel; the surface sits on it inset by one
     * pixel on three sides and by the rail's width on the left. What shows
     * around the edge is therefore a hairline accent that thickens into a rail
     * — one shape, so the rounding can only ever agree with itself.
     *
     * The obvious construction is a bordered panel with a narrow Rectangle
     * anchored down the left, and it is wrong: a Rectangle clamps its radius to
     * half its shorter side, so a four-pixel rail cannot round to the panel's
     * twelve and its square corners jut out past them. Setting `radius: 12` on
     * the rail does not fix it — it silently becomes 2.
     */
    readonly property int railWidth: 4

    Item {
        id: panel
        x: root.slideOffset
        width: root.panelWidth
        height: root.panelHeight
        opacity: 0

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowBlur: 0.8
            shadowVerticalOffset: 6
        }

        // The accent, read as "this is a reward" before any of the text is.
        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusCard
            color: Theme.primary
        }

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: root.railWidth
            anchors.topMargin: 1
            anchors.rightMargin: 1
            anchors.bottomMargin: 1
            // One less than the plate's, so the two curves stay concentric
            // rather than the inner one bulging through the outer.
            radius: Theme.radiusCard - 1
            color: Theme.surface
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: Theme.cardPadding + root.railWidth
            anchors.rightMargin: Theme.cardPadding
            anchors.topMargin: Theme.cardPadding
            anchors.bottomMargin: Theme.cardPadding
            spacing: Theme.spacingMedium

            Rectangle {
                width: 56
                height: 56
                anchors.verticalCenter: parent.verticalCenter
                radius: Theme.radiusControl
                color: Theme.background
                clip: true

                Image {
                    id: artwork
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    // The artwork is decorative; the words carry the meaning, so
                    // a missing file must not leave a broken-image glyph where a
                    // reward should be.
                    visible: status === Image.Ready
                }
            }

            Column {
                width: parent.width - 56 - Theme.spacingMedium
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    text: Theme.tr("Achievement unlocked")
                    color: Theme.primary
                    font.pixelSize: Theme.fontSizeSection
                    font.letterSpacing: 0.8
                    font.capitalization: Font.AllUppercase
                }

                Text {
                    id: titleText
                    width: parent.width
                    color: Theme.textOnSurface
                    font.pixelSize: Theme.fontSizeMedium
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    id: descriptionText
                    width: parent.width
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                    elide: Text.ElideRight
                }
            }
        }
    }
}
