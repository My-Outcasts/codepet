import SwiftUI
import AppKit

// MARK: - Project Color Palette

/// Each project gets a distinct accent color from the brand palette.
/// Colors rotate based on project index.
struct ProjectPalette {
    let fill: Color       // light tinted fill (tab + folder body)
    let mid: Color        // primary accent (buttons, icons, section labels)
    let dark: Color       // darker accent (text on tinted bg)
    let light: Color      // very light tint for folder body background

    /// Brand accent palettes, matching CodepetTheme accents.
    static let palettes: [ProjectPalette] = [
        // Purple — CodepetTheme.accentPurple
        ProjectPalette(
            fill:  Color(hex: "#E8DCFF"),
            mid:   Color(hex: "#7C3AED"),
            dark:  Color(hex: "#5B21B6"),
            light: Color(hex: "#FDFCFF")
        ),
        // Orange — CodepetTheme.accentOrange
        ProjectPalette(
            fill:  Color(hex: "#FFD4B8"),
            mid:   Color(hex: "#E8660A"),
            dark:  Color(hex: "#A04408"),
            light: Color(hex: "#FFFAF6")
        ),
        // Pink — CodepetTheme.accentPink
        ProjectPalette(
            fill:  Color(hex: "#FFD6E5"),
            mid:   Color(hex: "#E0508C"),
            dark:  Color(hex: "#A8305E"),
            light: Color(hex: "#FFFAFC")
        ),
        // Gold — CodepetTheme.accentGold
        ProjectPalette(
            fill:  Color(hex: "#FFEDC0"),
            mid:   Color(hex: "#D49700"),
            dark:  Color(hex: "#8B6914"),
            light: Color(hex: "#FFFDF7")
        ),
        // Blue — CodepetTheme.accentBlue
        ProjectPalette(
            fill:  Color(hex: "#D0E4FE"),
            mid:   Color(hex: "#2563EB"),
            dark:  Color(hex: "#1D4ED8"),
            light: Color(hex: "#FBFCFF")
        ),
        // Coral — CodepetTheme.accentCoral
        ProjectPalette(
            fill:  Color(hex: "#FFD0C8"),
            mid:   Color(hex: "#D94F3A"),
            dark:  Color(hex: "#9C3424"),
            light: Color(hex: "#FFFAF8")
        ),
    ]

    /// Get a palette for a project at the given index (cycles).
    static func forIndex(_ index: Int) -> ProjectPalette {
        palettes[index % palettes.count]
    }
}

// MARK: - Tech-stack tag colors

/// Color for each tech-stack tag pill.
func techTagColor(_ tag: String) -> Color {
    switch tag {
    case "SwiftUI", "UIKit":  return Color(hex: "#7C3AED")
    case "Firebase":          return Color(hex: "#E07020")
    case "React":             return Color(hex: "#2563EB")
    case "Node":              return Color(hex: "#0F9984")
    case "Docker":            return Color(hex: "#2563EB")
    case "Python":            return Color(hex: "#1A6B5C")
    case "Go":                return Color(hex: "#00ADD8")
    case "Rust":              return Color(hex: "#B7410E")
    case "CI/CD":             return Color(hex: "#6B6B6B")
    case "Database":          return Color(hex: "#336791")
    case "API":               return Color(hex: "#D49700")
    case "Tests":             return Color(hex: "#34A853")
    case "Mobile":            return Color(hex: "#E0508C")
    default:                  return Color(hex: "#7C3AED")
    }
}

/// Convert ProjectTag set to sorted human-readable labels.
func projectTagLabels(_ tags: Set<ProjectTag>) -> [String] {
    let mapping: [ProjectTag: String] = [
        .swiftUI: "SwiftUI", .uiKit: "UIKit", .react: "React", .vue: "Vue",
        .angular: "Angular", .python: "Python", .nodeBackend: "Node",
        .goLang: "Go", .rust: "Rust", .firebase: "Firebase", .docker: "Docker",
        .ci: "CI/CD", .database: "Database", .api: "API", .testing: "Tests",
        .mobile: "Mobile",
    ]
    return tags.compactMap { mapping[$0] }.sorted()
}

// MARK: - Pixel Folder Tab Shape

/// A tab shape with stair-step corners on the top, flat bottom.
/// Matches the PixelStaircaseRectangle aesthetic but only applies
/// the staircase to the top-left and top-right corners.
struct PixelFolderTabShape: Shape {
    var blockSize: CGFloat = 4
    var steps: Int = 2

    func path(in rect: CGRect) -> Path {
        let b = blockSize
        let n = steps
        let chamfer = b * CGFloat(n)
        var p = Path()

        // Start: top edge, past top-left chamfer
        p.move(to: CGPoint(x: rect.minX + chamfer, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - chamfer, y: rect.minY))

        // Top-right staircase down-right
        for i in 0..<n {
            let baseX = rect.maxX - b * CGFloat(n - i)
            let baseY = rect.minY + b * CGFloat(i)
            p.addLine(to: CGPoint(x: baseX,     y: baseY + b))
            p.addLine(to: CGPoint(x: baseX + b, y: baseY + b))
        }

        // Right edge straight down to bottom
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))

        // Bottom edge straight across (no staircase)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))

        // Left edge straight up to staircase
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + chamfer))

        // Top-left staircase up-right
        for i in 0..<n {
            let baseX = rect.minX + b * CGFloat(i)
            let baseY = rect.minY + b * CGFloat(n - i)
            p.addLine(to: CGPoint(x: baseX,     y: baseY - b))
            p.addLine(to: CGPoint(x: baseX + b, y: baseY - b))
        }

        p.closeSubpath()
        return p
    }
}

// MARK: - Pixel Art Icons (Streamline Pixel style, no background)

/// Pixel art folder icon traced from Streamline Pixel `folder.svg`.
/// All coordinates live in a 32×32 viewBox; the Shape scales them to
/// fit whatever frame the caller provides.
struct PixelFolderShape: Shape {
    private static let polygons: [[(CGFloat, CGFloat)]] = [
        // Main body (frame + tab + front panel outline)
        [(30.472,3.045),(28.952,3.045),(28.952,1.525),(27.432,1.525),(27.432,-0.005),
         (6.092,-0.005),(6.092,12.195),(1.522,12.195),(1.522,13.715),(9.142,13.715),
         (9.142,12.195),(7.622,12.195),(7.622,1.525),(24.382,1.525),(24.382,7.615),
         (30.472,7.615),(30.472,22.855),(28.952,22.855),(28.952,25.905),(30.472,25.905),
         (30.472,30.475),(32.002,30.475),(32.002,4.575),(30.472,4.575)],
        // Bottom bar
        [(30.472,30.475),(7.622,30.475),(7.622,31.995),(30.472,31.995)],
        // Diagonal line segments (front panel fold)
        [(28.952,19.805),(27.432,19.805),(27.432,22.855),(28.952,22.855)],
        [(27.432,16.765),(25.902,16.765),(25.902,19.805),(27.432,19.805)],
        [(25.902,15.235),(10.672,15.235),(10.672,16.765),(25.902,16.765)],
        [(10.672,13.715),(9.142,13.715),(9.142,15.235),(10.672,15.235)],
        // Stair-step left edge
        [(7.622,27.425),(6.092,27.425),(6.092,30.475),(7.622,30.475)],
        [(6.092,24.385),(4.572,24.385),(4.572,27.425),(6.092,27.425)],
        [(4.572,21.335),(3.052,21.335),(3.052,24.385),(4.572,24.385)],
        [(3.052,18.285),(1.522,18.285),(1.522,21.335),(3.052,21.335)],
        [(1.522,13.715),(0.002,13.715),(0.002,18.285),(1.522,18.285)],
    ]

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 32.0
        let sy = rect.height / 32.0
        var p = Path()
        for poly in Self.polygons {
            guard let first = poly.first else { continue }
            p.move(to: CGPoint(x: first.0 * sx, y: first.1 * sy))
            for v in poly.dropFirst() {
                p.addLine(to: CGPoint(x: v.0 * sx, y: v.1 * sy))
            }
            p.closeSubpath()
        }
        return p
    }
}

