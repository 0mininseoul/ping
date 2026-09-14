import XCTest
@testable import Ping

final class PlaybackGroupLayoutTests: XCTestCase {
    private let safeArea = CGRect(x: 0, y: 24, width: 1920, height: 1056)
    private let face = CGSize(width: 200, height: 200)
    private let anchor = CGPoint(x: 960, y: 540)

    private func faceFrames(_ count: Int, centeredAt center: CGPoint? = nil) -> [CGRect] {
        let sizes = Array(repeating: face, count: count)
        let origins = PlaybackGroupLayout.origins(
            sizes: sizes,
            centeredAt: center ?? anchor,
            inSafeArea: safeArea
        )
        return zip(origins, sizes).map { CGRect(origin: $0, size: $1) }
    }

    func testEmptyGroupProducesNoOrigins() {
        XCTAssertTrue(PlaybackGroupLayout.origins(sizes: [], centeredAt: anchor, inSafeArea: safeArea).isEmpty)
    }

    /// 혼자 온 핑은 지금까지처럼 보낸 사람이 찍은 자리에 그대로 떠야 한다.
    func testSingleWindowStaysOnTheAnchor() {
        let frames = faceFrames(1)

        XCTAssertEqual(frames[0].midX, anchor.x, accuracy: 0.001)
        XCTAssertEqual(frames[0].midY, anchor.y, accuracy: 0.001)
    }

    /// 회귀 방지 본체. 자동 회신은 전부 원본 핑의 mirrorPosition을 물고 오므로
    /// 앵커만 보고 놓으면 완전히 포개져, 위 창이 닫혀야 아래가 드러난다.
    func testTwoWindowsDoNotOverlap() {
        let frames = faceFrames(2)

        XCTAssertFalse(frames[0].intersects(frames[1]))
    }

    func testTwoWindowsSitSideBySideCenteredOnTheAnchor() {
        let frames = faceFrames(2)

        XCTAssertEqual(frames[0].midY, frames[1].midY, accuracy: 0.001)
        XCTAssertLessThan(frames[0].midX, frames[1].midX)
        XCTAssertEqual((frames[0].midX + frames[1].midX) / 2, anchor.x, accuracy: 0.001)
    }

    func testThreeWindowsStayOnASingleRow() {
        let frames = faceFrames(3)

        XCTAssertEqual(frames[1].midY, frames[0].midY, accuracy: 0.001)
        XCTAssertEqual(frames[2].midY, frames[0].midY, accuracy: 0.001)
        XCTAssertEqual(frames[1].midX, anchor.x, accuracy: 0.001)
    }

    /// 룸 정원이 8명이라 회신은 최대 7개다. 한 줄에 3개까지만 놓고 접는다.
    func testFourthWindowWrapsToASecondRow() {
        let frames = faceFrames(4)

        XCTAssertEqual(frames[0].midY, frames[2].midY, accuracy: 0.001)
        XCTAssertLessThan(frames[3].midY, frames[0].midY)
    }

    func testLastPartialRowIsCenteredUnderTheFullRow() {
        let frames = faceFrames(4)

        XCTAssertEqual(frames[3].midX, anchor.x, accuracy: 0.001)
    }

    func testNoTwoWindowsOverlapUpToAFullRoom() {
        for count in 1...7 {
            let frames = faceFrames(count)
            for i in frames.indices {
                for j in frames.indices where j > i {
                    XCTAssertFalse(frames[i].intersects(frames[j]), "\(count)개 중 \(i)·\(j)가 겹친다")
                }
            }
        }
    }

    func testGroupAnchoredAtTheCornerStaysInsideTheSafeArea() {
        for count in 1...7 {
            for corner in [CGPoint(x: 1920, y: 1080), CGPoint(x: 0, y: 0)] {
                for frame in faceFrames(count, centeredAt: corner) {
                    XCTAssertTrue(safeArea.contains(frame), "\(count)개 @\(corner): \(frame)")
                }
            }
        }
    }

    /// 좁은 화면에서 3열을 고집하면 창이 화면 밖으로 밀리거나 클램프되며 다시 겹친다.
    func testNarrowScreenFallsBackToFewerColumns() {
        let narrow = CGRect(x: 0, y: 0, width: 260, height: 900)
        let sizes = Array(repeating: face, count: 3)
        let origins = PlaybackGroupLayout.origins(
            sizes: sizes,
            centeredAt: CGPoint(x: 130, y: 450),
            inSafeArea: narrow
        )
        let frames = zip(origins, sizes).map { CGRect(origin: $0, size: $1) }

        XCTAssertEqual(Set(frames.map { $0.minX }).count, 1)
        for i in frames.indices {
            for j in frames.indices where j > i {
                XCTAssertFalse(frames[i].intersects(frames[j]))
            }
        }
    }

    /// 얼굴 회신(200)과 화면+얼굴(480)이 한 묶음에 섞여도 줄이 어긋나면 안 된다.
    func testMixedSizesShareAUniformGridWithoutOverlap() {
        let sizes = [face, CGSize(width: 480, height: 270), face]
        let origins = PlaybackGroupLayout.origins(sizes: sizes, centeredAt: anchor, inSafeArea: safeArea)
        let frames = zip(origins, sizes).map { CGRect(origin: $0, size: $1) }

        for i in frames.indices {
            for j in frames.indices where j > i {
                XCTAssertFalse(frames[i].intersects(frames[j]), "\(i)·\(j)가 겹친다")
            }
        }
        XCTAssertEqual(frames[0].midY, frames[1].midY, accuracy: 0.001)
    }
}
