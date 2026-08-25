// codepetTests/RecordComposerTests.swift
#if DEBUG
import SwiftUI
import XCTest
@testable import codepet

/// **The record surface — spec §10, the layout half.** The rules are in
/// `RecordFlowTests`.
///
/// Every number below was measured on this branch, at these widths, by deleting the code
/// it protects and running the test. Nothing is carried across from
/// `VoiceComposerTests` — the two figures that suite marks irreproducible (368, 389) are
/// the reason.
///
/// **Why this suite exists at all, given that `RecordComposer` reuses every decision
/// `VoiceComposer` makes.** What it does *not* reuse is the view body: spec §10 asks for
/// "the same chrome voice mode uses", and two hand-written stacks that could drift are the
/// obvious cost of a sibling view rather than a mode flag. So the load-bearing assertion
/// here is `testRecordAndVoiceModeMeasureTheSameHeight` — the drift this design risks,
/// measured directly, at both surfaces and both privacy branches.
///
/// `ImageRenderer` fires no `.onAppear` and no `.task`, so `preview(phase:partial:…)`
/// seeds its state directly; it also cannot see `.keyboardShortcut`, `.disabled`, or a
/// `DragGesture`, which is why every key and every gate is asserted in `RecordFlowTests`
/// against the pure expression the view reads.
///
/// **No test here starts an audio engine or constructs an `SFSpeechRecognizer`.**
/// `InertSpeechListening` does nothing at all.
@MainActor
final class RecordComposerTests: XCTestCase {

    /// Renders `v` against a proposal and reports what it took.
    ///
    /// **Constrain one axis and measure the free one.** A fixed `.frame(width:height:)`
    /// reports its own arguments, so asserting a rendered size equals the frame is
    /// vacuous. `nil` is unconstrained, which is the only way an intrinsic dimension gets
    /// measured.
    private func size(_ v: some View, w: CGFloat?, h: CGFloat?) -> CGSize {
        let renderer = ImageRenderer(content: v)
        renderer.proposedSize = ProposedViewSize(width: w, height: h)
        return renderer.nsImage?.size ?? .zero
    }

    private static let paneWidth: CGFloat = 520
    /// **The dock's real composer width, which is not 380.** `composerDock`/`composer`
    /// both go through `readingColumn(_:)`, so the composer gets
    /// `ChatColumn.textWidth(forBox:)` — 344 inside a 380pt dock.
    private static let dockWidth = ChatColumn.textWidth(forBox: 380, surface: .dock)
    /// Both, because `ChatSurface.defaultValue` is `.dock`: `cornerRadius` and
    /// `controlDiameter` each have a `.twoMode` branch, and `controlDiameter` (28 vs 26) is
    /// the only surface-dependent thing in the vertical stack.
    private static let surfaces: [ChatSurface] = [.dock, .twoMode]
    private static let phases: [RecordPhase] = [.connecting, .capturing, .held, .failed]

    // MARK: - The parity this design has to buy

    /// **The two surfaces measure the same, which is the assertion that makes
    /// `RecordComposer` a sibling of `VoiceComposer` rather than a divergence from it.**
    ///
    /// Spec §10: record shows "the same chrome voice mode uses". Every *decision* is
    /// genuinely shared — `VoiceChrome.Line`, `VoiceChrome.Control`,
    /// `VoiceWaveform.barHeights`, `VoiceChrome.disclosure`,
    /// `VoiceComposer.transcriptHeight` and `.horizontalPadding` are all reached from
    /// `RecordComposer` rather than restated — but the `VStack`, the paddings and the card
    /// are written twice, and that is the one thing a reader cannot verify by eye across
    /// two files. This measures it: 99pt in the dock and 97pt in two-mode on-device, 122
    /// and 120 off-device, which are `VoiceComposerTests`' own pinned figures for the same
    /// four cases.
    ///
    /// Measured 22 Aug at 520pt and at the dock's real 344pt, all four record phases
    /// against all four voice states, both privacy branches — 32 render pairs.
    ///
    /// **RED, 22 Aug — measured, in failing TESTS.** `.padding(.top, 11)` changed to **14**
    /// in `RecordComposer`: **2 tests fail** (this one and
    /// `testRecordsMeasuredHeightIsPinnedWithAndWithoutTheDisclosure`).
    ///
    /// **A 1pt drift does NOT go red, and that is a stated limit rather than a bug.** Changed
    /// to 12, both tests stay green: the tolerance here is `accuracy: 2`, carried from
    /// `VoiceComposerTests` because sub-pixel rendering makes a tighter figure a flake rather
    /// than a guard. So this catches a padding, slot or card change of 2pt or more, and does
    /// not catch one of a single point. The first version of this note claimed the 1pt case
    /// failed; it was measured and it does not.
    ///
    /// Changing `VoiceComposer.transcriptHeight` instead leaves this green, which is correct:
    /// that constant is *shared*, so it moves both composers together, and this test is about
    /// what is not shared.
    func testRecordAndVoiceModeMeasureTheSameHeight() {
        for surface in Self.surfaces {
            for width in [Self.paneWidth, Self.dockWidth] {
                for onDevice in [true, false] {
                    let voice = size(VoiceComposer.preview(state: .listening, partial: "why",
                                                           onDevice: onDevice,
                                                           surface: surface),
                                     w: width, h: nil)
                    for phase in Self.phases {
                        let record = size(RecordComposer.preview(phase: phase, partial: "why",
                                                                 onDevice: onDevice,
                                                                 surface: surface),
                                          w: width, h: nil)
                        XCTAssertEqual(record.height, voice.height, accuracy: 2,
                                       "\(surface)/\(phase)/onDevice=\(onDevice) at \(width)pt: "
                                       + "record measured \(record.height)pt against voice "
                                       + "mode's \(voice.height) — the two composers have "
                                       + "drifted, and the founder sees one control's box "
                                       + "jump when she uses the other")
                    }
                }
            }
        }
    }