/// Pixel art closed-book-with-bookmark icon traced from Streamline Pixel
/// `content-files-close-book-bookmark.svg`. Same 32×32 viewBox.
struct PixelBookShape: Shape {
    private static let polygons: [[(CGFloat, CGFloat)]] = [
        // Right cover + spine top
        [(3.81,1.52),(28.19,1.52),(28.19,3.05),(26.67,3.05),(26.67,4.57),
         (28.19,4.57),(28.19,7.62),(29.72,7.62),(29.72,30.48),(31.24,30.48),
         (31.24,6.1),(29.72,6.1),(29.72,1.52),(31.24,1.52),(31.24,0),(3.81,0)],
        // Left cover + bottom
        [(6.86,30.48),(6.86,7.62),(16,7.62),(16,6.1),(3.81,6.1),(3.81,7.62),
         (5.34,7.62),(5.34,30.48),(3.81,30.48),(3.81,32),(29.72,32),(29.72,30.48)],
        // Bookmark ribbon
        [(25.15,10.67),(23.62,10.67),(23.62,6.1),(22.1,6.1),(22.1,4.57),
         (23.62,4.57),(23.62,3.05),(16,3.05),(16,4.57),(17.53,4.57),
         (17.53,6.1),(19.05,6.1),(19.05,21.33),(20.57,21.33),(20.57,19.81),
         (22.1,19.81),(22.1,18.29),(23.62,18.29),(23.62,19.81),(25.15,19.81),
         (25.15,21.33),(26.67,21.33),(26.67,6.1),(25.15,6.1)],
        // Bookmark top-right corner
        [(25.15,4.57),(23.62,4.57),(23.62,6.1),(25.15,6.1)],
        // Title bar on cover
        [(14.48,3.05),(5.34,3.05),(5.34,4.57),(14.48,4.57)],
        // Spine bottom-left
        [(3.81,28.95),(2.29,28.95),(2.29,30.48),(3.81,30.48)],
        // Spine top-left
        [(3.81,1.52),(2.29,1.52),(2.29,3.05),(3.81,3.05)],
        // Spine vertical bar
        [(2.29,6.1),(3.81,6.1),(3.81,4.57),(2.29,4.57),(2.29,3.05),
         (0.76,3.05),(0.76,28.95),(2.29,28.95)],
    ]

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 32.0
        let sy = rect.height / 32.0
        var p = Path()
        for poly in Self.polygons {
            guard let first = poly.first else { continue }
            p.move(to: CGPoint(x: first.0 * sx, y: first.1 * sy))
            for v in poly.dropFirst() {
                p.addLine(to: CGPoint(x: v.0 * sx, y: v.1 * sy))
            }
            p.closeSubpath()
        }
        return p
    }
}

/// Convenience view that renders a Streamline Pixel icon in a single color.
/// Usage: `PixelArtIcon(kind: .folder, color: palette.mid, size: 24)`
struct PixelArtIcon: View {
    enum Kind { case folder, book }
    let kind: Kind
    let color: Color
    var size: CGFloat = 24

