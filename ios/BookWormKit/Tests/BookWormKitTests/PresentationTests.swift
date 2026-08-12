import XCTest
@testable import BookWormKit

final class ProgressTextTests: XCTestCase {
    func testTheRestingLine() {
        XCTAssertEqual(ProgressText.summary(for: .fixture(pageCount: 224, currentPage: 180)), "180 / 224 · 80%")
    }

    func testAnUnrecordedPageIsNotPageZero() {
        XCTAssertEqual(ProgressText.summary(for: .fixture(pageCount: 224, currentPage: nil)), "Not started · 224 pages")
        XCTAssertEqual(ProgressText.summary(for: .fixture(pageCount: 224, currentPage: 0)), "0 / 224 · 0%")
    }

    func testABookWithoutAPageCount() {
        XCTAssertEqual(ProgressText.summary(for: .fixture(pageCount: nil, currentPage: 44)), "Page 44")
        XCTAssertEqual(ProgressText.summary(for: .fixture(pageCount: nil, currentPage: nil)), "No page count")
    }

    func testTheDraggingLineShowsWhereItLandsAndWhatChanged() {
        XCTAssertEqual(ProgressText.whileDragging(target: 212, from: 180), "212 · +32 pages")
        XCTAssertEqual(ProgressText.whileDragging(target: 181, from: 180), "181 · +1 page")
        XCTAssertEqual(ProgressText.whileDragging(target: 172, from: 180), "172 · −8 pages")
        XCTAssertEqual(ProgressText.whileDragging(target: 180, from: 180), "180 · no change")
    }

    func testDraggingABookWithNoRecordedPageHasNoDelta() {
        XCTAssertEqual(ProgressText.whileDragging(target: 212, from: nil), "212 · first update")
    }

    func testTheConfirmation() {
        XCTAssertEqual(ProgressText.saved(pagesRead: 32), "Saved · 32 pages read")
        XCTAssertEqual(ProgressText.saved(pagesRead: 1), "Saved · 1 page read")
        XCTAssertEqual(ProgressText.saved(pagesRead: 0), "Saved")
        XCTAssertEqual(ProgressText.saved(pagesRead: nil), "Saved")
    }
}

final class PageScrubberTests: XCTestCase {
    // 320 points of track, 400 pages: 1.25 pages per point.
    private func scrubber(start: Int = 180, pages: Int = 400) -> PageScrubber {
        PageScrubber(startPage: start, pageCount: pages, trackWidth: 320)
    }

    func testAHorizontalDragMovesAtFullRate() {
        var s = scrubber()
        XCTAssertEqual(s.drag(translationX: 80, translationY: 0), 280)
    }

    func testDraggingAwayFromTheTrackSlowsItDown() {
        var fine = scrubber()
        XCTAssertEqual(fine.drag(translationX: 80, translationY: 60), 205)   // a quarter
        var finest = scrubber()
        XCTAssertEqual(finest.drag(translationX: 80, translationY: 150), 190) // a tenth
    }

    func testTheRateAppliesToWhatHappensNextNotToWhereTheFingerAlreadyWas() {
        var s = scrubber()
        XCTAssertEqual(s.drag(translationX: 80, translationY: 0), 280)
        // Same finger, now pulled down and moved a little further: the earlier
        // 100 pages stay put and only the new 8 points are scaled.
        XCTAssertEqual(s.drag(translationX: 88, translationY: 150), 281)
    }

    func testTheRangeStartsAtZeroSoAPageCanBeCorrectedDownwards() {
        var s = scrubber(start: 20)
        XCTAssertEqual(s.drag(translationX: -400, translationY: 0), 0)
        XCTAssertEqual(s.currentPage, 0)
    }

    func testItCannotGoPastTheEnd() {
        var s = scrubber(start: 390)
        XCTAssertEqual(s.drag(translationX: 400, translationY: 0), 400)
    }

    func testSinglePageNudges() {
        var s = scrubber()
        XCTAssertEqual(s.nudge(1), 181)
        XCTAssertEqual(s.nudge(-1), 180)
        var atZero = scrubber(start: 0)
        XCTAssertEqual(atZero.nudge(-1), 0)
    }

    func testTappingTheTrackJumpsThere() {
        var s = scrubber()
        XCTAssertEqual(s.jump(toX: 160), 200)
        XCTAssertEqual(s.drag(translationX: 8, translationY: 0), 210)
    }

    func testABookWithNoRecordedPageStartsTheSliderAtZeroWithoutWritingZero() {
        // The control starts at 0 because it has to start somewhere; nothing is
        // written until the user releases, which is what keeps `null` intact.
        let s = scrubber(start: 0)
        XCTAssertEqual(s.currentPage, 0)
        XCTAssertEqual(s.fraction, 0)
    }
}

final class BookTests: XCTestCase {
    func testProgressFractionNeedsBothEnds() {
        XCTAssertEqual(Book.fixture(pageCount: 200, currentPage: 50).progressFraction, 0.25)
        XCTAssertNil(Book.fixture(pageCount: nil, currentPage: 50).progressFraction)
        XCTAssertNil(Book.fixture(pageCount: 200, currentPage: nil).progressFraction)
        XCTAssertNil(Book.fixture(pageCount: 0, currentPage: 10).progressFraction)
    }

    func testStarredBooksComeFirstAndTheRestKeepTheServersOrder() {
        let books = [
            Book.fixture(id: 1, title: "One"),
            Book.fixture(id: 2, title: "Two", isPriority: true),
            Book.fixture(id: 3, title: "Three"),
            Book.fixture(id: 4, title: "Four", isPriority: true)
        ]

        let (priority, rest) = Book.priorityFirst(books)

        XCTAssertEqual(priority.map(\.id), [2, 4])
        XCTAssertEqual(rest.map(\.id), [1, 3])
    }

    func testAPriorityFlagSurvivesAnOptimisticPageChange() {
        let book = Book.fixture(isPriority: true).withCurrentPage(200)
        XCTAssertTrue(book.isPriority)
        XCTAssertEqual(book.currentPage, 200)
    }

    func testACacheWrittenBeforeThePriorityFieldExistedStillDecodes() throws {
        let legacy = Data(#"{"id":1,"title":"T","author":"A"}"#.utf8)
        let book = try JSONDecoder().decode(Book.self, from: legacy)
        XCTAssertFalse(book.isPriority)
    }

    func testPageBounds() {
        XCTAssertTrue(PageBounds.isValid(0))
        XCTAssertTrue(PageBounds.isValid(100_000))
        XCTAssertFalse(PageBounds.isValid(-1))
        XCTAssertFalse(PageBounds.isValid(100_001))
        XCTAssertEqual(PageBounds.clamp(-5), 0)
        XCTAssertEqual(PageBounds.clamp(999_999), 100_000)
    }
}

final class AppLogTests: XCTestCase {
    func testItSurvivesRelaunchAndReadsNewestFirst() async {
        let url = temporaryFileURL("log.txt")
        let log = AppLog(fileURL: url)
        await log.write("first")
        await log.write("second")

        let reopened = AppLog(fileURL: url)
        let lines = await reopened.recent()

        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].hasSuffix("second"))
        XCTAssertTrue(lines[1].hasSuffix("first"))
    }

    func testItStopsGrowing() async {
        let log = AppLog(fileURL: nil, limit: 3)
        for i in 1...10 { await log.write("line \(i)") }

        let lines = await log.recent()
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasSuffix("line 10"))
    }
}
