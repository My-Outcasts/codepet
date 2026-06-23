import SwiftUI

// MARK: - Diagram model
//
// A dictionary term's "Analogy" section is replaced by a small, labeled visual
// diagram. To keep ~150 terms maintainable we DON'T draw a bespoke picture per
// term — instead each term declares ONE of a handful of reusable templates and
// supplies a few bilingual label strings. The template view does the drawing,
// built entirely from the app's existing pixel primitives (`.pixelBox`,
// `CodepetTheme`, SF Symbols).

/// Which reusable diagram a term renders. Each case documents its label slots.
enum DiagramTemplate: String, Hashable {
    /// A named box with a value inside. labels: [0]=name, [1]=value.
    /// Used by: variable, constant, string, number, boolean.
    case labeledBox
    /// input ▸ machine ▸ output. labels: [0]=input, [1]=machine, [2]=output.
    /// Used by: function, parameter, return-value, pure-function, side-effect.
    case beforeAfter
    /// A condition that splits into two branches. labels: [0]=condition, [1]=true, [2]=false.
    /// Used by: if-else, conditional.
    case fork
    /// A repeating body with a stop condition. labels: [0]=body, [1]=stop-when.
    /// Used by: loop, iteration, break-continue.
    case cycle
    /// Two nodes exchanging a request and a response.
    /// labels: [0]=client, [1]=request, [2]=server, [3]=response.
    /// Used by: http, api.
    case requestResponse
    /// Ordered snapshots on a line. labels: each label = one snapshot (2–4).
    /// Used by: git, commit, branch, pull-request.
    case timeline
    /// A row of numbered slots, each holding one value. labels: each = one item (2–4).
    /// Used by: array.
    case indexedSlots
    /// Concentric boxes shrinking inward to a base case. labels: outer→inner (2–4),
    /// last label = the stop. Used by: recursion.
    case nesting
    /// A braced container of "key: value" rows. labels: each = one "key: value" line.
    /// Used by: json.
    case keyValue
    /// Two panels side by side with a link between them.
    /// labels: [0]=left title, [1]=left detail, [2]=right title, [3]=right detail.
    /// Used by: frontend-backend.
    case twoSides
    /// Two stacked layers (structure under style). labels: [0]=bottom, [1]=top,
    /// [2]="bottom"|"top" = which layer this term highlights. Used by: html, css.
    case layers
    /// A typed command and the output it produces. labels: [0]=command, [1]=output.
    /// Used by: terminal, package-manager.
    case commandFlow
    /// You hand a callback to a worker; later it calls you back.
    /// labels: [0]=you, [1]=hand-over, [2]=worker, [3]=call-back. Used by: callback.
    case handBack
    /// A main input▸fn▸result path plus a branch to an outside effect.
    /// labels: [0]=input, [1]=fn, [2]=result, [3]=side effect. Used by: side-effect.
    case mainPlusEffects
}

/// Semantic accent so term data never imports SwiftUI `Color`.
enum DiagramAccent: Hashable {
    case purple, pink, gold, teal, orange, blue

    var color: Color {
        switch self {
        case .purple: return CodepetTheme.accentPurple
        case .pink:   return CodepetTheme.accentPink
        case .gold:   return CodepetTheme.accentGold
        case .teal:   return CodepetTheme.accentTeal
        case .orange: return CodepetTheme.accentOrange
        case .blue:   return CodepetTheme.accentBlue
        }
    }
}

/// A term's diagram declaration: template + positional bilingual labels.
struct DiagramSpec: Hashable {
    let template: DiagramTemplate
    let labels: [L10n]
    let accent: DiagramAccent
    let caption: L10n?

    init(_ template: DiagramTemplate,
         _ labels: [L10n],
         accent: DiagramAccent = .purple,
         caption: L10n? = nil) {
        self.template = template
        self.labels = labels
        self.accent = accent
        self.caption = caption
    }
}

// MARK: - Dispatch view

/// Renders a `DiagramSpec` by dispatching to its template view, with an
/// optional caption underneath. Fixed vertical band so cards don't jump.
struct DictionaryDiagramView: View {
    @Environment(\.uiLanguage) private var lang
    let spec: DiagramSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            template
                .frame(maxWidth: .infinity, minHeight: 110, alignment: .center)
                .padding(.vertical, 6)

