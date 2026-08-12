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
    let onScrub: (Int) -> Void
    let onCommit: (Int) -> Void

    @State private var scrubber: PageScrubber?
    @State private var draftPage: Int?
    @State private var trackWidth: Double = 1
    @State private var nudgeCommit: Task<Void, Never>?

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
            .gesture(dragGesture(width: width))
            .onAppear { trackWidth = width }
            .onChange(of: width) { _, new in trackWidth = new }
        }
        .frame(height: 44)
    }

    private func dragGesture(width: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if scrubber == nil {
                    var new = PageScrubber(startPage: page, pageCount: pageCount, trackWidth: width)
                    // A touch that starts away from the thumb jumps there, so a
                    // rough move is one tap rather than a long drag.
                    let thumbX = (width - thumbSize) * fraction + thumbSize / 2
                    if abs(value.startLocation.x - thumbX) > thumbSize {
                        new.jump(toX: value.startLocation.x)
                    }
                    scrubber = new
                }
                let next = scrubber?.drag(
                    translationX: value.translation.width,
                    translationY: value.translation.height
                )
                if let next, next != draftPage {
                    draftPage = next
                    onScrub(next)
                }
            }
            .onEnded { _ in
                // One request per gesture: the write happens here, never while
                // the finger is moving.
                let final = scrubber?.currentPage ?? page
                scrubber = nil
                draftPage = nil
                if final != page { onCommit(final) }
            }
    }

    /// Tapping `+` five times is one write, not five: the taps settle first.
    /// Five requests would also be five reading sessions' worth of pointless
    /// traffic and a good way to meet the rate limiter.
    private func nudge(_ delta: Int) {
        let next = min(pageCount, max(0, shownPage + delta))
        guard next != shownPage else { return }
        draftPage = next
        onScrub(next)

        nudgeCommit?.cancel()
        nudgeCommit = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            draftPage = nil
            if next != page { onCommit(next) }
        }
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
