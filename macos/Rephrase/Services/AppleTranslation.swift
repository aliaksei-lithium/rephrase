import Foundation
import NaturalLanguage
import Translation

/// Which service translates for ⌃⌥Z.
enum TranslateEngine: String, CaseIterable {
    /// Google Translate through the server: needs a password sign-in and the server's Google key.
    case google
    /// Apple's Translation framework, on this Mac: free, offline once a language is downloaded.
    case apple
}

/// Apple's on-device translation. The source language is detected with NaturalLanguage.
enum AppleTranslation {
    enum Plan: Equatable {
        case unknownLanguage
        /// Already in the target language and there is no alternate.
        case unchanged(source: String)
        case translate(source: String, target: String)
    }

    /// Detects the language and applies the "if already in that language" alternate, like the server does.
    static func plan(_ text: String, options: TranslateOptions) -> Plan {
        guard let source = detect(text) else { return .unknownLanguage }
        guard sameLanguage(source, options.target) else { return .translate(source: source, target: options.target) }
        if let alternate = options.alternate, !sameLanguage(alternate, options.target) {
            return .translate(source: source, target: alternate)
        }
        return .unchanged(source: source)
    }

    static func detect(_ text: String) -> String? {
        guard let language = NLLanguageRecognizer.dominantLanguage(for: text), language != .undetermined else { return nil }
        return language.rawValue
    }

    /// "en" and "en-US" match; Chinese also compares the script, so "zh-Hans" and "zh-CN" match but "zh-TW" doesn't.
    static func sameLanguage(_ a: String, _ b: String) -> Bool {
        let x = Locale.Language(identifier: a), y = Locale.Language(identifier: b)
        guard x.languageCode == y.languageCode else { return false }
        if x.languageCode?.identifier == "zh" { return x.maximalIdentifier == y.maximalIdentifier }
        return true
    }

    static func language(_ code: String) -> Locale.Language {
        Locale.Language(identifier: code)
    }

    /// Whether Apple can translate this pair, and whether it is downloaded yet.
    @concurrent nonisolated static func status(from source: String, to target: String) async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: Locale.Language(identifier: source), to: Locale.Language(identifier: target))
    }

    /// Translates with languages that are already downloaded; throws `notInstalled` otherwise.
    /// The session lives only inside this call, off the main actor.
    @concurrent nonisolated static func translate(_ text: String, from source: String, to target: String) async throws -> String {
        let session = TranslationSession(installedSource: Locale.Language(identifier: source), target: Locale.Language(identifier: target))
        return try await session.translate(text).targetText
    }

    /// Languages Apple can translate, with English names like the Google list.
    @concurrent nonisolated static func supportedLanguages() async -> [TranslateLanguage] {
        let english = Locale(identifier: "en")
        var seen = Set<String>()
        return await LanguageAvailability().supportedLanguages
            .map { $0.minimalIdentifier }
            .filter { seen.insert($0).inserted }
            .map { TranslateLanguage(code: $0, name: english.localizedString(forIdentifier: $0) ?? $0) }
            .sorted { $0.name < $1.name }
    }
}
