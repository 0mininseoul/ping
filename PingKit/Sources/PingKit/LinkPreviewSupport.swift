import Foundation

public struct PingDetectedLink: Equatable, Hashable, Sendable {
    public let url: URL
    public let range: NSRange
}

public struct PingLinkPreviewMetadata: Equatable, Hashable, Sendable {
    public let url: URL
    public let title: String?
    public let summary: String?
    public let imageURL: URL?
    public let siteName: String?

    public static func fallback(url: URL) -> PingLinkPreviewMetadata {
        PingLinkPreviewMetadata(
            url: url,
            title: nil,
            summary: nil,
            imageURL: PingLinkPreviewDetector.youtubeThumbnailURL(for: url),
            siteName: PingLinkPreviewDetector.fallbackSiteName(for: url)
        )
    }

    public var displayTitle: String {
        title ?? siteName ?? PingLinkPreviewDetector.displayHost(for: url)
    }
}

public enum PingLinkPreviewDetector {
    private static let urlPattern = #"(https?://[^\s<>"']+|www\.[^\s<>"']+)"#
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,!?;:)]}")

    public static func firstURL(in text: String) -> URL? {
        matches(in: text).first?.url
    }

    public static func matches(in text: String) -> [PingDetectedLink] {
        let detectorMatches = dataDetectorMatches(in: text)
        if !detectorMatches.isEmpty {
            return detectorMatches
        }

        return regexMatches(in: text)
    }

    private static func dataDetectorMatches(in text: String) -> [PingDetectedLink] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        return detector.matches(in: text, range: fullRange).compactMap { result in
            guard result.range.location != NSNotFound else { return nil }
            var raw = nsText.substring(with: result.range)
            raw = raw.trimmingCharacters(in: trailingPunctuation)
            guard let url = normalizedURL(from: raw) ?? result.url else { return nil }
            return PingDetectedLink(url: url, range: NSRange(location: result.range.location, length: (raw as NSString).length))
        }
    }

    private static func regexMatches(in text: String) -> [PingDetectedLink] {
        guard let regex = try? NSRegularExpression(pattern: urlPattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: fullRange).compactMap { result in
            guard result.range.location != NSNotFound else { return nil }
            var raw = nsText.substring(with: result.range)
            raw = raw.trimmingCharacters(in: trailingPunctuation)
            guard let url = normalizedURL(from: raw) else { return nil }
            return PingDetectedLink(url: url, range: NSRange(location: result.range.location, length: (raw as NSString).length))
        }
    }

    public static func displayHost(for url: URL) -> String {
        let host = url.host(percentEncoded: false) ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    public static func fallbackSiteName(for url: URL) -> String? {
        isYouTubeURL(url) ? "YouTube" : nil
    }

    public static func youtubeThumbnailURL(for url: URL) -> URL? {
        guard let videoID = youtubeVideoID(for: url) else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
    }

    private static func normalizedURL(from raw: String) -> URL? {
        let value = raw.hasPrefix("www.") ? "https://\(raw)" : raw
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil else {
            return nil
        }
        return components.url
    }

    private static func youtubeVideoID(for url: URL) -> String? {
        guard isYouTubeURL(url) else { return nil }

        let host = normalizedHost(for: url)
        let pathComponents = url.path.split(separator: "/").map(String.init)

        if host == "youtu.be" {
            return sanitizedYouTubeVideoID(pathComponents.first)
        }

        if url.path == "/watch",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let videoID = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return sanitizedYouTubeVideoID(videoID)
        }

        guard pathComponents.count >= 2 else { return nil }
        switch pathComponents[0].lowercased() {
        case "embed", "live", "shorts", "v":
            return sanitizedYouTubeVideoID(pathComponents[1])
        default:
            return nil
        }
    }

    private static func isYouTubeURL(_ url: URL) -> Bool {
        let host = normalizedHost(for: url)
        return host == "youtu.be"
            || host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host == "youtube-nocookie.com"
            || host.hasSuffix(".youtube-nocookie.com")
    }

    private static func normalizedHost(for url: URL) -> String {
        let host = (url.host(percentEncoded: false) ?? "").lowercased()
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func sanitizedYouTubeVideoID(_ rawValue: String?) -> String? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        guard rawValue.rangeOfCharacter(from: allowedCharacters.inverted) == nil else { return nil }
        return rawValue
    }
}

