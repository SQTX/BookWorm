import Foundation

/// The arithmetic behind the slider.
///
/// A plain `Slider` across a phone gives about three pages per point of travel on
/// a 400-page book, which makes landing on an exact page a fight. Dragging away
/// from the track slows the rate — the gesture every scrubbing control on the
/// platform uses — so a coarse move and a precise one are the same gesture.
///
/// The rate is applied to each increment of the drag rather than to the whole
/// translation, so moving the thumb down mid-drag slows what happens next
/// instead of retroactively rescaling where the finger already went.
public struct PageScrubber: Sendable, Equatable {
    public enum Precision: Sendable, Equatable {
        case coarse    // full speed
        case fine      // a quarter
        case finest    // a tenth

        public var rate: Double {
            switch self {
            case .coarse: return 1
            case .fine: return 0.25
            case .finest: return 0.1
            }
        }

        public static func forVerticalOffset(_ offset: Double) -> Precision {
            let distance = abs(offset)
            if distance < 44 { return .coarse }
            if distance < 100 { return .fine }
            return .finest
        }
    }

    public let pageCount: Int
    public let trackWidth: Double
    public private(set) var page: Double
    public private(set) var precision: Precision = .coarse
    private var lastTranslationX: Double = 0

    public init(startPage: Int, pageCount: Int, trackWidth: Double) {
        self.pageCount = max(1, pageCount)
        self.trackWidth = max(1, trackWidth)
        self.page = Double(min(max(0, startPage), max(1, pageCount)))
    }

    public var pagesPerPoint: Double { Double(pageCount) / trackWidth }

    public var currentPage: Int { Int(page.rounded()) }

    @discardableResult
    public mutating func drag(translationX: Double, translationY: Double) -> Int {
        precision = Precision.forVerticalOffset(translationY)
        let step = translationX - lastTranslationX
        lastTranslationX = translationX
        page = clamp(page + step * pagesPerPoint * precision.rate)
        return currentPage
    }

    /// A tap on the track jumps there; the drag that follows continues from that
    /// point at full precision.
    @discardableResult
    public mutating func jump(toX x: Double) -> Int {
        page = clamp(x / trackWidth * Double(pageCount))
        lastTranslationX = 0
        precision = .coarse
        return currentPage
    }

    @discardableResult
    public mutating func nudge(_ delta: Int) -> Int {
        page = clamp((page.rounded()) + Double(delta))
        return currentPage
    }

    public mutating func endDrag() {
        page = page.rounded()
        lastTranslationX = 0
        precision = .coarse
    }

    public var fraction: Double {
        page / Double(pageCount)
    }

    private func clamp(_ value: Double) -> Double {
        min(Double(pageCount), max(0, value))
    }
}
