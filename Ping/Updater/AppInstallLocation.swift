import Foundation

enum AppInstallLocation {
    static func canUseSparkleUpdates(bundleURL: URL = Bundle.main.bundleURL) -> Bool {
        let components = bundleURL.standardizedFileURL.pathComponents

        if components.count >= 3, components[0] == "/", components[1] == "Applications" {
            return true
        }

        if components.count >= 5,
           components[0] == "/",
           components[1] == "Users",
           components[3] == "Applications" {
            return true
        }

        return false
    }
}
