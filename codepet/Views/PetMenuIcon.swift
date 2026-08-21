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
/// **Nearest-neighbour, per CLAUDE.md.** These are pixel-art sprites; bilinear
/// smoothing on a 16pt draw turns a crisp 4px eye into grey mush. `.none`
/// interpolation keeps the pixels square at the cost of looking chunky, which is
/// what the art is.
enum PetMenuIcon {

    /// Menu icons are ~16pt on macOS. Bigger reads as a mistake next to the SF
    /// Symbols on neighbouring rows; smaller loses the face.
    static let side: CGFloat = 16

    /// Cached: this is called once per row per menu open, and redrawing eight
    /// sprites on every render of a control that lives in the composer would be
    /// wasted work on the main thread.
    private static var cache: [String: Image] = [:]

    /// The sprite for `petId` at menu-icon size, or nil when the asset is missing —
    /// in which case the caller shows the row's text alone rather than a gap. A row
    /// must never promise a pet it cannot draw.
    @MainActor static func image(_ petId: String) -> Image? {
        if let hit = cache[petId] { return hit }
        guard let src = NSImage(named: "char-\(petId)") else { return nil }

        let box = NSSize(width: side, height: side)
        let out = NSImage(size: box)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        // Fit rather than fill: these are tall portraits in a square frame, so
        // aspect-fill would crop the face to a band of forehead.
        let s = src.size
        let scale = min(box.width / max(s.width, 1), box.height / max(s.height, 1))
        let drawn = NSSize(width: s.width * scale, height: s.height * scale)
        src.draw(in: NSRect(x: (box.width - drawn.width) / 2,
                            y: (box.height - drawn.height) / 2,
                            width: drawn.width, height: drawn.height),
                 from: .zero, operation: .sourceOver, fraction: 1.0)
        out.unlockFocus()
        // The property AppKit actually reads. Everything above is to make this
        // honest rather than a stretched thumbnail.
        out.size = box

        let img = Image(nsImage: out)
        cache[petId] = img
        return img
    }
}
