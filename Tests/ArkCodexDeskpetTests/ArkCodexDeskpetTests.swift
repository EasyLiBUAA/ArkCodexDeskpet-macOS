import AppKit
import XCTest
@testable import ArkCodexDeskpet

final class ArkCodexDeskpetTests: XCTestCase {
    func testNewSettingsAllowDragging() {
        XCTAssertFalse(PetSettings().locked)
    }

    func testDraggedOriginUsesOriginalWindowPosition() {
        let result = draggedWindowOrigin(
            from: NSPoint(x: 120, y: 80),
            mouseStart: NSPoint(x: 300, y: 200),
            mouseNow: NSPoint(x: 345, y: 165)
        )
        XCTAssertEqual(result, NSPoint(x: 165, y: 45))
    }

    func testRunningStatusUsesCompactBubbleText() {
        XCTAssertEqual(petStatusDisplayText("Codex 运行中 · a very long task"), "Codex 正在处理")
        XCTAssertEqual(petStatusDisplayText("Codex 待机"), "Codex 待机")
    }

    func testStatusDotTopAndTextBottomHaveEqualPadding() {
        let body = NSRect(x: 0, y: 8, width: 160, height: 31)
        let textHeight: CGFloat = 13
        let dotDiameter: CGFloat = 7
        let centerY = statusContentCenterY(body: body, textHeight: textHeight, dotDiameter: dotDiameter)
        let topPadding = body.maxY - (centerY + dotDiameter / 2)
        let bottomPadding = (centerY - textHeight / 2) - body.minY
        XCTAssertEqual(topPadding, bottomPadding, accuracy: 0.001)
    }

    func testPRTSMetadataListsOnlyBuildModelsWithDefaultFirst() {
        let metadata = PRTSMetadata(
            prefix: "https://example.invalid/",
            name: "test",
            skin: [
                "时装": ["基建": PRTSModel(file: "skin", skin: nil)],
                "默认": ["基建": PRTSModel(file: "default", skin: nil)],
                "战斗模型": ["战斗": PRTSModel(file: "battle", skin: nil)]
            ]
        )
        XCTAssertEqual(metadata.buildSkins, ["默认", "时装"])
    }
}
