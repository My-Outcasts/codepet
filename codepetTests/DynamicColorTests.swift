// codepetTests/DynamicColorTests.swift
import XCTest
import AppKit
@testable import codepet

final class DynamicColorTests: XCTestCase {
    func testNSColorHexParses() {
        let c = NSColor(hex: "#221d17").usingColorSpace(.sRGB)!
        XCTAssertEqual(c.redComponent,   CGFloat(0x22) / 255, accuracy: 0.01)
        XCTAssertEqual(c.greenComponent, CGFloat(0x1d) / 255, accuracy: 0.01)
        XCTAssertEqual(c.blueComponent,  CGFloat(0x17) / 255, accuracy: 0.01)
    }

    func testDynamicColorFlipsByAppearance() {
        let ns = CodepetTheme.dynamicNSColor(light: "#ffffff", dark: "#221d17")
        var lightR: CGFloat = -1, darkR: CGFloat = -1
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            lightR = ns.usingColorSpace(.sRGB)!.redComponent
        }
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            darkR = ns.usingColorSpace(.sRGB)!.redComponent
        }
        XCTAssertEqual(lightR, 1.0, accuracy: 0.01)                 // #ffffff
        XCTAssertEqual(darkR, CGFloat(0x22) / 255, accuracy: 0.01)  // #221d17
        XCTAssertNotEqual(lightR, darkR, accuracy: 0.001)          // proves the dynamic flip
    }
}