    /// The absolute figures, pinned here as well as compared above — because a change that
    /// moved *both* composers by the same amount would keep the parity test green.
    ///
    /// Measured 22 Aug: **99pt dock / 97pt two-mode on-device, 122 / 120 off-device.** The
    /// 23pt is spec §3's disclosure slot, which renders only when recognition is not
    /// on-device (`VoiceChrome.disclosure`, amended 22 Aug).
    ///
    /// **RED, 22 Aug (measured):** deleting `disclosure` from `RecordComposer`'s `VStack` —
    /// **2 tests fail** (this one, where every off-device render measures 99/97 against the
    /// pinned 122/120, and `testRecordAndVoiceModeMeasureTheSameHeight`). That pair is the
    /// design working as intended: this test says which number moved, and that one says it
    /// moved on only one of the two composers.
    func testRecordsMeasuredHeightIsPinnedWithAndWithoutTheDisclosure() {
        let withoutSlot: [ChatSurface: CGFloat] = [.dock: 99, .twoMode: 97]
        let withSlot: [ChatSurface: CGFloat] = [.dock: 122, .twoMode: 120]
        for surface in Self.surfaces {
            for width in [Self.paneWidth, Self.dockWidth] {
                for phase in Self.phases {
                    for onDevice in [true, false] {
                        let s = size(RecordComposer.preview(phase: phase, partial: "why",
                                                            onDevice: onDevice,
                                                            surface: surface),
                                     w: width, h: nil)
                        let expected = onDevice ? withoutSlot[surface]! : withSlot[surface]!
                        XCTAssertEqual(s.height, expected, accuracy: 2,
                                       "\(surface)/\(phase)/onDevice=\(onDevice) at \(width)pt "
                                       + "measured \(s.height)pt against \(expected)")
                    }
                }
            }
        }
    }

    // MARK: - Layout

    /// The composer is sized by the reading column, so a box that shrank to its content
    /// would sit narrow in the middle of a column the transcript above it fills — visibly
    /// not the same object as the composer it replaced.
    ///
    /// **A property guard, not a modifier guard**, exactly as `VoiceComposer`'s is: the
    /// width fill is implemented twice, by the two `maxWidth: .infinity` frames and
    /// independently by the `Spacer` in `bottomRow`. It catches "record stopped spreading"
    /// and does not catch "one of the two mechanisms was deleted".
    func testRecordSpreadsToTheWidthItIsOffered() {
        let s = size(RecordComposer.preview(phase: .capturing, partial: "why"),
                     w: Self.paneWidth, h: nil)
        XCTAssertEqual(s.width, Self.paneWidth, accuracy: 2,
                       "record took \(s.width)pt of the \(Self.paneWidth) it was offered")
    }

    /// **The composer grows in place; it does not become a takeover.** Spec §2 decision 5,
    /// which record inherits: the chat stays visible, which is the point of the surface.
    /// Offered 700pt it must take its own ~99 and leave the rest.
    ///
    /// RED, 22 Aug (measured): `.frame(maxHeight: .infinity)` added to `RecordComposer`'s
    /// `body` — **1 test fails**, this one, reporting 700 in all eight cases. Notably the two
    /// height tests stay green, because they propose `h: nil`: an unconstrained proposal never
    /// reaches the `maxHeight`. That is why this test is separate from them.
    func testRecordExpandsWithoutTakingOverThePane() {
        for surface in Self.surfaces {
            for phase in Self.phases {
                let s = size(RecordComposer.preview(phase: phase, partial: "why",
                                                    surface: surface),
                             w: Self.paneWidth, h: 700)
                XCTAssertLessThan(s.height, 200,
                                  "\(surface)/\(phase) took \(s.height)pt of the 700 offered — "
                                  + "the conversation is supposed to stay visible")
            }
        }
    }