public enum PingOpenGraphParser {
    public static func parse(html: String, pageURL: URL) -> PingLinkPreviewMetadata {
        let title = metaContent(in: html, keys: ["og:title", "twitter:title"])
            ?? titleContent(in: html)
        let summary = metaContent(in: html, keys: ["og:description", "twitter:description", "description"])
        let siteName = metaContent(in: html, keys: ["og:site_name"])
            ?? PingLinkPreviewDetector.fallbackSiteName(for: pageURL)
        let image = metaContent(in: html, keys: ["og:image:secure_url", "og:image", "og:image:url", "twitter:image", "twitter:image:src"])
        let imageURL = image.flatMap { URL(string: $0, relativeTo: pageURL)?.absoluteURL }
            ?? PingLinkPreviewDetector.youtubeThumbnailURL(for: pageURL)

        return PingLinkPreviewMetadata(
            url: pageURL,
            title: title,
            summary: summary,
            imageURL: imageURL,
            siteName: siteName
        )
    }

    private static func metaContent(in html: String, keys: [String]) -> String? {
        guard let tagRegex = try? NSRegularExpression(pattern: #"<meta\b[^>]*>"#, options: [.caseInsensitive]) else {
            return nil
        }

        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
        var contentByKey: [String: String] = [:]
        for tagMatch in tagRegex.matches(in: html, range: fullRange) {
            let tag = (html as NSString).substring(with: tagMatch.range)
            let attrs = attributes(in: tag)
            let key = (attrs["property"] ?? attrs["name"])?.lowercased()
            if let key, keys.contains(key), contentByKey[key] == nil, let content = attrs["content"], !content.isEmpty {
                contentByKey[key] = htmlDecoded(content)
            }
        }
        return keys.compactMap { contentByKey[$0] }.first
    }

    private static func attributes(in tag: String) -> [String: String] {
        guard let attrRegex = try? NSRegularExpression(
            pattern: #"([A-Za-z_:][A-Za-z0-9_:\.-]*)\s*=\s*(['"])(.*?)\2"#,
            options: [.caseInsensitive]
        ) else {
            return [:]
        }

        let nsTag = tag as NSString
        let fullRange = NSRange(location: 0, length: nsTag.length)
        var attrs: [String: String] = [:]
        for match in attrRegex.matches(in: tag, range: fullRange) where match.numberOfRanges >= 4 {
            let name = nsTag.substring(with: match.range(at: 1)).lowercased()
            let value = nsTag.substring(with: match.range(at: 3))
            attrs[name] = htmlDecoded(value)
        }
        return attrs
    }

    private static func titleContent(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<title\b[^>]*>(.*?)</title>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range), match.numberOfRanges > 1 else {
            return nil
        }
        let value = (html as NSString).substring(with: match.range(at: 1))
        return htmlDecoded(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func htmlDecoded(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

public actor PingLinkPreviewCache {
    public static let shared = PingLinkPreviewCache()

    private var metadataByURL: [URL: PingLinkPreviewMetadata] = [:]

    public func metadata(for url: URL) async -> PingLinkPreviewMetadata {
        if let cached = metadataByURL[url] {
            return cached
        }

        let metadata: PingLinkPreviewMetadata
        do {
            var request = URLRequest(url: url)
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("Ping LinkPreview", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .ascii)
                ?? ""
            metadata = PingOpenGraphParser.parse(html: html, pageURL: response.url ?? url)
        } catch {
            NSLog("Link preview fetch failed for \(url.absoluteString): \(error.localizedDescription)")
            metadata = .fallback(url: url)
        }

        metadataByURL[url] = metadata
        return metadata
    }
}