            if let caption = spec.caption {
                Text(markdown: caption(lang))
                    .font(CodepetTheme.body(13))
                    .foregroundColor(CodepetTheme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var template: some View {
        switch spec.template {
        case .labeledBox:      LabeledBoxDiagram(spec: spec)
        case .beforeAfter:     BeforeAfterDiagram(spec: spec)
        case .fork:            ForkDiagram(spec: spec)
        case .cycle:           CycleDiagram(spec: spec)
        case .requestResponse: RequestResponseDiagram(spec: spec)
        case .timeline:        TimelineDiagram(spec: spec)
        case .indexedSlots:    IndexedSlotsDiagram(spec: spec)
        case .nesting:         NestingDiagram(spec: spec)
        case .keyValue:        KeyValueDiagram(spec: spec)
        case .twoSides:        TwoSidesDiagram(spec: spec)
        case .layers:          LayersDiagram(spec: spec)
        case .commandFlow:     CommandFlowDiagram(spec: spec)
        case .handBack:        HandBackDiagram(spec: spec)
        case .mainPlusEffects: MainPlusEffectsDiagram(spec: spec)
        }
    }
}

// MARK: - Shared diagram primitives

/// A chunky pixel box holding a short string — the workhorse of every template.
private struct DiagramBox: View {
    let text: String
    let accent: Color
    var mono: Bool = false
    var emphasized: Bool = false

    var body: some View {
        Text(text)
            .font(mono
                  ? .system(size: 15, weight: .semibold, design: .monospaced)
                  : .pixelSystem(size: 14, weight: .semibold))
            .foregroundColor(CodepetTheme.primaryText)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .pixelBox(
                fill: accent.opacity(emphasized ? 0.22 : 0.14),
                shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2
            )
    }
}

/// A small rounded "sticker" / chip label.
private struct DiagramChip: View {
    let text: String
    let accent: Color

    var body: some View {
        Text(text)
            .font(.pixelSystem(size: 12, weight: .semibold))
            .foregroundColor(accent)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(accent.opacity(0.16))
            )
    }
}

private struct DiagramArrow: View {
    var systemName: String = "arrow.right"
    var color: Color = CodepetTheme.mutedText

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(color)
    }
}

/// Convenience: resolve positional label `i` for the current language.
private func label(_ spec: DiagramSpec, _ i: Int, _ lang: AppLanguage, default def: String = "") -> String {
    guard spec.labels.indices.contains(i) else { return def }
    return spec.labels[i](lang)
}

/// A tiny muted caption naming a piece's ROLE (e.g. "you give", "if true").
/// This is what makes a diagram teach instead of assume — every template uses it
/// to say *what each part is*, not just show it.
private func roleCaption(_ text: String) -> some View {
    Text(text)
        .font(.pixelSystem(size: 11, weight: .semibold))
        .foregroundColor(CodepetTheme.bodyText)
        .lineLimit(1)
        .fixedSize()
}

// MARK: - Templates

/// A named box with a value inside (variable, constant, string, number, boolean).
///
/// Drawn as ONE labeled container — the name is a colored band (the sticker on
/// the box), the value sits in the body below it — with "name"/"value" role tags
/// so the picture teaches the concept instead of assuming it.
private struct LabeledBoxDiagram: View {
    @Environment(\.uiLanguage) private var lang
    let spec: DiagramSpec

    private let bandHeight: CGFloat = 36
    private let bodyHeight: CGFloat = 44
    private let ink = Color(hex: "#2D2B26")

    var body: some View {
        let name = label(spec, 0, lang, default: "name")
        let value = label(spec, 1, lang)
        let accent = spec.accent.color
        let nameRole = lang == .vi ? "tên" : "name"
        let valueRole = lang == .vi ? "giá trị" : "value"

        HStack(spacing: 8) {
            // Role tags, each centred on the band it points at.
            VStack(spacing: 0) {
                roleTag(nameRole, tint: accent).frame(height: bandHeight)
                roleTag(valueRole, tint: CodepetTheme.mutedText).frame(height: bodyHeight)
            }

            // The labeled box: name band (the sticker) over the value body.
            VStack(spacing: 0) {
                Text(name)
                    .font(.pixelSystem(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .frame(height: bandHeight)
                    .background(accent)

                Rectangle().fill(ink).frame(height: 2)

                Text(value.isEmpty ? "…" : value)
                    .font(.system(size: 19, weight: .bold, design: .monospaced))
                    .foregroundColor(CodepetTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .frame(height: bodyHeight)
                    // Opaque white base UNDER the translucent tint — without it
                    // the dark pixel-shadow rectangle behind the box bleeds
                    // through the 14%-alpha fill and the value row goes dark.
                    .background(
                        ZStack {
                            Color.white
                            accent.opacity(0.14)
                        }
                    )
            }
            .frame(width: 150)
            .overlay(Rectangle().stroke(ink, lineWidth: 2))
            .background(Rectangle().fill(ink).offset(x: 3, y: 3))   // pixel shadow
        }
        .fixedSize()
    }

    private func roleTag(_ text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.pixelSystem(size: 12, weight: .semibold))
                .foregroundColor(CodepetTheme.bodyText)
                .lineLimit(1)
                .fixedSize()
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(tint.opacity(0.8))
        }
    }
}

/// input ▸ machine ▸ output (function, parameter, return-value, pure-function, side-effect).
/// Each box carries a role caption so the picture reads as a sentence:
/// "you give X → the function runs → you get back Y".
private struct BeforeAfterDiagram: View {
    @Environment(\.uiLanguage) private var lang
    let spec: DiagramSpec

