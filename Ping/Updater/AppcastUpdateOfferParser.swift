import Foundation

struct AppcastUpdateOffer: Equatable {
    let displayVersion: String
    let build: Int
    let downloadURL: URL
}

enum AppcastUpdateOfferParser {
    static func latestOffer(in data: Data, currentBuild: String) -> AppcastUpdateOffer? {
        let delegate = AppcastParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else { return nil }
        let currentBuildNumber = Int(currentBuild) ?? -1

        return delegate.offers
            .filter { $0.build > currentBuildNumber }
            .max { $0.build < $1.build }
    }
}

private struct AppcastItem {
    var displayVersion = ""
    var build: Int?
    var downloadURL: URL?
}

private final class AppcastParserDelegate: NSObject, XMLParserDelegate {
    private var currentItem: AppcastItem?
    private var currentElement = ""
    private var text = ""

    private(set) var offers: [AppcastUpdateOffer] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if matches(elementName, "item") {
            currentItem = AppcastItem()
            return
        }

        guard currentItem != nil else { return }
        currentElement = elementName
        text = ""

        if matches(elementName, "enclosure"),
           currentItem?.downloadURL == nil,
           let urlString = attributeDict["url"],
           let url = URL(string: urlString) {
            currentItem?.downloadURL = url
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentItem != nil else { return }
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard var item = currentItem else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if matches(elementName, "version") {
            item.build = Int(value)
            currentItem = item
        } else if matches(elementName, "shortVersionString") {
            item.displayVersion = value
            currentItem = item
        } else if matches(elementName, "title"), item.displayVersion.isEmpty {
            item.displayVersion = value
            currentItem = item
        } else if matches(elementName, "item") {
            appendOffer(item)
            currentItem = nil
        }

        currentElement = ""
        text = ""
    }

    private func appendOffer(_ item: AppcastItem) {
        guard let build = item.build,
              let downloadURL = item.downloadURL,
              !item.displayVersion.isEmpty else {
            return
        }

        offers.append(AppcastUpdateOffer(
            displayVersion: item.displayVersion,
            build: build,
            downloadURL: downloadURL
        ))
    }

    private func matches(_ elementName: String, _ suffix: String) -> Bool {
        elementName == suffix || elementName.hasSuffix(":\(suffix)")
    }
}
