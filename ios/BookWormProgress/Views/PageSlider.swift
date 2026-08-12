import SwiftUI
import BookWormKit

/// The whole interaction.
///
/// Not a `Slider`: on a 400-page book a stock slider gives about three pages per
/// point of travel, so landing on page 212 rather than 209 becomes a fight.
/// Dragging away from the track slows the rate to a quarter and then a tenth,
/// and `−`/`+` cover the last page either way. The arithmetic lives in
/// `PageScrubber`, where it is tested.
struct PageSlider: View {
    let pageCount: Int
    let page: Int
    /// The page the control is currently showing, which is only a proposal
    /// until the user confirms it. Owned by the card so the confirm button and
    /// the slider cannot disagree about what is pending.
    @Binding var draftPage: Int?

    @State private var scrubber: PageScrubber?
    @State private var trackWidth: Double = 1
    /// Nil until this gesture has proved itself horizontal. A flick down the
    /// list is not an attempt to move a page.
    @State private var isScrubbing = false

    private let trackHeight: Double = 8
    private let thumbSize: Double = 26

    private var shownPage: Int { draftPage ?? page }
    private var fraction: Double {
        guard pageCount > 0 else { return 0 }
        return min(1, max(0, Double(shownPage) / Double(pageCount)))
    }

    var body: some View {
        HStack(spacing: 10) {
            NudgeButton(symbol: "minus", disabled: shownPage <= 0) { nudge(-1) }
            track
            NudgeButton(symbol: "plus", disabled: shownPage >= pageCount) { nudge(1) }
        }
        .sensoryFeedback(.selection, trigger: scrubber?.precision)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current page")
        .accessibilityValue("\(shownPage) of \(pageCount)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(1)
            case .decrement: nudge(-1)
            @unknown default: break
            }
        }
    }

    private var track: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: trackHeight)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(trackHeight, width * fraction), height: trackHeight)
                Circle()
                    .fill(.background)
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: (width - thumbSize) * fraction)
                    .animation(scrubber == nil ? .snappy(duration: 0.25) : nil, value: fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            // Simultaneous, not exclusive: the list keeps scrolling under the
            // finger, and this gesture bows out unless the movement is
            // horizontal. Taking the gesture outright is what made scrolling
            // past a card nudge its page.
            .simultaneousGesture(dragGesture(width: width))
            .onAppear { trackWidth = width }
            .onChange(of: width) { _, new in trackWidth = new }
        }
        .frame(height: 44)
    }

    /// Below this the gesture is still ambiguous, so nothing moves. Above it,
    /// whichever axis is winning decides who owns the touch.
    private let axisThreshold: Double = 10

    private func dragGesture(width: Double) -> some Gesture {
        DragGesture(minimumDistance: axisThreshold)
            .onChanged { value in
                guard isScrubbing else {
                    // The list wins a vertical drag. Once it has, this gesture
                    // stays out until the finger lifts — no mid-scroll grabs.
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    var new = PageScrubber(startPage: shownPage, pageCount: pageCount, trackWidth: width)
                    // A touch that starts away from the thumb jumps there, so a
                    // rough move is one tap rather than a long drag.
                    let thumbX = (width - thumbSize) * fraction + thumbSize / 2
                    if abs(value.startLocation.x - thumbX) > thumbSize {
                        new.jump(toX: value.startLocation.x)
                    }
                    scrubber = new
                    isScrubbing = true
                    return
                }
                let next = scrubber?.drag(
                    translationX: value.translation.width,
                    translationY: value.translation.height
                )
                if let next, next != draftPage { draftPage = next }
            }
            .onEnded { _ in
                // Nothing is written here. Releasing leaves a proposal on the
                // card, and the card's confirm button is what reaches the
                // server — so a mis-swipe costs a tap on ✕, not a wrong page in
                // the user's reading history.
                if isScrubbing, let landed = scrubber?.currentPage { draftPage = landed }
                scrubber = nil
                isScrubbing = false
            }
    }

    /// Also a proposal. Tapping `+` five times is five page changes and still
    /// one request, because nothing is sent until it is confirmed.
    private func nudge(_ delta: Int) {
        let next = min(pageCount, max(0, shownPage + delta))
        guard next != shownPage else { return }
        draftPage = next
    }
}

private struct NudgeButton: View {
    let symbol: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 34, height: 34)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Color.secondary : Color.primary)
        .disabled(disabled)
        .accessibilityLabel(symbol == "plus" ? "One page forward" : "One page back")
    }
}
