/// Display names for the API's option ids, matching the web app.
enum Labels {
    static func mode(_ id: String) -> String {
        ["simple": "Fix", "default": "Edit", "rewrite": "Rewrite"][id] ?? fallback(id)
    }

    static func style(_ id: String) -> String {
        id == "keep" ? "Keep mine" : fallback(id)
    }

    static func tone(_ id: String) -> String {
        id == "keep" ? "Keep mine" : fallback(id)
    }

    static func language(_ id: String) -> String {
        ["auto": "Auto", "en": "English", "de": "Deutsch"][id] ?? id.uppercased()
    }

    private static func fallback(_ id: String) -> String {
        id.prefix(1).uppercased() + id.dropFirst()
    }
}