    var body: some View {
        let input = label(spec, 0, lang, default: "input")
        let machine = label(spec, 1, lang, default: "f()")
        let output = label(spec, 2, lang, default: "output")
        let inRole = lang == .vi ? "đưa vào" : "you give"
        let fnRole = lang == .vi ? "hàm" : "the function"
        let outRole = lang == .vi ? "nhận lại" : "you get back"
        HStack(alignment: .top, spacing: 8) {
            step(input, role: inRole, accent: CodepetTheme.mutedText)
            arrow
            step(machine, role: fnRole, accent: spec.accent.color, mono: true, emphasized: true)
            arrow
            step(output, role: outRole, accent: spec.accent.color)
        }
    }

    private var arrow: some View {
        DiagramArrow().padding(.top, 13)   // line up with the box centre, above its caption
    }

    private func step(_ text: String, role: String, accent: Color, mono: Bool = false, emphasized: Bool = false) -> some View {
        VStack(spacing: 5) {
            DiagramBox(text: text, accent: accent, mono: mono, emphasized: emphasized)
            roleCaption(role)
        }
    }
}

/// A condition splitting into a true branch and a false branch (if-else, conditional).
/// The condition is named as the true/false question; each branch says which
/// answer leads there, so the fork reads itself.
private struct ForkDiagram: View {
    @Environment(\.uiLanguage) private var lang
    let spec: DiagramSpec

    var body: some View {
        let condition = label(spec, 0, lang, default: "condition?")
        let yes = label(spec, 1, lang, default: "true")
        let no = label(spec, 2, lang, default: "false")
        let qRole = lang == .vi ? "câu hỏi đúng / sai" : "true-or-false question"
        let yesRole = lang == .vi ? "nếu đúng" : "if true"
        let noRole = lang == .vi ? "nếu sai" : "if false"
        VStack(spacing: 7) {
            VStack(spacing: 4) {
                roleCaption(qRole)
                DiagramBox(text: condition, accent: spec.accent.color, mono: true, emphasized: true)
            }
            DiagramArrow(systemName: "arrow.down", color: spec.accent.color.opacity(0.6))
            HStack(alignment: .top, spacing: 16) {
                branch(symbol: "checkmark", role: yesRole, text: yes, tint: CodepetTheme.accentTeal)
                branch(symbol: "xmark", role: noRole, text: no, tint: CodepetTheme.accentOrange)
            }
        }
    }

    private func branch(symbol: String, role: String, text: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(tint)
                roleCaption(role)
            }
            DiagramBox(text: text, accent: tint)
        }
    }
}

/// A repeating body with a stop condition (loop, iteration, break-continue).
/// The circular arrow is named "repeat", the body box "each pass", and the stop
/// row keeps its own exit wording — so it's clear what loops and what ends it.
private struct CycleDiagram: View {
    @Environment(\.uiLanguage) private var lang
    let spec: DiagramSpec

    var body: some View {
        let body = label(spec, 0, lang, default: "do this")
        let stop = label(spec, 1, lang)
        let repeatRole = lang == .vi ? "lặp lại" : "repeat"
        let eachRole = lang == .vi ? "mỗi vòng" : "each pass"
        HStack(spacing: 12) {
            VStack(spacing: 3) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(spec.accent.color)
                roleCaption(repeatRole)
            }
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    roleCaption(eachRole)
                    DiagramBox(text: body, accent: spec.accent.color, emphasized: true)
                }
                if !stop.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(CodepetTheme.accentOrange)
                        Text(stop)
                            .font(.pixelSystem(size: 11, weight: .semibold))
                            .foregroundColor(CodepetTheme.bodyText)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
        }
    }
}

