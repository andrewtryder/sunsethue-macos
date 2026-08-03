import SwiftUI
import SunsetHueCore

struct MediumWidgetView: View {
    let entry: SunsetHueEntry

    var body: some View {
        if let content = WidgetContentResolver.resolve(entry: entry, preferSingle: false) {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(
                    locationName: content.locationName,
                    updatedText: WidgetUpdatedCopy.text(for: entry)
                )

                HStack(alignment: .top, spacing: 12) {
                    if content.events.isEmpty {
                        EmptyView()
                    } else if content.events.count == 1 {
                        MediumEventColumn(event: content.events[0], showDayLabel: content.isUpcoming)
                    } else {
                        MediumEventColumn(event: content.events[0], showDayLabel: content.isUpcoming)
                        Divider()
                        MediumEventColumn(event: content.events[1], showDayLabel: content.isUpcoming)
                    }
                }

                if let hint = content.hint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                } else if let tomorrow = content.tomorrowSummary {
                    Text(tomorrow)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(content.accessibilityLabel)
        } else {
            OnboardingWidgetView(message: entry.statusMessage ?? "No data")
        }
    }
}

struct MediumEventColumn: View {
    let event: WidgetEventContent
    var showDayLabel: Bool = false

    var body: some View {
        let style = WidgetQualityStyle.resolve(quality: event.quality, qualityText: event.qualityText)

        VStack(alignment: .leading, spacing: 3) {
            Label {
                Text(showDayLabel ? "\(event.eventType.displayName) · \(event.dayLabel)" : event.eventType.displayName)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: event.eventType.symbolName)
                    .foregroundStyle(event.eventType.iconColor)
            }
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)

            Text(style.percentage)
                .font(.title2.weight(.bold))
                .foregroundStyle(style.tint)
                .minimumScaleFactor(0.7)

            QualityBadge(style: style)

            Text(event.timeLabel)
                .font(.caption.weight(.medium).monospacedDigit())

            if let golden = event.goldenHourLabel {
                Text(golden)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel(fullGoldenAccessibility(golden))
            }

            if let blue = event.blueHourLabel {
                Text(blue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel(fullBlueAccessibility(blue))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fullGoldenAccessibility(_ compact: String) -> String {
        let range = compact.replacingOccurrences(of: "Gold ", with: "")
        let parts = range.split(separator: "–", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return "Golden hour from \(parts[0]) to \(parts[1])"
        }
        return "Golden hour \(range)"
    }

    private func fullBlueAccessibility(_ compact: String) -> String {
        let range = compact.replacingOccurrences(of: "Blue ", with: "")
        let parts = range.split(separator: "–", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return "Blue hour from \(parts[0]) to \(parts[1])"
        }
        return "Blue hour \(range)"
    }
}
