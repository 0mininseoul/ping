import XCTest
@testable import Ping

final class AppcastUpdateOfferParserTests: XCTestCase {
    func testParsesLatestUpdateOfferWhenCurrentBuildIsOlder() {
        let xml = """
        <?xml version="1.0"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item>
              <title>0.3.28</title>
              <sparkle:version>38</sparkle:version>
              <sparkle:shortVersionString>0.3.28</sparkle:shortVersionString>
              <enclosure url="https://0minping.vercel.app/downloads/Ping-v0.3.28.dmg" length="7222917" type="application/octet-stream"/>
            </item>
            <item>
              <title>0.3.25</title>
              <sparkle:version>35</sparkle:version>
              <sparkle:shortVersionString>0.3.25</sparkle:shortVersionString>
              <enclosure url="https://0minping.vercel.app/downloads/Ping-v0.3.25.dmg" length="7150046" type="application/octet-stream"/>
            </item>
          </channel>
        </rss>
        """

        let offer = AppcastUpdateOfferParser.latestOffer(in: Data(xml.utf8), currentBuild: "35")

        XCTAssertEqual(offer?.displayVersion, "0.3.28")
        XCTAssertEqual(offer?.build, 38)
        XCTAssertEqual(offer?.downloadURL.absoluteString, "https://0minping.vercel.app/downloads/Ping-v0.3.28.dmg")
    }

    func testReturnsNilWhenCurrentBuildIsAlreadyLatest() {
        let xml = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item>
              <title>0.3.28</title>
              <sparkle:version>38</sparkle:version>
              <sparkle:shortVersionString>0.3.28</sparkle:shortVersionString>
              <enclosure url="https://0minping.vercel.app/downloads/Ping-v0.3.28.dmg" length="7222917" type="application/octet-stream"/>
            </item>
          </channel>
        </rss>
        """

        XCTAssertNil(AppcastUpdateOfferParser.latestOffer(in: Data(xml.utf8), currentBuild: "38"))
    }
}
