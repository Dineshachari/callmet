import Foundation

enum MeetingLinkParser {
    static func extractMeetingURL(from text: String) -> URL? {
        let patterns: [(String, Bool)] = [
            (#"https?://(?:www\.)?meet\.google\.com/[A-Za-z0-9-]+"#, false),
            (#"https?://(?:[\w-]+\.)?zoom\.us/j/\d+(?:\?[^\s<>\"]*)?"#, false),
            (#"https?://(?:[\w-]+\.)?teams\.microsoft\.com/l/meetup-join/[^\s<>\"]+"#, false),
            (#"(?:www\.)?meet\.google\.com/[A-Za-z0-9-]+"#, true),
            (#"(?:[\w-]+\.)?zoom\.us/j/\d+(?:\?[^\s<>\"]*)?"#, true),
            (#"(?:[\w-]+\.)?teams\.microsoft\.com/l/meetup-join/[^\s<>\"]+"#, true)
        ]

        for (pattern, needsScheme) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range),
                  let matchRange = Range(match.range, in: text) else {
                continue
            }

            var candidate = String(text[matchRange])
            if needsScheme {
                candidate = "https://" + candidate
            }

            if let url = URL(string: candidate) {
                return url
            }
        }

        return nil
    }
}
