// codepet/Views/PetMenuIcon.swift
import AppKit
import SwiftUI

/// A pet sprite sized for a **menu row or a `Menu`'s label**.
///
/// **Why this exists, observed 21 Aug.** `Image("char-crash")` inside a menu
/// `Label`'s icon slot renders the asset at its NATIVE pixel size. On screen that
/// turned the departments menu into a vertical slideshow of full-screen pixel faces
/// — one enormous fox per row, with scroll arrows.
///
/// A `.resizable().frame(width:16, height:16)` does not fix it: a menu item is not
/// laid out as a view tree. AppKit flattens the label to `(title, image)` and sizes
/// the image from `NSImage.size`, so SwiftUI layout modifiers on it are dropped. The
/// only thing macOS reads is that property, so this sets it.
///
/// **The same flattening applies to a `Menu`'s own label**, which is the less obvious
/// half. `CharacterImage(pet, size: 16)` renders correctly in `DepartmentRoster`'s
/// chips — those are plain `Button`s — and rendered full-size inside the armed
/// departments control, because that is a `Menu` label. If a sprite belongs anywhere
/// a `Menu` touches, it comes from here.
///
/// **No drawing, and deliberately so.** The first version redrew each sprite through
/// `NSImage.lockFocus()`. That needs a window-server graphics context, which a
/// headless XCTest host does not reliably have — and it destabilised the host badly
/// enough that six unrelated SSE streaming tests began timing out whenever this
/// type's suite ran before them. Setting `size` on a copy needs no context at all,
/// so it is both simpler and safe to test.
///
/// **Smooth downscaling, not nearest-neighbour.** `CLAUDE.md` says pixel art always
/// uses nearest-neighbour, and that rule is about UPSCALING, where nearest is the
/// difference between crisp pixels and blur. Here the sprite is reduced ~20× (421pt
/// to 16pt): nearest would sample one pixel in twenty and can drop a 4px eye
/// entirely, while the default smooth scaling preserves the impression of the face.
/// AppKit's own scaling is the right choice in this direction.
enum PetMenuIcon {

    /// Menu icons are ~16pt on macOS. Bigger reads as a mistake next to the SF
    /// Symbols on neighbouring rows; smaller loses the face.
    static let side: CGFloat = 16

    /// Cached: this is called once per row per menu open, and redrawing eight
    /// sprites on every render of a control that lives in the composer would be
    /// wasted work on the main thread.
    private static var cache: [String: NSImage] = [:]

    /// The sprite for `petId` as a SwiftUI `Image`, or nil when the asset is missing
    /// — in which case the caller shows the row's text alone rather than a gap. A row
    /// must never promise a pet it cannot draw.
    @MainActor static func image(_ petId: String) -> Image? {
        nsImage(petId).map { Image(nsImage: $0) }
    }

    /// The same sprite as the `NSImage` AppKit will actually size the row from.
    ///
    /// Exposed rather than private because `size` is the whole point of this type and
    /// a test asserting it through a SwiftUI `Image` would be asserting on a wrapper
    /// instead of on the value macOS reads.
    ///
    /// The copy matters: `NSImage(named:)` returns a SHARED instance from the asset
    /// catalog, and `DepartmentRoster` draws the same one at chip size. Setting `size`
    /// on it directly would reach across the app.
    @MainActor static func nsImage(_ petId: String) -> NSImage? {
        if let hit = cache[petId] { return hit }
        guard let shared = NSImage(named: "char-\(petId)"),
              let out = shared.copy() as? NSImage else { return nil }
        // The only sizing input a menu row has. Aspect ratio is preserved by AppKit
        // when it draws, so a square box on a tall portrait letterboxes rather than
        // stretching — the same ~13×16pt the roster chips already read as.
        out.size = NSSize(width: side, height: side)
        cache[petId] = out
        return out
    }
}
