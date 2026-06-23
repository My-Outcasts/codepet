import SwiftUI

/// Rectangle whose corners are cut by a STAIR-STEP of square blocks — each
/// step is a discrete horizontal-then-vertical jog so the edge reads as a
/// chunky stair of pixels (just like the pet sprites scaled with
/// `.interpolation(.none)`). Default: 2 steps of 4pt each at every corner.
struct PixelStaircaseRectangle: InsettableShape {
    var blockSize: CGFloat = 4   // size of one stair-step "pixel"
    var steps: Int = 2           // number of stair blocks per corner
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let b = blockSize
        let n = steps
        let nf = CGFloat(n)
        let chamfer = b * nf

        var p = Path()
        // Start: top edge, just past the top-left chamfer.
        p.move(to: CGPoint(x: r.minX + chamfer, y: r.minY))
        // Top edge across to the top-right chamfer start.
        p.addLine(to: CGPoint(x: r.maxX - chamfer, y: r.minY))

        // Top-right corner — stair down-right.
        for i in 0..<n {
            let baseX = r.maxX - b * CGFloat(n - i)
            let baseY = r.minY + b * CGFloat(i)
            p.addLine(to: CGPoint(x: baseX,     y: baseY + b))   // drop
            p.addLine(to: CGPoint(x: baseX + b, y: baseY + b))   // right
        }

        // Right edge down.
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - chamfer))

        // Bottom-right corner — stair down-left.
        for i in 0..<n {
            let baseX = r.maxX - b * CGFloat(i)
            let baseY = r.maxY - b * CGFloat(n - i)
            p.addLine(to: CGPoint(x: baseX,     y: baseY + b))   // drop
            p.addLine(to: CGPoint(x: baseX - b, y: baseY + b))   // left
        }

        // Bottom edge across.
        p.addLine(to: CGPoint(x: r.minX + chamfer, y: r.maxY))

        // Bottom-left corner — stair up-left.
        for i in 0..<n {
            let baseX = r.minX + b * CGFloat(n - i)
            let baseY = r.maxY - b * CGFloat(i)
            p.addLine(to: CGPoint(x: baseX - b, y: baseY))       // left
            p.addLine(to: CGPoint(x: baseX - b, y: baseY - b))   // up
        }

        // Left edge up.
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + chamfer))

        // Top-left corner — stair up-right.
        for i in 0..<n {
            let baseX = r.minX + b * CGFloat(i)
            let baseY = r.minY + b * CGFloat(n - i)
            p.addLine(to: CGPoint(x: baseX,     y: baseY - b))   // up
            p.addLine(to: CGPoint(x: baseX + b, y: baseY - b))   // right
        }

        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var s = self
        s.insetAmount += amount
        return s
    }
}

/// A pixel-art container that matches the chunky-staircase aesthetic of the
/// app's pet sprites: thick dark outline, stair-step corners, solid flat
/// fill (no gradient, no bevel, no scanlines), and a hard offset drop
/// shadow. Reads as an 8-bit game dialog box.
struct PixelCard<Content: View>: View {
    var fill: Color = Color(hex: "#F5E8C7")
    var borderColor: Color = Color(hex: "#2D2B26")
    var shadowOffset: CGFloat = 4
    var blockSize: CGFloat = 4
    var steps: Int = 2
    var borderWidth: CGFloat = 4
    @ViewBuilder var content: () -> Content

    private var shape: PixelStaircaseRectangle {
        PixelStaircaseRectangle(blockSize: blockSize, steps: steps)
    }

    var body: some View {
        // Layer order, back → front:
        //   1. Shadow (offset, dark) — gives the chunky drop-shadow vibe.
        //   2. Opaque white base — necessary because callers sometimes pass
        //      a TRANSLUCENT `fill` (e.g. `accent.opacity(0.18)`). Without
        //      this base layer the shadow bleeds through the fill and the
        //      card body looks dark instead of tinted.
        //   3. The actual fill — opaque or translucent, sits on the white
        //      base for predictable color.
        // Attached via `.background` so the whole composite sizes to the
        // content frame, not the surrounding container.
        content()
            .background(
                ZStack {
                    shape
                        .fill(borderColor)
                        .offset(x: shadowOffset, y: shadowOffset)
                    shape.fill(Color.white)
                    shape.fill(fill)
                }
            )
            .overlay(shape.stroke(borderColor, lineWidth: borderWidth))
    }
}

