import Foundation
import SunsetHueCore

struct UpdateCheckResult: Sendable {
    let currentVersion: String
    let latestVersion: String?
    let releaseURL: URL
    let updateAvailable: Bool
}

struct UpdateChecker: Sendable {
    private let session: URLSession
    private let currentVersion: String
    private let latestURL: URL
    private let releasesPageURL: URL

    init(
        session: URLSession = .shared,
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? SunsetHueConstants.marketingVersion,
        latestURL: URL = SunsetHueConstants.githubReleasesLatestURL,
        releasesPageURL: URL = SunsetHueConstants.githubReleasesPageURL
    ) {
        self.session = session
        self.currentVersion = currentVersion
        self.latestURL = latestURL
        self.releasesPageURL = releasesPageURL
    }

    func checkForUpdates() async throws -> UpdateCheckResult {
        var request = URLRequest(url: latestURL)
        request.setValue(SunsetHueConstants.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SunsetHueError.serviceUnavailable
        }
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let tag = (payload?["tag_name"] as? String)?.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        let htmlURL = (payload?["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPageURL
        let latest = tag
        let available: Bool
        if let latest {
            available = compareVersions(latest, currentVersion) == .orderedDescending
        } else {
            available = false
        }
        return UpdateCheckResult(
            currentVersion: currentVersion,
            latestVersion: latest,
            releaseURL: htmlURL,
            updateAvailable: available
        )
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: .numeric)
    }
}
