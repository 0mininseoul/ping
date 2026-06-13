import Foundation

struct DetectedLink: Equatable, Hashable {
    let url: URL
    let range: NSRange
}

struct LinkPreviewMetadata: Equatable, Hashable {
    let url: URL
    let title: String?
    let summary: String?
    let imageURL: URL?
    let siteName: String?

    static func fallback(url: URL) -> LinkPreviewMetadata {
        LinkPreviewMetadata(
            url: url,
            title: nil,
            summary: nil,
            imageURL: nil,
            siteName: nil
        )
    }

    var displayTitle: String {
        title ?? siteName ?? LinkPreviewDetector.displayHost(for: url)
    }
}

enum LinkPreviewDetector {
    private static let urlPattern = #"(https?://[^\s<>"']+|www\.[^\s<>"']+)"#
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,!?;:)]}")

    static func firstURL(in text: String) -> URL? {
        matches(in: text).first?.url
    }

    static func matches(in text: String) -> [DetectedLink] {
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
            return DetectedLink(url: url, range: NSRange(location: result.range.location, length: (raw as NSString).length))
        }
    }

    static func displayHost(for url: URL) -> String {
        let host = url.host(percentEncoded: false) ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
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
}

enum OpenGraphParser {
    static func parse(html: String, pageURL: URL) -> LinkPreviewMetadata {
        let title = metaContent(in: html, keys: ["og:title", "twitter:title"])
            ?? titleContent(in: html)
        let summary = metaContent(in: html, keys: ["og:description", "twitter:description", "description"])
        let siteName = metaContent(in: html, keys: ["og:site_name"])
        let image = metaContent(in: html, keys: ["og:image", "og:image:url", "twitter:image"])
        let imageURL = image.flatMap { URL(string: $0, relativeTo: pageURL)?.absoluteURL }

        return LinkPreviewMetadata(
            url: pageURL,
            title: title,
            summary: summary,
            imageURL: imageURL,
            siteName: siteName
        )
    }

    private static func metaContent(in html: String, keys: Set<String>) -> String? {
        guard let tagRegex = try? NSRegularExpression(pattern: #"<meta\b[^>]*>"#, options: [.caseInsensitive]) else {
            return nil
        }

        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
        for tagMatch in tagRegex.matches(in: html, range: fullRange) {
            let tag = (html as NSString).substring(with: tagMatch.range)
            let attrs = attributes(in: tag)
            let key = (attrs["property"] ?? attrs["name"])?.lowercased()
            if let key, keys.contains(key), let content = attrs["content"], !content.isEmpty {
                return htmlDecoded(content)
            }
        }
        return nil
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

actor LinkPreviewCache {
    static let shared = LinkPreviewCache()

    private var metadataByURL: [URL: LinkPreviewMetadata] = [:]

    func metadata(for url: URL) async -> LinkPreviewMetadata {
        if let cached = metadataByURL[url] {
            return cached
        }

        let metadata: LinkPreviewMetadata
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .ascii)
                ?? ""
            metadata = OpenGraphParser.parse(html: html, pageURL: url)
        } catch {
            metadata = .fallback(url: url)
        }

        metadataByURL[url] = metadata
        return metadata
    }
}