extension PixelCard {
    static var success: PixelCardPreset { .init(fill: Color(hex: "#F5E8C7"), border: Color(hex: "#2D2B26")) }
    static var warning: PixelCardPreset { .init(fill: Color(hex: "#FCEBA8"), border: Color(hex: "#2D2B26")) }
    static var error:   PixelCardPreset { .init(fill: Color(hex: "#A8D8D4"), border: Color(hex: "#2D2B26")) }
    static var info:    PixelCardPreset { .init(fill: Color(hex: "#F5E8C7"), border: Color(hex: "#2D2B26")) }
}

struct PixelCardPreset {
    let fill: Color
    let border: Color
}

// MARK: - Pixel button

/// Pixel-art button matching the staircase-cornered card. Press feedback:
/// shadow vanishes and the button shifts into the shadow's old slot — the
/// classic 8-bit "press down" feel.
struct PixelButtonStyle: ButtonStyle {
    var fill: Color = Color(hex: "#7C3AED")
    var foreground: Color = .white
    var borderColor: Color = Color(hex: "#2D2B26")
    var paddingH: CGFloat = 14
    var paddingV: CGFloat = 8
    var blockSize: CGFloat = 3
    var steps: Int = 2
    var borderWidth: CGFloat = 3
    var shadowOffset: CGFloat = 3
    /// Optional font override. When nil, callers style their own label font.
    var font: Font? = nil

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = PixelStaircaseRectangle(blockSize: blockSize, steps: steps)
        return configuration.label
            .applying(font: font, foreground: foreground)
            .padding(.horizontal, paddingH)
            .padding(.vertical, paddingV)
            .background(
                ZStack {
                    shape
                        .fill(borderColor)
                        .offset(x: shadowOffset, y: shadowOffset)
                        .opacity(pressed ? 0 : 1)
                    shape.fill(Color.white)
                    shape.fill(fill)
                }
            )
            .overlay(shape.stroke(borderColor, lineWidth: borderWidth))
            .offset(x: pressed ? shadowOffset : 0, y: pressed ? shadowOffset : 0)
            .animation(.easeOut(duration: 0.06), value: pressed)
            .fixedSize()
    }
}

private extension View {
    @ViewBuilder
    func applying(font: Font?, foreground: Color) -> some View {
        if let font = font {
            self.font(font).foregroundColor(foreground)
        } else {
            self.foregroundColor(foreground)
        }
    }
}

// MARK: - Pixel box modifier

/// Drop-in modifier for inline boxes that don't need a wrapping container.
/// Equivalent to `PixelCard` rendered as a background.
struct PixelBoxModifier: ViewModifier {
    var fill: Color = Color(hex: "#F5E8C7")
    var borderColor: Color = Color(hex: "#2D2B26")
    var shadowOffset: CGFloat = 4
    var blockSize: CGFloat = 4
    var steps: Int = 2
    var borderWidth: CGFloat = 4

    func body(content: Content) -> some View {
        PixelCard(
            fill: fill,
            borderColor: borderColor,
            shadowOffset: shadowOffset,
            blockSize: blockSize,
            steps: steps,
            borderWidth: borderWidth
        ) {
            content
        }
    }
}

extension View {
    func pixelBox(
        fill: Color = Color(hex: "#F5E8C7"),
        borderColor: Color = Color(hex: "#2D2B26"),
        shadowOffset: CGFloat = 4,
        blockSize: CGFloat = 4,
        steps: Int = 2,
        borderWidth: CGFloat = 4
    ) -> some View {
        modifier(PixelBoxModifier(
            fill: fill,
            borderColor: borderColor,
            shadowOffset: shadowOffset,
            blockSize: blockSize,
            steps: steps,
            borderWidth: borderWidth
        ))
    }
}
