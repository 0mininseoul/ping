import CoreGraphics

/// 같은 자리에 함께 뜨는 재생 창들을 겹치지 않게 배치한다.
///
/// 자동 회신은 원본 핑의 `mirrorPosition`을 그대로 물고 온다. 창을 하나씩 앵커에 놓으면
/// 회신한 사람 수만큼 한 점에 완전히 포개지고, 위 창이 닫혀야 아래가 드러나므로
/// 사용자 눈에는 "한 명씩 순서대로" 뜨는 것으로 보인다. 그래서 배치는 묶음 단위로 계산한다.
enum PlaybackGroupLayout {
    static let spacing: CGFloat = 12

    /// 룸 정원이 8명이라 한 핑에 달릴 수 있는 회신은 최대 7개다.
    /// 한 줄에 3개까지만 놓고 나머지는 아래 줄로 접는다.
    static let maxColumns = 3

    /// 화면이 좁으면 열 수를 줄인다. 3열을 고집하면 클램프에 밀려 다시 겹친다.
    static func columnCount(for count: Int, cellWidth: CGFloat, availableWidth: CGFloat) -> Int {
        guard count > 0 else { return 0 }
        let wanted = min(count, maxColumns)
        guard cellWidth > 0 else { return wanted }

        let fits = Int(((availableWidth + spacing) / (cellWidth + spacing)).rounded(.down))
        return max(1, min(wanted, fits))
    }

    /// - Parameters:
    ///   - sizes: 함께 띄울 창들의 크기. 반환값은 같은 순서다.
    ///   - center: 묶음 전체의 중심. 원본 핑이 찍힌 자리다.
    /// - Returns: 서로 겹치지 않고 `safeArea` 안에 들어가는 창 원점들.
    static func origins(sizes: [CGSize], centeredAt center: CGPoint, inSafeArea safeArea: CGRect) -> [CGPoint] {
        guard !sizes.isEmpty else { return [] }

        // 셀은 가장 큰 창에 맞춘다. 크기가 섞여도 줄과 열이 어긋나지 않는다.
        let cell = CGSize(
            width: sizes.map(\.width).max() ?? 0,
            height: sizes.map(\.height).max() ?? 0
        )
        let columns = columnCount(for: sizes.count, cellWidth: cell.width, availableWidth: safeArea.width)
        let rows = Int((Double(sizes.count) / Double(columns)).rounded(.up))

        let blockWidth = CGFloat(columns) * cell.width + CGFloat(columns - 1) * spacing
        let blockHeight = CGFloat(rows) * cell.height + CGFloat(rows - 1) * spacing
        let blockOrigin = ScreenCoordinates.clamp(
            point: CGPoint(x: center.x - blockWidth / 2, y: center.y - blockHeight / 2),
            windowSize: CGSize(width: blockWidth, height: blockHeight),
            inSafeArea: safeArea
        )

        return sizes.enumerated().map { index, size in
            let row = index / columns
            let column = index % columns

            // 마지막 줄이 덜 찼으면 그 줄만 가운데로 모은다.
            let inRow = min(columns, sizes.count - row * columns)
            let rowWidth = CGFloat(inRow) * cell.width + CGFloat(inRow - 1) * spacing
            let cellX = blockOrigin.x + (blockWidth - rowWidth) / 2 + CGFloat(column) * (cell.width + spacing)
            // AppKit은 y가 위로 자라므로 첫 줄이 가장 높이 온다.
            let cellY = blockOrigin.y + blockHeight
                - CGFloat(row + 1) * cell.height
                - CGFloat(row) * spacing

            return ScreenCoordinates.clamp(
                point: CGPoint(
                    x: cellX + (cell.width - size.width) / 2,
                    y: cellY + (cell.height - size.height) / 2
                ),
                windowSize: size,
                inSafeArea: safeArea
            )
        }
    }
}
