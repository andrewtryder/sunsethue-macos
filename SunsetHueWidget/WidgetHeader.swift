import SwiftUI

struct WidgetHeader: View {
    let locationName: String
    let updatedText: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(locationName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            if let updatedText {
                Text(updatedText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct UpdatedLabel: View {
    let entry: SunsetHueEntry

    var body: some View {
        if let text = WidgetUpdatedCopy.text(for: entry) {
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

enum WidgetUpdatedCopy {
    /// Compact chrome for headers / footers. Prefer entry.statusMessage when already compact.
    static func text(for entry: SunsetHueEntry) -> String? {
        if let status = entry.statusMessage, !status.isEmpty {
            return status
        }
        guard let fetchedAt = entry.bundle?.fetchedAt else { return nil }
        return compactUpdated(from: fetchedAt, now: entry.date)
    }

    static func compactUpdated(from fetchedAt: Date, now: Date = Date()) -> String {
        let ageSeconds = max(0, now.timeIntervalSince(fetchedAt))
        if ageSeconds < 3600 {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return "Updated \(formatter.string(from: fetchedAt))"
        }
        let hours = max(1, Int(ageSeconds / 3600))
        return "Updated \(hours)h ago"
    }
}
