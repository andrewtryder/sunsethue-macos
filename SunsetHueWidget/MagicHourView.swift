import SwiftUI

struct MagicHourView: View {
    let goldenHourLabel: String?
    let blueHourLabel: String?
    let cloudCoverLabel: String?
    var preferred: MagicHourPreference = .both
    var showCloud: Bool = false

    enum MagicHourPreference {
        case both
        case preferGolden
        case preferBlue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if showCloud, let cloudCoverLabel {
                Label(cloudCoverLabel, systemImage: "cloud.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel(accessibilityCloud(cloudCoverLabel))
            }

            ForEach(Array(selectedHourLines.enumerated()), id: \.offset) { _, line in
                if line.systemImage != nil {
                    Label(line.text, systemImage: line.systemImage!)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityLabel(line.accessibility)
                } else {
                    Text(line.text)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityLabel(line.accessibility)
                }
            }
        }
    }

    private struct HourLine {
        let text: String
        let accessibility: String
        let systemImage: String?
    }

    private var selectedHourLines: [HourLine] {
        var lines: [HourLine] = []
        let golden = goldenHourLabel.map {
            HourLine(text: $0, accessibility: accessibilityGolden($0), systemImage: "camera.filters")
        }
        let blue = blueHourLabel.map {
            HourLine(text: $0, accessibility: accessibilityBlue($0), systemImage: nil)
        }

        switch preferred {
        case .both:
            if let golden { lines.append(golden) }
            if let blue { lines.append(blue) }
        case .preferGolden:
            if let golden {
                lines.append(golden)
            } else if let blue {
                lines.append(blue)
            }
        case .preferBlue:
            if let blue {
                lines.append(blue)
            } else if let golden {
                lines.append(golden)
            }
        }
        return lines
    }

    private func accessibilityGolden(_ compact: String) -> String {
        // compact: "Gold 05:16–05:51"
        let range = compact.replacingOccurrences(of: "Gold ", with: "")
        let parts = range.split(separator: "–", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return "Golden hour from \(parts[0]) to \(parts[1])"
        }
        return "Golden hour \(range)"
    }

    private func accessibilityBlue(_ compact: String) -> String {
        let range = compact.replacingOccurrences(of: "Blue ", with: "")
        let parts = range.split(separator: "–", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return "Blue hour from \(parts[0]) to \(parts[1])"
        }
        return "Blue hour \(range)"
    }

    private func accessibilityCloud(_ compact: String) -> String {
        // "Cloud 23%"
        let value = compact.replacingOccurrences(of: "Cloud ", with: "")
            .replacingOccurrences(of: "%", with: " percent")
        return "Cloud cover \(value)"
    }
}
