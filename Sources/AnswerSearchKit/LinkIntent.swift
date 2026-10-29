import Foundation

public enum LinkIntent {
    private static let pattern =
        #"\b(sources?|citations?|references?|links?|urls?|websites?)\b|\b(show|provide|give|include)\b.*\b(sources?|links?|references?|urls?)\b"#

    /// True when the question explicitly asks for links, sources or citations.
    public static func isLinkRequest(_ question: String) -> Bool {
        question.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
