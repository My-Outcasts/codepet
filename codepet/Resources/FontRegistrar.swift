import Foundation
import CoreText
import os
#if canImport(AppKit)
import AppKit
#endif

/// Registers any .ttf/.otf fonts bundled in the app's Resources at app launch
/// so they're usable from `Font.custom(...)` without an Info.plist entry.
///
/// Call `FontRegistrar.registerBundledFonts()` once early in `CodePetApp.init`.
enum FontRegistrar {

    private static let logger = Logger(subsystem: "app.murror.codepet", category: "FontRegistrar")

    /// Triggered on first access (e.g. when `CodepetTheme.pixel(_:)` is
    /// first called). Ensures fonts are available even in SwiftUI Previews,
    /// which bypass `App.init()`.
    static let autoRegister: Void = {
        registerBundledFonts()
    }()

    /// File basename → PostScript name. The PostScript name is what
    /// `Font.custom(_:size:)` resolves against — it lives inside the font's
    /// `name` table and may not match the file name (e.g. Google's optical
    /// Inter ships as `Inter_18pt-Regular.ttf` but its PS name is
    /// `Inter18pt-Regular`).
    private static let bundled: [(file: String, postScript: String)] = [
        ("Minecraft",              "Minecraft"),
        // Google Sans Flex — the app's sans (matches the web). Inter kept as fallback.
        ("GoogleSansFlex-Regular", "GoogleSansFlex-Regular"),
        ("GoogleSansFlex-Medium",  "GoogleSansFlex-Medium"),
        ("GoogleSansFlex-SemiBold","GoogleSansFlex-SemiBold"),
        ("GoogleSansFlex-Bold",    "GoogleSansFlex-Bold"),
        ("Inter_18pt-Regular",     "Inter18pt-Regular"),
        ("Inter_18pt-Medium",      "Inter18pt-Medium"),
        ("Inter_18pt-SemiBold",    "Inter18pt-SemiBold"),
        ("Inter_18pt-Bold",        "Inter18pt-Bold"),
    ]

    /// Idempotent: safe to call multiple times. The font URLs are looked up
    /// in `Bundle.main`, so any .ttf/.otf placed under `codepet/Resources/`
    /// will be picked up by the synchronized-folder build.
    static func registerBundledFonts() {
        let extensions = ["ttf", "otf"]

        for entry in bundled {
            var registered = false
            for ext in extensions {
                guard let url = Bundle.main.url(forResource: entry.file, withExtension: ext) else {
                    continue
                }
                var error: Unmanaged<CFError>?
                if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                    logger.info("Registered bundled font: \(entry.file).\(ext) at \(url.path)")
                    print("[FontRegistrar] ✓ registered \(entry.file).\(ext)")
                } else {
                    let cf = error?.takeRetainedValue()
                    let code = (cf as Error?).map { ($0 as NSError).code } ?? 0
                    // 105 = "already registered" in CTFontManagerErrorDomain. Harmless.
                    if code == 105 {
                        logger.debug("Font already registered: \(entry.file)")
                        print("[FontRegistrar] (already registered: \(entry.file))")
                    } else {
                        logger.error("Failed to register font \(entry.file).\(ext): \(String(describing: cf))")
                        print("[FontRegistrar] ✗ failed to register \(entry.file).\(ext): \(String(describing: cf))")
                    }
                }
                registered = true
                break
            }
            if !registered {
                logger.error("Bundled font not found in Bundle.main: \(entry.file)")
                print("[FontRegistrar] ✗ \(entry.file).ttf not in Bundle.main")
            }
        }

        // Diagnostic: confirm each PostScript name is now resolvable.
        for entry in bundled {
            #if canImport(AppKit)
            if NSFont(name: entry.postScript, size: 13) != nil {
                print("[FontRegistrar] NSFont(name: \"\(entry.postScript)\") resolves ✓")
            } else {
                print("[FontRegistrar] NSFont(name: \"\(entry.postScript)\") returned nil ✗")
            }
            #endif
        }
    }
}
