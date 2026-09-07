import Foundation

/// The line the transcript shows under an authored fallback — pure + localized.
///
/// **Why this exists.** `CompanyStore.postLiveLine` posts the caller's authored `fallback`
/// whenever the live reply is nil or empty, and until now it did so silently: the transcript
/// read exactly like a working live run. On 7 Sep a demo launched with `-CODEPET_LIVE_AI YES`
/// served three authored lines in a row — `.summary`, `.prompt` and `.setup`, each of which
/// HAS a live instruction — because the deployed `companyChat` was getting
/// `401 authentication_error: API key is invalid` from Anthropic on every call. Nothing on
/// screen said so, and the only existing signal (`MockFlowPlayer`'s "That reply didn't come
/// back" caption) fires on a TIMEOUT, never on a nil or empty return.
///
/// Wording deliberately echoes that caption, so the two read as the same event.
enum LiveFallbackNotice {
    static func text(_ language: AppLanguage) -> String {
        language == .vi
            ? "Câu có sẵn — phản hồi trực tiếp không về."
            : "Scripted — that reply didn't come back."
    }
}