    /// Every phase lays out at the dock's real width, in both privacy branches. The
    /// off-device render is the one where §3's escalated sentence has to fit.
    func testEveryPhaseRenders() {
        for surface in Self.surfaces {
            for onDevice in [true, false] {
                for phase in Self.phases {
                    let s = size(RecordComposer.preview(phase: phase, partial: "test",
                                                        onDevice: onDevice, surface: surface),
                                 w: Self.dockWidth, h: nil)
                    XCTAssertGreaterThan(s.height, 60,
                                         "\(surface)/\(phase)/onDevice=\(onDevice) did not lay out")
                }
            }
        }
    }

    /// A transcript long enough to wrap must not change the composer's height — the slot is
    /// a fixed 40pt precisely so that ✕ and ✓ do not move out from under her pointer as she
    /// talks.
    ///
    /// RED, 22 Aug (measured): deleting `.frame(height: VoiceComposer.transcriptHeight, …)`
    /// from `transcriptSlot` — **3 tests fail** (this one,
    /// `testRecordsMeasuredHeightIsPinnedWithAndWithoutTheDisclosure`, and
    /// `testRecordAndVoiceModeMeasureTheSameHeight`).
    func testAWrappingTranscriptDoesNotMoveTheControls() {
        let long = "why is onboarding losing people at step three and what should I do "
            + "about the pricing page before the beta freeze on Friday"
        for surface in Self.surfaces {
            for width in [Self.paneWidth, Self.dockWidth] {
                let short = size(RecordComposer.preview(phase: .capturing, partial: "why",
                                                        surface: surface), w: width, h: nil)
                let wrapped = size(RecordComposer.preview(phase: .capturing, partial: long,
                                                          surface: surface), w: width, h: nil)
                XCTAssertEqual(wrapped.height, short.height, accuracy: 1,
                               "\(surface) at \(width)pt: the box grew from \(short.height) to "
                               + "\(wrapped.height) as she talked")
            }
        }
    }

    // MARK: - The two text slots

    /// **Spec §3's disclosure fits two lines on record's surface too, and it is the same
    /// string.**
    ///
    /// Record reaches `VoiceChrome.disclosure` rather than reimplementing it, so the words
    /// cannot drift — but the *width* it lays out in is `RecordComposer`'s own padding, and
    /// the default `.tail` truncation would cut §3's sentence mid-phrase with nothing on
    /// screen saying so. That is the footnote §3 forbids, arrived at by layout.
    ///
    /// Measured against the width the founder gets, not a round number. RED: drop the
    /// limit to 1 here — the dock measures 13pt against 25pt needed.
    func testTheOffDeviceDisclosureFitsTwoLinesOnRecordsSurface() throws {
        for lang in [AppLanguage.en, .vi] {
            let line = try XCTUnwrap(VoiceChrome.disclosure(onDevice: false, failure: nil, lang))
            let text = Text(line).font(CodepetTheme.inter(CodepetType.footnote))
            let inner = Self.dockWidth - VoiceComposer.horizontalPadding * 2
            let needed = size(text.lineLimit(nil), w: inner, h: nil)
            let given = size(text.lineLimit(2), w: inner, h: nil)
            XCTAssertEqual(given.height, needed.height, accuracy: 1,
                           "\(lang): the off-device disclosure needs \(needed.height)pt at "
                           + "\(inner)pt wide and .lineLimit(2) gives it \(given.height) — "
                           + "spec §3's sentence is being truncated: \(line)")
        }
    }

    /// **`.held` with nothing heard has to fit the slot, and its length is load-bearing for
    /// the same reason the watchdog's remedy is.**
    ///
    /// This lands in the transcript slot, which is `.lineLimit(2)` at `CodepetType.body`
    /// with `truncationMode(.head)` — so a sentence needing three lines loses its
    /// *beginning* silently — and the slot is a fixed 40pt, so three lines do not fit the
    /// frame either. Measured 22 Aug at the dock's real 316pt inner width against the
    /// watchdog's own two-line string, which `VoiceComposerTests` has already pinned at
    /// 34pt with ~6 characters of headroom.
    ///
    /// RED: replace `nothingHeardText` with the watchdog's diagnosis plus its own text
    /// appended — three lines, 51pt, and both assertions fail.
    func testTheNothingHeardLineFitsTheComposersTwoLines() {
        let inner = Self.dockWidth - VoiceComposer.horizontalPadding * 2
        let twoLines = size(Text("x\nx").font(CodepetTheme.inter(CodepetType.body)),
                            w: inner, h: nil).height
        for lang in [AppLanguage.en, .vi] {
            let line = RecordChrome.nothingHeardText(lang)
            let needed = size(Text(line).font(CodepetTheme.inter(CodepetType.body))
                                .lineLimit(nil), w: inner, h: nil)
            XCTAssertLessThanOrEqual(needed.height, twoLines + 1,
                                     "\(lang): \"\(line)\" needs \(needed.height)pt at "
                                     + "\(inner)pt wide against the \(twoLines)pt two lines "
                                     + "give it — `.head` truncation would eat its start")
            XCTAssertLessThanOrEqual(needed.height, VoiceComposer.transcriptHeight,
                                     "\(lang): it does not fit the 40pt slot either")
        }
    }
}
#endif