/// Two nodes exchanging a request and a response (http, api).
/// Numbered role captions ("① sends request" / "② gets response") show the order
/// and direction so the back-and-forth is legible, not just two arrows.
private struct RequestResponseDiagram: View {
    @Environment(\.uiLanguage) private var lang
    let spec: DiagramSpec

    var body: some View {
        let client = label(spec, 0, lang, default: "client")
        let request = label(spec, 1, lang, default: "request")
        let server = label(spec, 2, lang, default: "server")
        let response = label(spec, 3, lang, default: "response")
        let reqRole = lang == .vi ? "① gửi yêu cầu" : "① sends request"
        let resRole = lang == .vi ? "② nhận trả lời" : "② gets response"
        HStack(spacing: 10) {
            DiagramBox(text: client, accent: spec.accent.color)
            VStack(spacing: 8) {
                exchange(role: reqRole, text: request, forward: true, tint: spec.accent.color)
                exchange(role: resRole, text: response, forward: false, tint: CodepetTheme.accentTeal)
            }
            DiagramBox(text: server, accent: spec.accent.color, emphasized: true)
        }
    }

    private func exchange(role: String, text: String, forward: Bool, tint: Color) -> some View {
        VStack(spacing: 2) {
            roleCaption(role)
            HStack(spacing: 4) {
                if !forward {
                    Image(systemName: "arrow.left").font(.system(size: 11, weight: .bold)).foregroundColor(tint)
                }
                Text(text)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(CodepetTheme.bodyText)
                    .lineLimit(1)
                    .fixedSize()
                if forward {
                    Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)).foregroundColor(tint)
                }
            }
        }
    }
}

/// Ordered captioned snapshots — a chain of little "photos" (git, commit,
/// pull-request). The body text calls git "a photo of the whole project with a
/// note" and history "a chain of photos", so each node is drawn AS a snapshot:
/// a framed photo glyph with its note underneath and an order number tucked in
/// the corner. A "jump back" return cue + "time →" axis pay off the caption.
private struct TimelineDiagram: View {
    @Environment(\.uiLanguage) private var lang
    let spec: DiagramSpec

    var body: some View {
        let snapshots: [String] = spec.labels.isEmpty
            ? ["•", "•", "•"]
            : spec.labels.map { $0(lang) }
        let axis = lang == .vi ? "quay lại bản bất kỳ · thời gian →"
                               : "jump back to any · time →"
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                ForEach(Array(snapshots.enumerated()), id: \.offset) { idx, snap in
                    snapshotCard(snap, index: idx + 1)
                    if idx < snapshots.count - 1 {
                        DiagramArrow(color: spec.accent.color.opacity(0.7))
                            .padding(.top, 12)   // line up with the photo centre
                    }
                }
            }
            HStack(spacing: 5) {
                Image(systemName: "arrow.uturn.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(spec.accent.color.opacity(0.7))
                roleCaption(axis)
            }
        }
    }

    /// One snapshot: a framed "photo" with the commit order in the corner and
    /// the note (commit message) as a caption below.
    private func snapshotCard(_ note: String, index: Int) -> some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topLeading) {
                Image(systemName: "photo.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(spec.accent.color)
                    .frame(width: 58, height: 40)
                    .pixelBox(
                        fill: spec.accent.color.opacity(0.14),
                        shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2
                    )
                ZStack {
                    Circle()
                        .fill(spec.accent.color)
                        .overlay(Circle().stroke(Color(hex: "#2D2B26"), lineWidth: 1.5))
                    Text("\(index)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 16, height: 16)
                .offset(x: -5, y: -5)
            }
            Text(note)
                .font(.pixelSystem(size: 11, weight: .semibold))
                .foregroundColor(CodepetTheme.bodyText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .fixedSize()
        }
    }
}

// MARK: - Phase 1 templates

/// A row of numbered slots, each holding one value (array).
/// The index numbers ARE the lesson: you reach each item by its position from 0.
private struct IndexedSlotsDiagram: View {
    @Environment(\.uiLanguage) private var lang
    let spec: DiagramSpec

    var body: some View {
        let items = spec.labels.isEmpty ? ["a", "b", "c"] : spec.labels.map { $0(lang) }
        let posRole = lang == .vi ? "vị trí" : "position"
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                VStack(spacing: 4) {
                    Text("[\(idx)]")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(spec.accent.color)
                    DiagramBox(text: item, accent: spec.accent.color, mono: true, emphasized: idx == 0)
                    if idx == 0 { roleCaption(posRole) } else { roleCaption(" ") }
                }
            }
        }
    }
}