    var body: some View {
        Group {
            switch kind {
            case .folder:
                PixelFolderShape().fill(color)
            case .book:
                PixelBookShape().fill(color)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Reading Icon Kind

/// Reading type derived from the English prefix of `TipReadingItem.kind`.
enum ReadingIconKind {
    case book, essay, guide, series, reference

    init(fromEnglishKind en: String) {
        let prefix = en.split(separator: " ").first.map { String($0).lowercased() } ?? ""
        switch prefix {
        case "book", "novel":                           self = .book
        case "essay", "paper":                          self = .essay
        case "guide":                                   self = .guide
        case "series", "course", "linked", "connected": self = .series
        case "reference", "repo":                       self = .reference
        default:                                        self = .book
        }
    }
}

// MARK: - Multi-Color Pixel Reading Icon

/// Fun multi-color pixel art icon for each reading type.
/// Each icon is a 14×14 pixel grid drawn via Canvas, scaled to `size`.
struct PixelReadingIcon: View {
    let kind: ReadingIconKind
    var size: CGFloat = 28

    var body: some View {
        Canvas { context, canvasSize in
            let grid = Self.grid(for: kind)
            let rows = grid.count
            let cols = grid.first?.count ?? 0
            guard rows > 0, cols > 0 else { return }
            let px = min(canvasSize.width / CGFloat(cols),
                         canvasSize.height / CGFloat(rows))
            for r in 0..<rows {
                for c in 0..<cols {
                    if let color = grid[r][c] {
                        context.fill(
                            Path(CGRect(x: CGFloat(c) * px, y: CGFloat(r) * px,
                                        width: ceil(px), height: ceil(px))),
                            with: .color(color))
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: Grid lookup

    private static func grid(for kind: ReadingIconKind) -> [[Color?]] {
        switch kind {
        case .book:      return bookGrid
        case .essay:     return essayGrid
        case .guide:     return guideGrid
        case .series:    return seriesGrid
        case .reference: return referenceGrid
        }
    }

    // ── Book: red cover · gold ribbon · cream pages ──

    private static let bookGrid: [[Color?]] = {
        let K = Color(hex: "#2D2B26")   // outline
        let R = Color(hex: "#D94444")   // red cover
        let H = Color(hex: "#EF6B6B")   // cover highlight
        let G = Color(hex: "#F0C040")   // gold ribbon
        let P = Color(hex: "#F5F0E0")   // cream pages
        let n: Color? = nil
        return [
            [n,n,n,n,n,n,n,n,n,n,n,n,n,n],
            [n,K,K,K,K,K,K,K,K,K,K,K,K,n],
            [n,K,R,R,R,R,R,R,R,R,K,P,K,n],
            [n,K,R,H,H,R,R,R,R,R,K,P,K,n],
            [n,K,R,R,R,R,G,G,R,R,K,P,K,n],
            [n,K,R,R,R,R,G,G,R,R,K,P,K,n],
            [n,K,R,R,R,R,R,G,R,R,K,P,K,n],
            [n,K,R,R,R,R,R,G,R,R,K,P,K,n],
            [n,K,R,R,R,R,R,R,R,R,K,P,K,n],
            [n,K,R,R,R,R,R,R,R,R,K,P,K,n],
            [n,K,R,R,R,R,R,R,R,R,K,P,K,n],
            [n,K,R,R,R,R,R,R,R,R,K,P,K,n],
            [n,K,K,K,K,K,K,K,K,K,K,K,K,n],
            [n,n,n,n,n,n,n,n,n,n,n,n,n,n],
        ]
    }()

    // ── Essay: parchment scroll · text lines · red wax seal ──

    private static let essayGrid: [[Color?]] = {
        let K = Color(hex: "#2D2B26")
        let C = Color(hex: "#F5E8C7")   // parchment
        let D = Color(hex: "#DDD0B0")   // roll shadow
        let L = Color(hex: "#C0B090")   // text lines
        let S = Color(hex: "#D94444")   // seal
        let n: Color? = nil
        return [
            [n,n,K,K,K,K,K,K,K,K,K,K,n,n],
            [n,K,D,D,D,D,D,D,D,D,D,D,K,n],
            [n,K,C,C,C,C,C,C,C,C,C,C,K,n],
            [n,K,C,L,L,L,L,C,C,C,C,C,K,n],
            [n,K,C,C,C,C,C,C,C,C,C,C,K,n],
            [n,K,C,L,L,L,L,L,C,C,C,C,K,n],
            [n,K,C,C,C,C,C,C,C,C,C,C,K,n],
            [n,K,C,L,L,L,L,C,C,C,C,C,K,n],
            [n,K,C,C,C,C,C,C,C,C,C,C,K,n],
            [n,K,D,D,D,D,D,D,D,D,D,D,K,n],
            [n,n,K,K,K,K,K,K,K,K,K,K,n,n],
            [n,n,n,n,n,n,n,n,K,n,n,n,n,n],
            [n,n,n,n,n,n,n,K,S,K,n,n,n,n],
            [n,n,n,n,n,n,n,n,K,n,n,n,n,n],
        ]
    }()

    // ── Guide: glowing lightbulb ──

    private static let guideGrid: [[Color?]] = {
        let K = Color(hex: "#2D2B26")
        let Y = Color(hex: "#FFE066")   // yellow glass
        let W = Color(hex: "#FFF5B0")   // highlight
        let O = Color(hex: "#FF9020")   // filament
        let A = Color(hex: "#B0B0B0")   // base
        let B = Color(hex: "#888888")   // screw
        let n: Color? = nil
        return [
            [n,n,n,n,n,K,K,K,K,n,n,n,n,n],
            [n,n,n,n,K,Y,Y,Y,Y,K,n,n,n,n],
            [n,n,n,K,Y,W,W,Y,Y,Y,K,n,n,n],
            [n,n,K,Y,Y,W,Y,Y,Y,Y,Y,K,n,n],
            [n,n,K,Y,Y,Y,Y,Y,Y,Y,Y,K,n,n],
            [n,n,K,Y,Y,Y,O,O,Y,Y,Y,K,n,n],
            [n,n,n,K,Y,Y,O,Y,Y,Y,K,n,n,n],
            [n,n,n,n,K,Y,Y,Y,Y,K,n,n,n,n],
            [n,n,n,n,K,K,K,K,K,K,n,n,n,n],
            [n,n,n,n,K,A,A,A,A,K,n,n,n,n],
            [n,n,n,n,n,K,A,A,K,n,n,n,n,n],
            [n,n,n,n,n,K,B,B,K,n,n,n,n,n],
            [n,n,n,n,n,n,K,K,n,n,n,n,n,n],
            [n,n,n,n,n,n,n,n,n,n,n,n,n,n],
        ]
    }()

    // ── Series: three overlapping cards (purple · teal · pink) ──

    private static let seriesGrid: [[Color?]] = {
        let K = Color(hex: "#2D2B26")
        let U = Color(hex: "#C4B5F0")   // purple back card
        let E = Color(hex: "#90E0D0")   // teal middle card
        let I = Color(hex: "#FFB8C8")   // pink front card
        let n: Color? = nil
        return [
            [n,n,n,n,n,n,n,n,n,n,n,n,n,n],
            [n,n,n,n,n,K,K,K,K,K,K,K,K,n],
            [n,n,n,n,n,K,U,U,U,U,U,U,K,n],
            [n,n,n,K,K,K,K,K,K,K,K,U,K,n],
            [n,n,n,K,E,E,E,E,E,E,K,U,K,n],
            [n,K,K,K,K,K,K,K,K,E,K,U,K,n],
            [n,K,I,I,I,I,I,I,K,E,K,U,K,n],
            [n,K,I,I,I,I,I,I,K,E,K,K,K,n],
            [n,K,I,I,I,I,I,I,K,E,K,n,n,n],
            [n,K,I,I,I,I,I,I,K,K,K,n,n,n],
            [n,K,I,I,I,I,I,I,K,n,n,n,n,n],
            [n,K,K,K,K,K,K,K,K,n,n,n,n,n],
            [n,n,n,n,n,n,n,n,n,n,n,n,n,n],
            [n,n,n,n,n,n,n,n,n,n,n,n,n,n],
        ]
    }()

    // ── Reference: monitor with green code ──

    private static let referenceGrid: [[Color?]] = {
        let K = Color(hex: "#2D2B26")
        let M = Color(hex: "#5B8DD9")   // blue frame
        let F = Color(hex: "#E8E8F0")   // screen
        let J = Color(hex: "#50C878")   // green code
        let A = Color(hex: "#B0B0B0")   // stand
        let n: Color? = nil
        return [
            [n,n,n,n,n,n,n,n,n,n,n,n,n,n],
            [n,K,K,K,K,K,K,K,K,K,K,K,K,n],
            [n,K,M,M,M,M,M,M,M,M,M,M,K,n],
            [n,K,M,F,F,F,F,F,F,F,F,M,K,n],
            [n,K,M,F,J,F,J,J,F,F,F,M,K,n],
            [n,K,M,F,F,F,F,F,F,F,F,M,K,n],
            [n,K,M,F,J,J,F,J,F,F,F,M,K,n],
            [n,K,M,F,F,F,F,F,F,F,F,M,K,n],
            [n,K,M,M,M,M,M,M,M,M,M,M,K,n],
            [n,K,K,K,K,K,K,K,K,K,K,K,K,n],
            [n,n,n,n,n,K,K,K,K,n,n,n,n,n],
            [n,n,n,n,K,A,A,A,A,K,n,n,n,n],
            [n,n,n,n,K,K,K,K,K,K,n,n,n,n],
            [n,n,n,n,n,n,n,n,n,n,n,n,n,n],
        ]
    }()
}

// MARK: - Single Project Tab Button

struct ProjectTabButton: View {
    let name: String
    let tags: [String]
    let palette: ProjectPalette
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.pixelSystem(size: 13, weight: .bold))
                    .foregroundColor(isActive ? palette.dark : Color(hex: "#2D2B26").opacity(0.5))
                    .lineLimit(1)

                ForEach(tags.prefix(2), id: \.self) { tag in
                    Text(tag)
                        .font(.pixelSystem(size: 9, weight: .bold))
                        .foregroundColor(isActive ? palette.dark : .white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isActive ? palette.mid.opacity(0.18) : techTagColor(tag))
                        .overlay(
                            Rectangle()
                                .stroke(
                                    isActive ? palette.mid.opacity(0.3) : Color(hex: "#2D2B26").opacity(0.25),
                                    lineWidth: 1.5
                                )
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    if !isActive {
                        PixelFolderTabShape(blockSize: 4, steps: 2)
                            .fill(Color(hex: "#2D2B26").opacity(0.06))
                            .offset(x: 2, y: 2)
                    }
                    // Active tab uses the cream body color so it reads as one
                    // continuous surface with the section; inactive tabs stay grey.
                    PixelFolderTabShape(blockSize: 4, steps: 2)
                        .fill(isActive ? ReflectionTheme.background : Color(hex: "#F0F0F0"))
                    PixelFolderTabShape(blockSize: 4, steps: 2)
                        .stroke(
                            // Active tab outlines in the project's accent so it
                            // matches the folder frame + inner cards; inactive
                            // tabs stay a faint neutral.
                            isActive ? palette.dark : Color(hex: "#2D2B26").opacity(0.18),
                            lineWidth: 3
                        )
                }
            )
        }
        .buttonStyle(.plain)
        .zIndex(isActive ? 10 : 1)
        .offset(y: isActive ? 4 : 0) // overlap body
        // Bottom bridge: covers seam between tab and body
        .background(alignment: .bottom) {
            if isActive {
                ReflectionTheme.background
                    .frame(height: 10)
                    .padding(.horizontal, 2)
                    .offset(y: 8)
            }
        }
    }
}

// MARK: - Folder Content Body

struct ProjectFolderContentView: View {
    let report: ProjectHealthReport
    /// The project these checks belong to — source of brief/domains for plan generation.
    let project: Project
    let readings: [ReadingMatcher.MatchedReading]
    let palette: ProjectPalette
    let uiLanguage: AppLanguage
    let onFeedToClaude: (TipReadingItem, String?) -> Void
    let onOpenURL: (URL) -> Void
    let onLearnMore: (URL) -> Void
    /// nil stage = revert to engine-inferred. Set by the header stage picker.
    let onSetStage: (ProjectStage?) -> Void
    /// Toggle a self-attested check ("Mark done" / undo).
    let onToggleAttestation: (String) -> Void

    /// Generates per-section action plans on demand.
    @ObservedObject var planEnricher: PlanEnricher
    /// Holds the cached plans (plansByKey) the panel reads.
    @EnvironmentObject var tipsState: TipsState
    @EnvironmentObject var feedbackManager: FeatureFeedbackManager

    /// The user actively engaged with Project Health (switched a pillar, expanded
    /// checks, or opened a plan) → fire the one-time first-experience feedback.
    private func markHealthInteracted() {
        feedbackManager.requestIfFirstTime(.projectHealth)
    }

    /// "Coming up later" is collapsed by default — it's forward-looking,
    /// non-actionable context, and at early stages it can be 9+ rows.
    @State private var upcomingExpanded = false

    /// The check whose plan is shown in the modal layer (nil = no sheet).
    @State private var planSheet: PlanSheetTarget?

    /// The pillar whose checks are shown (tab selection). nil = default to the
    /// first active pillar. Only one pillar renders at a time so the panel stays
    /// short and scannable instead of stacking all checks at once.
    @State private var selectedPillar: HealthPillar? = nil

    /// Pillars whose *passed* checks are expanded (the "✓ N done" roll-up).
    /// Completed checks are hidden by default — they're done, not actionable.
    @State private var expandedPassed: Set<HealthPillar> = []

    /// Rule ids whose plan the user has revealed past the free preview.
    /// (Progressive disclosure now; becomes the purchase gate when gating is on.)
    @State private var unlockedPlans: Set<String> = []

    /// English titles of readings already added as references for this project
    /// (mirrors the Codepet-managed block in the project's CLAUDE.md). Drives the
    /// "Add" ↔ "Added" toggle and the references summary. Loaded on appear.
    @State private var addedReferences: Set<String> = []

    /// The references list is collapsed by default — it's set-and-forget context.
    @State private var referencesExpanded = false

    /// Identifiable wrapper so the plan opens via `.sheet(item:)`.
    private struct PlanSheetTarget: Identifiable {
        let result: ProjectHealthResult
        var id: String { result.rule.id }
    }

    /// Pillars that actually have relevant checks for this project, in display order.
    private var activePillars: [HealthPillar] {
        HealthPillar.allCases
            .sorted { $0.order < $1.order }
            .filter { !report.results(for: $0).isEmpty }
    }

    /// The folder body surface — the warm cream used across the app. The active
    /// tab and seam bridge use this same color so the tab reads as continuous
    /// with the section.
    private var bodyBackground: Color { ReflectionTheme.background }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Project header ──
            projectHeader

            // ── Pillar tabs — one pillar's checks at a time ──
            // Tapping a tab swaps the checks below; missing (actionable) ones
            // lead and passed ones roll up into a "✓ N done" line. This keeps
            // the panel short instead of stacking all 26 checks vertically.
            if let pillar = currentPillar {
                pillarTabBar
                pillarContent(pillar)
            }

            // ── Roadmap: next-step beacon + per-department "To build" list ──
            RoadmapSectionView(
                projectPath: project.id,
                stage: report.stage,
                brief: project.companyBrief ?? CompanyBrief(projectName: project.displayName)
            )

            // ── Coming up later (stage-gated checks) — collapsed by default ──
            if !report.upcoming.isEmpty {
                upcomingSection
            }

            // ── Recommended reading ──
            sectionLabel(text: uiLanguage == .vi ? "Sách nên đọc" : "Recommended reading")

            if !readings.isEmpty {
                // Horizontal scroll — cards keep fixed size;
                // arrow peeks when more items exist off-screen.
                readingScroll
            } else {
                // Not enough signal to recommend project-specific books yet.
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12, weight: .medium))
                    Text(uiLanguage == .vi
                         ? "Chưa đủ thông tin về dự án này để gợi ý sách phù hợp. Viết mô tả dự án (project brief) hoặc tiếp tục code ở đây — mình sẽ nhận ra công nghệ bạn dùng và gợi ý sách đúng với nó."
                         : "Not enough info about this project yet to suggest books that fit it. Add a project brief, or keep coding here — I'll learn its tech and recommend reading that matches.")
                        .font(.pixelSystem(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(3)
                }
                .foregroundColor(ReflectionTheme.primaryText.opacity(0.8))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // ── Project references (resources added for the coding agent) ──
            if !addedReferences.isEmpty {
                referencesSummary
            }
        }
        .padding(20)
        // A whisper of the project's color so the body matches its colored border
        // and tab instead of a stark white that reads as out of place. Light
        // enough to keep dark text and accents legible.
        .background(bodyBackground)
        // Plan opens in its own modal layer (keeps the folder compact).
        .sheet(item: $planSheet) { target in
            planSheetView(target.result)
        }
        .onAppear {
            addedReferences = ProjectReferences.loadAdded(projectPath: project.id)
        }
    }

    /// The resources the user has added for this project. They live in a managed
    /// block in the project's CLAUDE.md; this is the in-app view of that list,
    /// with a remove control per item.
    private var referencesSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Collapsed by default (one line: label + count) — set-and-forget
            // context that shouldn't cost height. Expands into wrapping chips so
            // even 10+ references stay compact. Mirrors "Coming up later".
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) { referencesExpanded.toggle() }
            }) {
                HStack(spacing: 6) {
                    Text((uiLanguage == .vi ? "Tài liệu dự án" : "Project references")
                         + " · \(addedReferences.count)")
                        .font(.pixelSystem(size: 13, weight: .bold))
                        .foregroundColor(ReflectionTheme.primaryText.opacity(0.55))
                        .tracking(0.8)
                        .textCase(.uppercase)
                    Image(systemName: referencesExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(ReflectionTheme.primaryText.opacity(0.45))
                    Spacer()
                }
                .padding(.top, 16)
                .padding(.bottom, referencesExpanded ? 8 : 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if referencesExpanded {
                Text(uiLanguage == .vi
                     ? "Đã lưu vào CLAUDE.md — Claude sẽ dùng khi xây dự án này."
                     : "Saved to CLAUDE.md — Claude will use these when building this project.")
                    .font(.pixelSystem(size: 11))
                    .foregroundColor(ReflectionTheme.primaryText.opacity(0.55))
                    .padding(.bottom, 2)

                FlowLayout(spacing: 8) {
                    ForEach(addedReferences.sorted(), id: \.self) { title in
                        referenceChip(title)
                    }
                }
            }
        }
    }

    /// One reference as a compact removable pill (used inside the flow layout).
    private func referenceChip(_ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(palette.dark.opacity(0.7))
            Text(title)
                .font(.pixelSystem(size: 11, weight: .semibold))
                .foregroundColor(ReflectionTheme.primaryText.opacity(0.85))
                .lineLimit(1)
            Button(action: { removeReference(title) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(ReflectionTheme.primaryText.opacity(0.45))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .pixelBox(fill: palette.mid.opacity(0.08), borderColor: palette.dark.opacity(0.25),
                  shadowOffset: 2, blockSize: 2, steps: 1, borderWidth: 2)
        .fixedSize()
    }

    /// Remove a reference by its title key (mirrors deletion from CLAUDE.md).
    private func removeReference(_ key: String) {
        ProjectReferences.remove(projectPath: project.id, key: key)
        withAnimation(.easeInOut(duration: 0.15)) {
            addedReferences.remove(key)
        }
    }

    // ── Project header with icon + score ──

    private var projectHeader: some View {
        // One calm row: identity · stage · overall progress. The old top-right
        // "N/N passed" badge restated the per-pillar tab counts, so it's gone —
        // a slim meter carries the overall number without shouting.
        HStack(spacing: 12) {
            // Project icon — pixel art, no background
            PixelArtIcon(kind: .folder, color: palette.dark, size: 28)

            Text(report.projectName)
                .font(CodepetTheme.body(22, weight: .bold))
                .foregroundColor(ReflectionTheme.primaryText)

            Spacer()

            // Stage menu — drives which checks are relevant now vs. later.
            stageMenu

            // Slim overall progress meter.
            overallProgress
        }
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ReflectionTheme.borderLight)
                .frame(height: 2)
        }
    }

    // ── Overall progress meter ──

    /// A thin track + count that replaces the old "N/N passed" pill. Quiet by
    /// design — the active-pillar tab already carries the detail.
    private var overallProgress: some View {
        let total = max(report.totalCount, 1)
        let frac = CGFloat(report.passedCount) / CGFloat(total)
        return HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.dark.opacity(0.12))
                    .frame(width: 56, height: 5)
                Capsule()
                    .fill(palette.mid)
                    .frame(width: 56 * frac, height: 5)
            }
            Text("\(report.passedCount)/\(report.totalCount)")
                .font(.pixelSystem(size: 11, weight: .bold))
                .foregroundColor(ReflectionTheme.primaryText.opacity(0.6))
        }
    }

    // ── Stage menu ──

    /// A small menu that sets the project's lifecycle stage. The current stage
    /// drives `relevantFrom` gating in the engine. "Auto" reverts to inference.
    /// The "Stage:" label and flag icon were decorative, so the menu now stands
    /// on its own in the header row.
    private var stageMenu: some View {
        Menu {
            ForEach(ProjectStage.allCases) { stage in
                Button(stage.label(uiLanguage)) { onSetStage(stage) }
            }
            Divider()
            Button(uiLanguage == .vi ? "Tự động" : "Auto-detect") { onSetStage(nil) }
        } label: {
            HStack(spacing: 4) {
                Text(report.stage.label(uiLanguage))
                    .font(.pixelSystem(size: 11, weight: .bold))
                    .foregroundColor(palette.dark)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(palette.dark)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                PixelStaircaseRectangle(blockSize: 2, steps: 1)
                    .fill(Color.white)
            )
            .overlay(
                PixelStaircaseRectangle(blockSize: 2, steps: 1)
                    .stroke(Color(hex: "#2D2B26"), lineWidth: 1.5)
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // ── Pillar tabs — one pillar's checks shown at a time ──

    /// The pillar currently displayed. Defaults to the first active pillar.
    private var currentPillar: HealthPillar? {
        selectedPillar ?? activePillars.first
    }

    /// Row of pillar tabs (Engineering · Business · Marketing · Growth). Tapping
    /// one swaps the visible checks below — only one pillar renders at a time so
    /// the panel stays short instead of stacking every check vertically.
    private var pillarTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(activePillars, id: \.self) { pillar in
                    pillarTab(pillar)
                }
            }
            .padding(.vertical, 2)
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func pillarTab(_ pillar: HealthPillar) -> some View {
        let items = report.results(for: pillar)
        let passed = items.filter(\.passed).count
        let isSelected = currentPillar == pillar
        return Button(action: {
            markHealthInteracted()
            withAnimation(.easeInOut(duration: 0.15)) { selectedPillar = pillar }
        }) {
            // Glyph removed — the label + count carry the meaning; the icon was
            // decoration. Active tab fills with the brand accent; the rest stay
            // quiet so "you are here" is unmistakable.
            HStack(spacing: 6) {
                Text("\(pillar.label(uiLanguage).uppercased()) \(passed)/\(items.count)")
                    .font(.pixelSystem(size: 12, weight: .bold))
                    .foregroundColor(isSelected ? .white : ReflectionTheme.primaryText.opacity(0.55))
                    .tracking(0.3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                PixelStaircaseRectangle(blockSize: 2, steps: 1)
                    .fill(isSelected ? palette.mid : Color(hex: "#2D2B26").opacity(0.04))
            )
            .overlay(
                PixelStaircaseRectangle(blockSize: 2, steps: 1)
                    .stroke(isSelected ? Color(hex: "#2D2B26") : palette.dark.opacity(0.25),
                            lineWidth: isSelected ? 2 : 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Checks for the selected pillar: missing (actionable) first, then a
    /// collapsible "✓ N done" roll-up for the completed ones.
    @ViewBuilder
    private func pillarContent(_ pillar: HealthPillar) -> some View {
        let items = report.results(for: pillar)
        let missing = items.filter { !$0.passed }
        let passed = items.filter { $0.passed }
        let passedOpen = expandedPassed.contains(pillar)

        VStack(alignment: .leading, spacing: 0) {
            if missing.isEmpty && passed.isEmpty {
                Text(uiLanguage == .vi ? "Chưa có mục nào ở đây." : "No checks here yet.")
                    .font(.pixelSystem(size: 13))
                    .foregroundColor(ReflectionTheme.primaryText.opacity(0.6))
                    .padding(.vertical, 8)
            }

            ForEach(missing) { result in
                healthRow(result)
            }

            // The completed checks roll up into ONE line. When nothing is missing
            // it reads "All N done" — which previously needed a separate
            // "Everything here is done." banner stacked on top of "N done".
            if !passed.isEmpty {
                passedRollup(pillar: pillar, count: passed.count, open: passedOpen, allDone: missing.isEmpty)
                if passedOpen {
                    ForEach(passed) { result in
                        healthRow(result)
                    }
                }
            }
        }
        .padding(.bottom, 4)
    }

    /// "✓ N done" disclosure that hides completed checks by default — they're
    /// finished, so they shouldn't compete for attention with what's missing.
    private func passedRollup(pillar: HealthPillar, count: Int, open: Bool, allDone: Bool) -> some View {
        Button(action: {
            markHealthInteracted()
            withAnimation(.easeInOut(duration: 0.15)) {
                if open { expandedPassed.remove(pillar) } else { expandedPassed.insert(pillar) }
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(ReflectionTheme.moodCalm)
                Text(allDone
                     ? (uiLanguage == .vi ? "Tất cả \(count) đã xong" : "All \(count) done")
                     : "\(count) \(uiLanguage == .vi ? "đã xong" : "done")")
                    .font(.pixelSystem(size: 12, weight: .bold))
                    .foregroundColor(ReflectionTheme.primaryText.opacity(0.6))
                    .tracking(0.3)
                    .fixedSize()
                Rectangle()
                    .fill(palette.dark.opacity(0.15))
                    .frame(height: 1)
                Text(open ? (uiLanguage == .vi ? "Ẩn" : "Hide")
                          : (uiLanguage == .vi ? "Hiện" : "Show"))
                    .font(.pixelSystem(size: 11, weight: .bold))
                    .foregroundColor(palette.dark.opacity(0.8))
                Image(systemName: open ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(palette.dark.opacity(0.8))
            }
            .padding(.top, 12)
            .padding(.bottom, open ? 6 : 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // ── Section label ──

    /// Minimal section label — no icon, no band, no divider line. Quiet muted
    /// small-caps text; sections are separated by whitespace alone for a clean,
    /// calm look. The leading icon was decorative, so it's gone.
    private func sectionLabel(text: String) -> some View {
        Text(text)
            .font(.pixelSystem(size: 13, weight: .bold))
            .foregroundColor(ReflectionTheme.primaryText.opacity(0.55))
            .tracking(0.8)
            .textCase(.uppercase)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }

    // ── Coming up later (collapsible) ──

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) { upcomingExpanded.toggle() }
            }) {
                // Clock glyph removed (decorative); the chevron stays because it
                // signals the row expands. Matches the quiet section-label style.
                HStack(spacing: 6) {
                    Text((uiLanguage == .vi ? "Sắp tới" : "Coming up later")
                         + " (\(report.upcoming.count))")
                        .font(.pixelSystem(size: 13, weight: .bold))
                        .foregroundColor(ReflectionTheme.primaryText.opacity(0.55))
                        .tracking(0.8)
                        .textCase(.uppercase)
                    Image(systemName: upcomingExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(ReflectionTheme.primaryText.opacity(0.45))
                    Spacer()
                }
                .padding(.top, 16)
                .padding(.bottom, upcomingExpanded ? 8 : 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if upcomingExpanded {
                ForEach(report.upcoming) { result in
                    upcomingRow(result)
                }
            }
        }
    }

    // ── Health check row ──

    private func healthRow(_ result: ProjectHealthResult) -> some View {
        let isMissing = !result.passed
        let planKey = SectionPlan.key(
            projectPath: project.id, ruleId: result.rule.id, stage: report.stage.rawValue
        )

        return HStack(alignment: .center, spacing: 12) {
            // Status marker. Not-yet-done: a simple dot (a task bullet, no box).
            // Passed: the green pixel check. Both occupy a 20pt slot so titles align.
            Group {
                if isMissing {
                    Circle()
                        .fill(ReflectionTheme.primaryText.opacity(0.4))
                        .frame(width: 7, height: 7)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(hex: "#1E6B30"))
                        .frame(width: 20, height: 20)
                        .background(Color(hex: "#B8F0B0"))
                        .overlay(Rectangle().stroke(Color(hex: "#2D2B26"), lineWidth: 2))
                }
            }
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(result.rule.title(uiLanguage))
                    .font(.pixelSystem(size: 15, weight: isMissing ? .bold : .semibold))
                    .foregroundColor(isMissing ? ReflectionTheme.primaryText : ReflectionTheme.primaryText.opacity(0.7))

                Text((isMissing
                      ? result.rule.missingDescription(uiLanguage)
                      : result.rule.description(uiLanguage)).emDashesAsCommas)
                    .font(.pixelSystem(size: 13))
                    .foregroundColor(ReflectionTheme.primaryText.opacity(0.7))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if isMissing, let urlString = result.rule.learnMoreURL, let url = URL(string: urlString) {
                Button(action: { onLearnMore(url) }) {
                    Text(uiLanguage == .vi ? "Tìm hiểu" : "Learn more")
                        .font(.pixelSystem(size: 9, weight: .bold))
                }
                .buttonStyle(PixelButtonStyle(
                    fill: palette.mid, foreground: .white,
                    paddingH: 10, paddingV: 4, blockSize: 2, steps: 1,
                    borderWidth: 2, shadowOffset: 2,
                    font: .pixelSystem(size: 9, weight: .bold)
                ))
            }

            // Get plan / View plan — opens the action plan in a modal layer.
            if isMissing {
                Button(action: { openPlan(result) }) {
                    Text(planButtonLabel(key: planKey))
                        .font(.pixelSystem(size: 9, weight: .bold))
                }
                .buttonStyle(PixelButtonStyle(
                    fill: palette.mid, foreground: .white,
                    paddingH: 10, paddingV: 4, blockSize: 2, steps: 1,
                    borderWidth: 2, shadowOffset: 2,
                    font: .pixelSystem(size: 9, weight: .bold)
                ))
            }

        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    // ── Plan: button label, open, modal layer ──

    private func planButtonLabel(key: String) -> String {
        if tipsState.plansByKey[key] != nil { return uiLanguage == .vi ? "Xem kế hoạch" : "View plan" }
        return uiLanguage == .vi ? "Lập kế hoạch" : "Get plan"
    }

    /// Open the plan in its modal layer and kick off generation (cache-or-fetch).
    private func openPlan(_ result: ProjectHealthResult) {
        markHealthInteracted()
        planSheet = PlanSheetTarget(result: result)
        Task {
            await planEnricher.generatePlan(
                project: project, report: report, result: result,
                language: uiLanguage, tipsState: tipsState
            )
        }
    }

    /// The plan modal: header bar + scrollable body (loading / error / plan).
    @ViewBuilder
    private func planSheetView(_ result: ProjectHealthResult) -> some View {
        let key = SectionPlan.key(
            projectPath: project.id, ruleId: result.rule.id, stage: report.stage.rawValue
        )
        VStack(spacing: 0) {
            // Header bar
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(uiLanguage == .vi ? "Kế hoạch hành động" : "Action plan")
                        .font(.pixelSystem(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                        .tracking(0.5)
                        .textCase(.uppercase)
                    Text(result.rule.title(uiLanguage))
                        .font(.pixelSystem(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                // Regenerate — fetches a fresh plan (e.g. after a prompt change).
                Button(action: {
                    unlockedPlans.remove(result.rule.id)
                    Task {
                        await planEnricher.generatePlan(
                            project: project, report: report, result: result,
                            language: uiLanguage, tipsState: tipsState, force: true
                        )
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(PixelButtonStyle(
                    fill: .white, foreground: palette.dark,
                    paddingH: 9, paddingV: 7, blockSize: 2, steps: 1,
                    borderWidth: 2, shadowOffset: 2,
                    font: .pixelSystem(size: 11, weight: .bold)
                ))
                Button(action: { planSheet = nil }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(PixelButtonStyle(
                    fill: .white, foreground: palette.dark,
                    paddingH: 9, paddingV: 7, blockSize: 2, steps: 1,
                    borderWidth: 2, shadowOffset: 2,
                    font: .pixelSystem(size: 11, weight: .bold)
                ))
            }
            .padding(16)
            .background(palette.dark)

            // Body
            ScrollView {
                Group {
                    if planEnricher.isLoading(key) {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(palette.dark)
                            Text(uiLanguage == .vi ? "Đang lập kế hoạch…" : "Generating plan…")
                                .font(.pixelSystem(size: 12))
                                .foregroundColor(Color(hex: "#2D2B26").opacity(0.85))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                    } else if let plan = tipsState.plansByKey[key] {
                        planContent(plan, result: result)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(Color(hex: "#E8660A"))
                                Text(uiLanguage == .vi
                                     ? "Không lập được kế hoạch."
                                     : "Couldn't generate a plan.")
                                    .font(.pixelSystem(size: 12))
                                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.9))
                            }
                            Button(action: {
                                Task {
                                    await planEnricher.generatePlan(
                                        project: project, report: report, result: result,
                                        language: uiLanguage, tipsState: tipsState, force: true
                                    )
                                }
                            }) {
                                Text(uiLanguage == .vi ? "Thử lại" : "Retry")
                                    .font(.pixelSystem(size: 11, weight: .bold))
                            }
                            .buttonStyle(PixelButtonStyle(
                                fill: palette.mid, foreground: .white,
                                paddingH: 14, paddingV: 7, blockSize: 2, steps: 1,
                                borderWidth: 2, shadowOffset: 2,
                                font: .pixelSystem(size: 11, weight: .bold)
                            ))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 560, height: 540)
        .background(palette.light)
    }

    @ViewBuilder
    private func planContent(_ plan: SectionPlan, result: ProjectHealthResult) -> some View {
        let unlocked = unlockedPlans.contains(result.rule.id)
        // Free preview shows ~half the steps; the rest are blurred behind the
        // unlock CTA. Once unlocked, the whole plan (and pitfalls) is shown.
        let previewCount = max(1, plan.steps.count / 2)
        let visibleCount = unlocked ? plan.steps.count : min(previewCount, plan.steps.count)
        let hiddenCount = plan.steps.count - visibleCount

        VStack(alignment: .leading, spacing: 14) {
            // Summary
            Text(plan.summary)
                .font(.pixelSystem(size: 15, weight: .semibold))
                .foregroundColor(Color(hex: "#2D2B26"))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            // Visible steps
            ForEach(0..<visibleCount, id: \.self) { idx in
                planStepRow(index: idx + 1, step: plan.steps[idx])
            }

            // Locked preview: blurred peek at the next step + unlock CTA
            if !unlocked && hiddenCount > 0 {
                lockedTeaser(plan: plan, result: result,
                             hiddenCount: hiddenCount, nextIndex: visibleCount + 1)
            }

            // Pitfalls (full plan only)
            if unlocked && !plan.pitfalls.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(uiLanguage == .vi ? "TRÁNH" : "AVOID")
                        .font(.pixelSystem(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.55))
                        .tracking(0.5)
                    ForEach(Array(plan.pitfalls.enumerated()), id: \.offset) { _, p in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•").foregroundColor(Color(hex: "#2D2B26").opacity(0.55))
                            Text(p)
                                .font(.pixelSystem(size: 13))
                                .foregroundColor(Color(hex: "#2D2B26").opacity(0.8))
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
    }

    /// Blurred peek at the remaining steps + the unlock CTA. Keeps the panel
    /// compact by default and doubles as the freemium teaser.
    private func lockedTeaser(
        plan: SectionPlan, result: ProjectHealthResult,
        hiddenCount: Int, nextIndex: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // A short, blurred glimpse of the next step so it reads as "there's more".
            if nextIndex - 1 < plan.steps.count {
                planStepRow(index: nextIndex, step: plan.steps[nextIndex - 1])
                    .frame(maxHeight: 64, alignment: .top)
                    .clipped()
                    .blur(radius: 6)
                    .opacity(0.65)
                    .allowsHitTesting(false)
                    .overlay(
                        LinearGradient(
                            colors: [palette.light.opacity(0), palette.light],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }

            Button(action: { revealPlan(result, plan) }) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold))
                    Text((uiLanguage == .vi
                          ? "Mở khoá để xem toàn bộ kế hoạch"
                          : "Unlock to view full plan details")
                         + " (\(hiddenCount))")
                }
            }
            .buttonStyle(PixelButtonStyle(
                fill: palette.mid, foreground: .white,
                paddingH: 14, paddingV: 7, blockSize: 2, steps: 1,
                borderWidth: 2, shadowOffset: 2,
                font: .pixelSystem(size: 11, weight: .bold)
            ))
        }
    }

    /// Reveal the rest of the plan. While gating is OFF the full content is
    /// already present, so this is a free progressive-disclosure reveal. When
    /// gating is ON the withheld steps have no content and this is where a
    /// purchase flow would hook in (step 4 client work, not yet built).
    private func revealPlan(_ result: ProjectHealthResult, _ plan: SectionPlan) {
        withAnimation(.easeInOut(duration: 0.18)) {
            unlockedPlans.insert(result.rule.id)
        }
        // TODO(monetization): if plan.lockedStepCount > 0 (server-gated), route
        // to the purchase flow instead of revealing.
    }

    private func planStepRow(index: Int, step: SectionPlan.Step) -> some View {
        let locked = step.detail == nil
        return HStack(alignment: .top, spacing: 10) {
            // Step number / lock badge
            ZStack {
                Rectangle()
                    .fill(locked ? palette.fill.opacity(0.6) : palette.mid)
                    .frame(width: 26, height: 26)
                    .overlay(Rectangle().stroke(Color(hex: "#2D2B26").opacity(locked ? 0.15 : 0.5), lineWidth: 2))
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.4))
                } else {
                    Text("\(index)")
                        .font(.pixelSystem(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.pixelSystem(size: 15, weight: .bold))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(locked ? 0.5 : 1.0))
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = step.detail {
                    Text(detail)
                        .font(.pixelSystem(size: 13))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.82))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if !step.doneWhen.isEmpty {
                        Text((uiLanguage == .vi ? "Xong khi: " : "Done when: ") + step.doneWhen)
                            .font(.pixelSystem(size: 12))
                            .foregroundColor(Color(hex: "#2D2B26").opacity(0.6))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // ── Upcoming (stage-gated) row ──

    /// A check that isn't relevant yet at the project's current stage. Shown
    /// muted with the stage it unlocks at, so the roadmap is visible without
    /// nagging the user about work that isn't due.
    private func upcomingRow(_ result: ProjectHealthResult) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(ReflectionTheme.primaryText.opacity(0.45))
                .frame(width: 20, height: 20)
                .background(ReflectionTheme.primaryText.opacity(0.06))
                .overlay(
                    Rectangle()
                        .stroke(ReflectionTheme.primaryText.opacity(0.2), lineWidth: 2)
                )

            Text(result.rule.title(uiLanguage))
                .font(.pixelSystem(size: 14))
                .foregroundColor(ReflectionTheme.primaryText.opacity(0.6))

            Spacer()

            // When this check unlocks — quiet text, not a chip, so it reads as a
            // status label rather than a clickable button.
            Text((uiLanguage == .vi ? "Mở ở giai đoạn " : "Unlocks at ")
                 + result.rule.relevantFrom.label(uiLanguage))
                .font(.pixelSystem(size: 10, weight: .semibold))
                .foregroundColor(ReflectionTheme.primaryText.opacity(0.4))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }

    // ── Reading scroll (horizontal, with trailing arrow) ──

    private var readingScroll: some View {
        ZStack(alignment: .trailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(readings.enumerated()), id: \.element.id) { idx, matched in
                        readingCard(matched.item, projectName: matched.projectName, cardIndex: idx)
                            .frame(width: 320)
                    }
                }
                .padding(.bottom, 4) // room for drop shadow
            }

            // Trailing arrow hint when more cards are off-screen
            if readings.count > 2 {
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [bodyBackground.opacity(0), bodyBackground],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 32)

                    ZStack {
                        // Opaque match for the tinted body (light base + tint).
                        palette.light
                        bodyBackground
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(palette.dark)
                    }
                    .frame(width: 20)
                }
                .allowsHitTesting(false)
            }
        }
    }

    // ── Reading card ──

    /// Per-card brand hue — keeps each reading scannable by color. A light tint
    /// of this sits behind a thin border in the same hue (the Profile-box look).
    private static let readingHues: [Color] = [
        Color(hex: "#9538CF"),  // Purple
        Color(hex: "#1C40CF"),  // Blue
        Color(hex: "#E24B4A"),  // Red
        Color(hex: "#029902"),  // Green
        Color(hex: "#F58345"),  // Orange
        Color(hex: "#0EA5A5"),  // Teal
        Color(hex: "#E0457B"),  // Pink
    ]

    private func readingCard(_ item: TipReadingItem, projectName: String?, cardIndex: Int) -> some View {
        // Light tinted "info box" (matches the Profile-tab boxes): a soft tint of
        // the card's hue behind a thin border in the same hue, dark ink. No cover
        // icon, no decorative dots — calm but not boring.
        let hue = Self.readingHues[cardIndex % Self.readingHues.count]
        let textPrimary = Color(hex: "#2D2B26")
        let textSecondary = Color(hex: "#2D2B26").opacity(0.55)
        let textBody = Color(hex: "#2D2B26").opacity(0.78)

        return VStack(alignment: .leading, spacing: 4) {
            Text(item.title(uiLanguage))
                .font(ReflectionTheme.serif(16, weight: .semibold))
                .foregroundColor(textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(item.author) · \(item.kind(uiLanguage))")
                .font(.pixelSystem(size: 11))
                .foregroundColor(textSecondary)

            Text(item.why(uiLanguage).emDashesAsCommas)
                .font(.pixelSystem(size: 12))
                .foregroundColor(textBody)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

            Spacer(minLength: 10)

            let refKey = item.title(.en)
            let isAdded = addedReferences.contains(refKey)
            let isDistilling = planEnricher.isDistilling(
                PlanEnricher.distillKey(projectPath: project.id, title: refKey))

            // ── Bottom: Open + "Add to project references" ──
            // Adding writes the resource into a Codepet-managed block in the
            // project's CLAUDE.md, so the coding agent has it on hand when
            // building — a durable reference, not a throwaway chat.
            HStack(spacing: 14) {
                if let urlString = item.url, let url = URL(string: urlString) {
                    Button(action: { onOpenURL(url) }) {
                        Text(uiLanguage == .vi ? "Mở" : "Open")
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(PixelButtonStyle(
                        fill: Color(hex: "#2D2B26"),
                        foreground: .white,
                        paddingH: 12,
                        paddingV: 5,
                        blockSize: 2,
                        steps: 1,
                        borderWidth: 2,
                        shadowOffset: 2,
                        font: .pixelSystem(size: 10, weight: .semibold)
                    ))
                }

                Button(action: { toggleReference(item) }) {
                    HStack(spacing: 4) {
                        if isDistilling {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: isAdded ? "checkmark" : "plus")
                                .font(.system(size: 9, weight: .bold))
                        }
                        Text(isDistilling
                             ? (uiLanguage == .vi ? "Đang chắt lọc…" : "Distilling…")
                             : (isAdded
                                ? (uiLanguage == .vi ? "Đã thêm" : "Added")
                                : (uiLanguage == .vi ? "Thêm vào dự án" : "Add to project references")))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .font(.pixelSystem(size: 10, weight: .semibold))
                    .foregroundColor(isAdded ? Color(hex: "#1E6B30") : hue)
                }
                .disabled(isDistilling)
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelBox(fill: hue.opacity(0.12), borderColor: hue,
                  shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2)
    }

    /// Add/remove this reading as a project reference, persisting it to the
    /// project's CLAUDE.md and updating the in-memory set so the card reflects it.
    ///
    /// On add we write the plain blurb IMMEDIATELY (so the feature works even if
    /// distillation fails or the backend isn't deployed), then distill in the
    /// background and upgrade that entry in place with concrete principles.
    private func toggleReference(_ item: TipReadingItem) {
        let key = item.title(.en)

        if addedReferences.contains(key) {
            ProjectReferences.remove(projectPath: project.id, key: key)
            withAnimation(.easeInOut(duration: 0.15)) { addedReferences.remove(key) }
            return
        }

        let blurb = "- **\(item.title(.en))** — \(item.author) · \(item.kind(.en)) — \(item.why(.en))"
        ProjectReferences.add(projectPath: project.id, key: key, body: blurb)
        withAnimation(.easeInOut(duration: 0.15)) { addedReferences.insert(key) }

        let resource = DistillReferenceRequest.ResourceDTO(
            title: item.title(.en),
            author: item.author,
            kind: item.kind(.en),
            why: item.why(.en)
        )
        Task {
            let principles = await planEnricher.distillReference(
                project: project, report: report, resource: resource, language: uiLanguage
            )
            guard let principles, !principles.isEmpty else { return }
            // Bail if the user removed it while we were distilling.
            guard ProjectReferences.loadAdded(projectPath: project.id).contains(key) else { return }
            let body = Self.distilledBody(item: item, principles: principles,
                                          projectName: report.projectName)
            ProjectReferences.update(projectPath: project.id, key: key, body: body)
        }
    }

    /// CLAUDE.md body for a distilled reference: a title line + the concrete,
    /// project-specific principles the coding agent should apply.
    private static func distilledBody(item: TipReadingItem, principles: [String], projectName: String) -> String {
        var lines = ["- **\(item.title(.en))** — \(item.author) · \(item.kind(.en))"]
        lines.append("  Apply to \(projectName):")
        for p in principles { lines.append("  - \(p)") }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Empty folder state

struct ProjectFolderEmptyView: View {
    let uiLanguage: AppLanguage

    var body: some View {
        VStack(spacing: 10) {
            PixelArtIcon(kind: .folder, color: ReflectionTheme.mutedText.opacity(0.4), size: 32)

            Text(uiLanguage == .vi
                 ? "Chưa viết mô tả cho dự án này."
                 : "No brief written yet for this project.")
                .font(.pixelSystem(size: 12))
                .foregroundColor(ReflectionTheme.mutedText)

            Text(uiLanguage == .vi
                 ? "Viết mô tả ngắn để pet đưa ra lời khuyên phù hợp hơn."
                 : "Write a short description so your pet can give tailored advice.")
                .font(.pixelSystem(size: 10))
                .foregroundColor(ReflectionTheme.mutedText.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Main Folder Tabs Container

struct ProjectFoldersView: View {
    let projects: [String: Project]
    let readingGroups: [ReadingMatcher.ProjectReadingGroup]
    let healthReports: [ProjectHealthReport]
    let uiLanguage: AppLanguage
    /// Project paths in Reflection's order (most recent first, sessions-only).
    /// When non-empty, the folder tabs follow this exact order so Project Health
    /// stays in lockstep with the Reflection sidebar. Empty → fall back to local
    /// recency (lastSeenAt).
    var orderedProjectPaths: [String] = []
    /// The project the user is currently focused on in Reflection. When set (and
    /// known), Project Health follows it: that project becomes the active folder
    /// tab in real time. nil leaves the local selection alone.
    var syncedProjectPath: String? = nil
    let onFeedToClaude: (TipReadingItem, String?) -> Void
    let onOpenURL: (URL) -> Void
    /// (projectPath, stage) — nil stage reverts to engine inference.
    let onSetStage: (String, ProjectStage?) -> Void
    /// (projectPath, ruleId) — toggle a self-attested check.
    let onToggleAttestation: (String, String) -> Void
    /// Generates per-section action plans (shared across folders).
    @ObservedObject var planEnricher: PlanEnricher

    @State private var selectedProjectPath: String?

    /// How many projects show as folder tabs before the rest collapse into
    /// the "+N more" overflow menu. The folder-tab metaphor reads cleanly at a
    /// small count; beyond that the bar gets crowded and starts to scroll.
    private let maxVisibleTabs = 3

    /// Projects in display order. Mirrors Reflection's group order
    /// (`orderedProjectPaths`) when available — most recent first, sessions-only
    /// — with any remaining known projects appended by local recency. Falls back
    /// to pure recency (lastSeenAt) before Reflection has published an order.
    private var sortedProjects: [(path: String, project: Project)] {
        let byRecency = projects.map { (path: $0.key, project: $0.value) }
            .sorted { $0.project.lastSeenAt > $1.project.lastSeenAt }
        guard !orderedProjectPaths.isEmpty else { return byRecency }

        var seen = Set<String>()
        var result: [(path: String, project: Project)] = []
        for path in orderedProjectPaths {
            guard let project = projects[path], !seen.contains(path) else { continue }
            result.append((path: path, project: project))
            seen.insert(path)
        }
        // Any projects Reflection didn't list (e.g. no sessions) trail behind,
        // newest first, so nothing silently disappears.
        for item in byRecency where !seen.contains(item.path) {
            result.append(item)
        }
        return result
    }

    /// The currently selected project path. A local tab tap (selectedProjectPath)
    /// wins; otherwise we mirror the project focused in Reflection
    /// (syncedProjectPath); otherwise we fall back to the most recent.
    private var activeProjectPath: String {
        if let local = selectedProjectPath, projects[local] != nil { return local }
        if let synced = syncedProjectPath, projects[synced] != nil { return synced }
        return sortedProjects.first?.path ?? ""
    }

    /// Projects rendered as folder tabs: the `maxVisibleTabs` most recent,
    /// newest → oldest. The project focused in Reflection is marked
    /// most-recently-active upstream, so it naturally leads this list.
    private var visibleProjects: [(path: String, project: Project)] {
        Array(sortedProjects.prefix(maxVisibleTabs))
    }

    /// Projects hidden behind the "+N more" menu.
    private var overflowProjects: [(path: String, project: Project)] {
        let visiblePaths = Set(visibleProjects.map { $0.path })
        return sortedProjects.filter { !visiblePaths.contains($0.path) }
    }

    /// Stable palette index keyed to a project's position in the full sorted
    /// list, so its color stays the same whether it's a tab or in the menu.
    private func paletteIndex(for path: String) -> Int {
        sortedProjects.firstIndex(where: { $0.path == path }) ?? 0
    }

    /// Display name, disambiguated with its parent directory when another
    /// project shares the same name (e.g. two `yoga-site` folders).
    private func label(for item: (path: String, project: Project)) -> String {
        let name = item.project.displayName
        let collides = sortedProjects.contains {
            $0.path != item.path && $0.project.displayName == name
        }
        guard collides else { return name }
        let parent = (item.path as NSString).deletingLastPathComponent
        let parentName = (parent as NSString).lastPathComponent
        return parentName.isEmpty ? name : "\(name) · \(parentName)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: uiLanguage == .vi ? "Sức khoẻ dự án" : "Project health")

            if sortedProjects.isEmpty {
                Text(uiLanguage == .vi
                     ? "Chưa có dự án nào được phát hiện."
                     : "No projects detected yet.")
                    .font(ReflectionTheme.serif(13))
                    .foregroundColor(ReflectionTheme.mutedText)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    // ── Tabs row ──
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: 0) {
                            ForEach(visibleProjects, id: \.path) { item in
                                let report = healthReports.first { $0.projectPath == item.path }
                                let tags = report.map { projectTagLabels($0.inferredTags) } ?? []
                                let pal = ProjectPalette.forIndex(paletteIndex(for: item.path))
                                let isActive = item.path == activeProjectPath

                                ProjectTabButton(
                                    name: label(for: item),
                                    tags: Array(tags.prefix(2)),
                                    palette: pal,
                                    isActive: isActive,
                                    action: {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            selectedProjectPath = item.path
                                        }
                                    }
                                )
                            }

                            // ── Overflow menu: "+N more" ──
                            // Sits flush against the last project tab (zero
                            // spacing), matching the gap between the tabs.
                            if !overflowProjects.isEmpty {
                                overflowMenu
                            }
                        }
                        .padding(.leading, 8)
                    }

                    // ── Folder body ──
                    let pal = ProjectPalette.forIndex(paletteIndex(for: activeProjectPath))

                    folderBody(for: activeProjectPath, palette: pal)
                        .background(
                            PixelStaircaseRectangle(blockSize: 4, steps: 2)
                                .fill(pal.light)
                        )
                        // Border + shadow in the project's own accent so the
                        // folder frame matches its tab and inner cards instead of
                        // a generic black outline.
                        .overlay(
                            PixelStaircaseRectangle(blockSize: 4, steps: 2)
                                .stroke(pal.dark, lineWidth: 3)
                        )
                        .clipShape(PixelStaircaseRectangle(blockSize: 4, steps: 2))
                        // Drop-shadow edge so the whole box reads as solidly
                        // thick, matching the Focus Today / reading cards.
                        .background(
                            PixelStaircaseRectangle(blockSize: 4, steps: 2)
                                .fill(pal.dark)
                                .offset(x: 3, y: 3)
                        )
                }
            }
        }
        .onAppear { followSyncedSelection() }
        .onChange(of: syncedProjectPath) { _ in followSyncedSelection() }
    }

    /// Mirror Reflection's focused project: when `syncedProjectPath` names a
    /// known project, make it the active folder tab. The user can still pick a
    /// different tab afterwards; it holds until Reflection's focus changes again.
    private func followSyncedSelection() {
        guard let path = syncedProjectPath, projects[path] != nil else { return }
        if selectedProjectPath != path {
            selectedProjectPath = path
        }
    }

    /// "+N more" tab that drops down the overflow projects. Selecting one
    /// promotes it to the active folder (and into the visible tab strip).
    private var overflowMenu: some View {
        Menu {
            ForEach(overflowProjects, id: \.path) { item in
                Button(label(for: item)) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedProjectPath = item.path
                    }
                }
            }
        } label: {
            // Compact dropdown-arrow tab framed like a project folder tab so it
            // reads as a defined sibling rather than a faint ghost. Uses the
            // same solid border + drop shadow as the project tabs, with the
            // chevron centered. The hidden-project count lives in the tooltip
            // to keep the face minimal.
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(hex: "#2D2B26").opacity(0.5))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        // Drop shadow — same depth as the inactive project tabs.
                        PixelFolderTabShape(blockSize: 4, steps: 2)
                            .fill(Color(hex: "#2D2B26").opacity(0.06))
                            .offset(x: 2, y: 2)
                        // Tab fill — same as the inactive 'sprout'/'codepet-pixel' tabs.
                        PixelFolderTabShape(blockSize: 4, steps: 2)
                            .fill(Color(hex: "#F0F0F0"))
                        // Border — matches the inactive project tabs exactly.
                        PixelFolderTabShape(blockSize: 4, steps: 2)
                            .stroke(Color(hex: "#2D2B26").opacity(0.18), lineWidth: 1.5)
                    }
                )
        }
        // .button style + plain button style renders the label at full color
        // fidelity. The default/borderlessButton menu style dims and restyles
        // custom labels, which washed out the folder-tab border.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(uiLanguage == .vi
              ? "\(overflowProjects.count) dự án khác"
              : "\(overflowProjects.count) more projects")
    }

    @ViewBuilder
    private func folderBody(for projectPath: String, palette: ProjectPalette) -> some View {
        let report = healthReports.first { $0.projectPath == projectPath }
        let readingGroup = readingGroups.first { $0.projectPath == projectPath }
        let readings = readingGroup?.readings ?? []

        if let report = report, let project = projects[projectPath] {
            ProjectFolderContentView(
                report: report,
                project: project,
                readings: readings,
                palette: palette,
                uiLanguage: uiLanguage,
                onFeedToClaude: onFeedToClaude,
                onOpenURL: { NSWorkspace.shared.open($0) },
                onLearnMore: { NSWorkspace.shared.open($0) },
                onSetStage: { stage in onSetStage(projectPath, stage) },
                onToggleAttestation: { ruleId in onToggleAttestation(projectPath, ruleId) },
                planEnricher: planEnricher
            )
        } else {
            ProjectFolderEmptyView(uiLanguage: uiLanguage)
                .padding(20)
                .background(palette.light)
        }
    }
}

// MARK: - Presentation copy cleanup

extension String {
    /// Presentation-time copy cleanup: em-dash clause separators (" — ") read as
    /// commas, which is calmer than the dash. Hyphens in compound words
    /// (goal-directed, zero-item) and numeric ranges (1-8) are left untouched —
    /// only the em-dash (—) is rewritten.
    var emDashesAsCommas: String {
        replacingOccurrences(of: #"\s*—\s*"#, with: ", ", options: .regularExpression)
    }
}

// MARK: - Project references (written for the coding agent)

/// Maintains a Codepet-managed block of reference resources inside a project's
/// `CLAUDE.md`, so the coding agent has them on hand when building. The block is
/// clearly delimited and idempotent: adding the same resource twice is a no-op,
/// and removing the last one strips the block (and an otherwise-untouched
/// CLAUDE.md the app created is left in place — we never clobber user content
/// outside the markers).
enum ProjectReferences {
    private static let startMarker = "<!-- codepet:references:start -->"
    private static let endMarker = "<!-- codepet:references:end -->"

    private static func fileURL(projectPath: String) -> URL {
        URL(fileURLWithPath: projectPath).appendingPathComponent("CLAUDE.md")
    }

    /// (titleKey, body markdown) pairs currently inside the managed block. The
    /// body may be multi-line (a blurb, or a title line + distilled principles):
    /// everything between a `<!-- ref:KEY -->` marker and the next ref/end marker.
    private static func parse(_ content: String) -> [(key: String, body: String)] {
        guard let start = content.range(of: startMarker),
              let end = content.range(of: endMarker),
              start.upperBound <= end.lowerBound else { return [] }
        let block = String(content[start.upperBound..<end.lowerBound])
        let lines = block.components(separatedBy: "\n")
        var result: [(String, String)] = []
        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("<!-- ref:"), line.hasSuffix("-->") {
                let key = line
                    .replacingOccurrences(of: "<!-- ref:", with: "")
                    .replacingOccurrences(of: "-->", with: "")
                    .trimmingCharacters(in: .whitespaces)
                // Capture every line until the next ref marker or the block end.
                var bodyLines: [String] = []
                var j = i + 1
                while j < lines.count,
                      !lines[j].trimmingCharacters(in: .whitespaces).hasPrefix("<!-- ref:") {
                    bodyLines.append(lines[j])
                    j += 1
                }
                let body = bodyLines.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty { result.append((key, body)) }
                i = j
                continue
            }
            i += 1
        }
        return result
    }

    private static func renderBlock(_ entries: [(key: String, body: String)]) -> String {
        var s = startMarker + "\n"
        s += "## 📚 Project references (added via Codepet)\n"
        s += "Resources to draw on when building this project — apply their principles where relevant.\n\n"
        for e in entries {
            s += "<!-- ref:\(e.key) -->\n\(e.body)\n\n"
        }
        s += endMarker
        return s
    }

    private static func write(projectPath: String, entries: [(key: String, body: String)]) {
        let url = fileURL(projectPath: projectPath)
        var content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if let start = content.range(of: startMarker),
           let end = content.range(of: endMarker),
           start.lowerBound <= end.upperBound {
            let replacement = entries.isEmpty ? "" : renderBlock(entries)
            content.replaceSubrange(start.lowerBound..<end.upperBound, with: replacement)
        } else if !entries.isEmpty {
            if !content.isEmpty, !content.hasSuffix("\n") { content += "\n" }
            if !content.isEmpty { content += "\n" }
            content += renderBlock(entries) + "\n"
        }
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// English titles currently saved as references for this project.
    static func loadAdded(projectPath: String) -> Set<String> {
        let url = fileURL(projectPath: projectPath)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Set(parse(content).map { $0.key })
    }

    /// Add a resource if absent (no-op if already present).
    static func add(projectPath: String, key: String, body: String) {
        let content = (try? String(contentsOf: fileURL(projectPath: projectPath), encoding: .utf8)) ?? ""
        var entries = parse(content)
        guard !entries.contains(where: { $0.key == key }) else { return }
        entries.append((key, body))
        write(projectPath: projectPath, entries: entries)
    }

    /// Replace an existing entry's body in place (e.g. upgrade a blurb to the
    /// distilled principles). Appends if the key isn't present yet.
    static func update(projectPath: String, key: String, body: String) {
        let content = (try? String(contentsOf: fileURL(projectPath: projectPath), encoding: .utf8)) ?? ""
        var entries = parse(content)
        if let idx = entries.firstIndex(where: { $0.key == key }) {
            entries[idx].body = body
        } else {
            entries.append((key, body))
        }
        write(projectPath: projectPath, entries: entries)
    }

    static func remove(projectPath: String, key: String) {
        let content = (try? String(contentsOf: fileURL(projectPath: projectPath), encoding: .utf8)) ?? ""
        var entries = parse(content)
        entries.removeAll { $0.key == key }
        write(projectPath: projectPath, entries: entries)
    }
}
