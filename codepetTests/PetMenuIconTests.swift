import AppKit
import XCTest
@testable import codepet

/// The one thing macOS reads when sizing a menu icon.
///
/// **The defect this guards, observed 21 Aug.** `Image("char-crash")` handed to a
/// `Menu` — either as a row's icon or inside the `Menu`'s own label — rendered at the
/// asset's native size. `char-crash@2x.png` is 1023×1263 pixels, which `NSImage`
/// reports as **341×421 points**. A 421pt-tall row on a ~1300pt display is three rows
/// to a screen, which is exactly what the screen recording showed: two enormous pixel
/// faces and scroll arrows.
///
/// A SwiftUI `.frame(width: 16, height: 16)` does not fix it. A menu item is not laid
/// out as a view tree — AppKit flattens the label to `(title, image)` and sizes the
/// image from `NSImage.size`. That property is the only input, so `PetMenuIcon` sets
/// it, and this asserts it stays set.
///
/// **Delete `out.size = box` from `PetMenuIcon` and this suite goes red.** That is the
/// point: the resize is invisible in the type's output otherwise, because the drawn
/// bitmap looks fine either way and only the reported `size` decides the row height.
@MainActor
final class PetMenuIconTests: XCTestCase {

    /// Every pet the roster can summon, per `DepartmentCompanions`.
    private let pets = ["crash", "luna", "nova", "sage", "glitch"]

    func testEverySpriteReportsMenuIconSize() throws {
        for pet in pets {
            guard let img = PetMenuIcon.image(pet) else {
                XCTFail("no sprite for \(pet) — a row would show text alone")
                continue
            }
            let ns = NSImage(named: "char-\(pet)")
            XCTAssertNotNil(ns, "asset char-\(pet) is missing")
            // The assertion that matters: what AppKit will read.
            let sized = try XCTUnwrap(ImageRenderer(content: img).nsImage)
            XCTAssertEqual(sized.size.width, PetMenuIcon.side, accuracy: 1,
                           "\(pet) is \(sized.size.width)pt wide — a menu row would be that tall")
            XCTAssertEqual(sized.size.height, PetMenuIcon.side, accuracy: 1)
        }
    }

    /// **The raw asset is the counter-example.** If this ever starts reporting ~16pt,
    /// the assets were resized and `PetMenuIcon` may no longer be needed — but until
    /// then it documents why it exists, in numbers rather than prose.
    func testTheRawAssetIsWhyThisTypeExists() throws {
        let raw = try XCTUnwrap(NSImage(named: "char-crash"))
        XCTAssertGreaterThan(raw.size.height, 100,
                             "char-crash reports \(raw.size.height)pt tall; if that is now "
                             + "small, re-check whether PetMenuIcon is still load-bearing")
    }

    /// Aspect-FIT, not fill. These are tall portraits in a square box, so filling
    /// would crop each face to a band of forehead. 13×16 is also the figure
    /// `DepartmentRoster` already documents, so the menu sprite and the roster chip
    /// read as the same object.
    func testTallPortraitsAreFittedNotCropped() {
        let fitted = ChatAttachment.fittedSize(for: CGSize(width: 1023, height: 1263),
                                               longEdge: 16)
        XCTAssertEqual(fitted.height, 16, accuracy: 0.5)
        XCTAssertEqual(fitted.width, 13, accuracy: 0.5)
    }

    /// Cached, because a menu re-renders whenever the composer does and redrawing
    /// eight 341×421 bitmaps on the main thread per render is real work.
    func testTheSameSpriteIsNotRedrawnEveryCall() {
        _ = PetMenuIcon.image("crash")
        let start = Date()
        for _ in 0..<200 { _ = PetMenuIcon.image("crash") }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.1,
                          "200 cached lookups took too long — the cache is not being hit")
    }
}