/// Concentric boxes shrinking inward to a base case (recursion).
/// Each frame is the same problem on a smaller piece; the innermost is the stop.
private struct NestingDiagram: View {
    @Environment(\.uiLanguage) private var lang
    let spec: DiagramSpec

    var body: some View {
        let layers = spec.labels.isEmpty ? ["f(3)", "f(2)", "f(1)"] : spec.labels.map { $0(lang) }
        let stopRole = lang == .vi ? "điểm dừng" : "stop here"
        let ink = Color(hex: "#2D2B26")
        ZStack {
            ForEach(Array(layers.enumerated()), id: \.offset) { idx, text in
                let depth = layers.count - 1 - idx        // outermost = largest
                let isBase = idx == layers.count - 1
                VStack(spacing: 2) {
                    Text(text)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(CodepetTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if isBase { roleCaption(stopRole) }
                }
                .padding(.horizontal, 12)
                .frame(width: CGFloat(96 + depth * 56), height: CGFloat(40 + depth * 26), alignment: .top)
                .padding(.top, 8)
                .background(
                    Rectangle().fill(spec.accent.color.opacity(isBase ? 0.28 : 0.10))
                )
                .overlay(Rectangle().stroke(ink, lineWidth: 2))
            }
        }
    }
}

/// A braced container of "key: value" rows (json).
private struct KeyValueDiagram: View {
    @Environment(\.uiLanguage) private var lang
    let spec: DiagramSpec

    var body: some View {
        let rows = spec.labels.isEmpty ? ["name: \"Ada\""] : spec.labels.map { $0(lang) }
        let nameRole = lang == .vi ? "tên" : "name"
        let valueRole = lang == .vi ? "giá trị" : "value"
        let accent = spec.accent.color
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                roleCaption(nameRole)
                roleCaption(valueRole)
            }
            .padding(.leading, 18)

            VStack(alignment: .leading, spacing: 4) {
                Text("{").font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundColor(accent)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Text(row)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(CodepetTheme.primaryText)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.leading, 16)
                }
                Text("}").font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundColor(accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .pixelBox(fill: accent.opacity(0.10), shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2)
        }
    }
}

/// Two panels side by side with a link between them (frontend-backend).
private struct TwoSidesDiagram: View {
    @Environment(\.uiLanguage) private var lang
    let spec: DiagramSpec

