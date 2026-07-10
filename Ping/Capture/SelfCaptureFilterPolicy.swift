enum SelfCaptureFilterPolicy {
    static func matchingApplications<Application>(
        in applications: [Application],
        bundleIdentifier: String?,
        processID: Int32,
        bundleIdentifierOf: (Application) -> String?,
        processIDOf: (Application) -> Int32
    ) -> [Application] {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            let bundleMatches = applications.filter {
                bundleIdentifierOf($0) == bundleIdentifier
            }
            if !bundleMatches.isEmpty {
                return bundleMatches
            }
        }

        return applications.filter { processIDOf($0) == processID }
    }
}