    var body: some View {
        let leftTitle = label(spec, 0, lang, default: "Front")
        let leftSub = label(spec, 1, lang)
        let rightTitle = label(spec, 2, lang, default: "Back")
        let rightSub = label(spec, 3, lang)
        let seeRole = lang == .vi ? "bạn nhìn thấy" : "you see"
        let hiddenRole = lang == .vi ? "chạy ngầm" : "runs hidden"
        HStack(alignment: .top, spacing: 8) {
            panel(title: leftTitle, sub: leftSub, role: seeRole, accent: spec.accent.color)
            VStack(spacing: 2) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(CodepetTheme.mutedText)
            }
            .padding(.top, 24)
            panel(title: rightTitle, sub: rightSub, role: hiddenRole, accent: CodepetTheme.accentBlue)
        }
    }

    private func panel(title: String, sub: String, role: String, accent: Color) -> some View {
        VStack(spacing: 5) {
            roleCaption(role)
            VStack(spacing: 4) {
                Text(title)
                    .font(.pixelSystem(size: 12, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !sub.isEmpty {
                    Text(sub)
                        .font(CodepetTheme.body(10))
                        .foregroundColor(CodepetTheme.mutedText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: 124)
            .pixelBox(fill: accent.opacity(0.12), shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2)
        }
    }
}

/// Two stacked layers — structure under style (html, css).
/// labels[2] picks which layer this term highlights.
private struct LayersDiagram: View {
    @Environment(\.uiLanguage) private var lang
    let spec: DiagramSpec

    var body: some View {
        let bottom = label(spec, 0, lang, default: "HTML")
        let top = label(spec, 1, lang, default: "CSS")
        let highlightTop = label(spec, 2, lang, default: "bottom") == "top"
        VStack(spacing: 6) {
            plate(text: top, highlighted: highlightTop)
            plate(text: bottom, highlighted: !highlightTop)
        }
    }

    private func plate(text: String, highlighted: Bool) -> some View {
        Text(text)
            .font(.pixelSystem(size: 12, weight: .semibold))
            .foregroundColor(highlighted ? CodepetTheme.primaryText : CodepetTheme.mutedText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(width: 220)
            .pixelBox(
                fill: spec.accent.color.opacity(highlighted ? 0.22 : 0.07),
                shadowOffset: highlighted ? 3 : 1, blockSize: 2, steps: 2,
                borderWidth: highlighted ? 3 : 2
            )
            .opacity(highlighted ? 1 : 0.85)
    }
}

/// A typed command and the output it produces (terminal, package-manager).
private struct CommandFlowDiagram: View {
    @Environment(\.uiLanguage) private var lang
    let spec: DiagramSpec

    var body: some View {
        let command = label(spec, 0, lang, default: "command")
        let output = label(spec, 1, lang, default: "output")
        let typeRole = lang == .vi ? "bạn gõ" : "you type"
        let outRole = lang == .vi ? "máy trả về" : "computer shows"
        let ink = Color(hex: "#2D2B26")
        VStack(alignment: .leading, spacing: 4) {
            roleCaption(typeRole)
            HStack(spacing: 6) {
                Text("$").font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(spec.accent.color)
                Text(command)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: 260, alignment: .leading)
            .background(Rectangle().fill(ink))

            DiagramArrow(systemName: "arrow.down", color: spec.accent.color.opacity(0.6))
                .padding(.leading, 16)

            roleCaption(outRole)
            Text(output)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(CodepetTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: 260, alignment: .leading)
                .pixelBox(fill: spec.accent.color.opacity(0.10), shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2)
        }
    }
}

/// You hand a callback to a worker; later it calls you back (callback).
/// Two ordered steps make the "don't wait — get notified later" idea concrete.
private struct HandBackDiagram: View {
    @Environment(\.uiLanguage) private var lang
    let spec: DiagramSpec

    var body: some View {
        let you = label(spec, 0, lang, default: "you")
        let handOver = label(spec, 1, lang, default: "hand callback")
        let worker = label(spec, 2, lang, default: "worker")
        let callBack = label(spec, 3, lang, default: "calls back")
        VStack(spacing: 8) {
            step(num: "①", from: you, action: handOver, to: worker,
                 forward: true, tint: spec.accent.color)
            step(num: "②", from: worker, action: callBack, to: you,
                 forward: false, tint: CodepetTheme.accentTeal)
        }
    }

    private func step(num: String, from: String, action: String, to: String, forward: Bool, tint: Color) -> some View {
        HStack(spacing: 6) {
            DiagramBox(text: from, accent: forward ? spec.accent.color : CodepetTheme.mutedText)
            VStack(spacing: 1) {
                roleCaption("\(num) \(action)")
                Image(systemName: forward ? "arrow.right" : "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(tint)
            }
            DiagramBox(text: to, accent: forward ? CodepetTheme.mutedText : spec.accent.color)
        }
    }
}

/// A main input▸fn▸result path plus a branch to an outside effect (side-effect).
private struct MainPlusEffectsDiagram: View {
    @Environment(\.uiLanguage) private var lang
    let spec: DiagramSpec

    var body: some View {
        let input = label(spec, 0, lang, default: "input")
        let fn = label(spec, 1, lang, default: "f()")
        let result = label(spec, 2, lang, default: "result")
        let effect = label(spec, 3, lang, default: "writes a file")
        let mainRole = lang == .vi ? "việc chính" : "the main job"
        let sideRole = lang == .vi ? "kèm theo (hiệu ứng phụ)" : "on the side (side effect)"
        VStack(spacing: 8) {
            VStack(spacing: 4) {
                roleCaption(mainRole)
                HStack(spacing: 6) {
                    DiagramBox(text: input, accent: CodepetTheme.mutedText)
                    DiagramArrow()
                    DiagramBox(text: fn, accent: spec.accent.color, mono: true, emphasized: true)
                    DiagramArrow()
                    DiagramBox(text: result, accent: spec.accent.color)
                }
            }
            VStack(spacing: 2) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(CodepetTheme.accentOrange)
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(CodepetTheme.accentOrange)
                    DiagramChip(text: effect, accent: CodepetTheme.accentOrange)
                }
                roleCaption(sideRole)
            }
        }
    }
}
