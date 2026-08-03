import SwiftUI
import SunsetHueCore

struct LargeWidgetView: View {
    let entry: SunsetHueEntry

    var body: some View {
        if let content = WidgetContentResolver.resolve(entry: entry, preferSingle: false),
           !content.daySections.isEmpty {
            ViewThatFits(in: .vertical) {
                LargeForecastLayout(
                    content: content,
                    entry: entry,
                    todayDetail: .full,
                    tomorrowDetail: .full,
                    thirdDayDetail: .compact
                )
                LargeForecastLayout(
                    content: content,
                    entry: entry,
                    todayDetail: .full,
                    tomorrowDetail: .compact,
                    thirdDayDetail: .compact
                )
                LargeForecastLayout(
                    content: content,
                    entry: entry,
                    todayDetail: .compact,
                    tomorrowDetail: .compact,
                    thirdDayDetail: .compact
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        } else {
            OnboardingWidgetView(message: entry.statusMessage ?? "No data")
        }
    }
}

enum LargeDayDetailLevel {
    case full
    case compact
}

struct LargeForecastLayout: View {
    let content: WidgetResolvedContent
    let entry: SunsetHueEntry
    let todayDetail: LargeDayDetailLevel
    let tomorrowDetail: LargeDayDetailLevel
    let thirdDayDetail: LargeDayDetailLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(
                locationName: content.locationName,
                updatedText: WidgetUpdatedCopy.text(for: entry)
            )

            ForEach(content.daySections) { section in
                LargeDayBlock(
                    section: section,
                    detail: detailLevel(for: section.dayOffset)
                )
            }

            if let hint = content.hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private func detailLevel(for dayOffset: Int) -> LargeDayDetailLevel {
        switch dayOffset {
        case 0: return todayDetail
        case 1: return tomorrowDetail
        default: return thirdDayDetail
        }
    }
}

struct LargeDayBlock: View {
    let section: WidgetDaySection
    let detail: LargeDayDetailLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.dayLabel.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(section.events) { event in
                switch detail {
                case .full:
                    LargeEventRow(event: event, timeZone: section.timeZone, showMetadata: true)
                case .compact:
                    LargeEventRow(event: event, timeZone: section.timeZone, showMetadata: false)
                }
            }
        }
    }
}

struct LargeEventRow: View {
    let event: WidgetEventContent
    let timeZone: TimeZone
    var showMetadata: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            LargeEventPrimaryLine(event: event)

            if showMetadata {
                LargeMetadataLine(
                    cloudCover: event.cloudCover,
                    goldenHour: event.goldenHour,
                    blueHour: event.blueHour,
                    timeZone: timeZone
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let qualityStyle = WidgetQualityStyle.resolve(
            quality: event.quality,
            qualityText: event.qualityText
        )
        var parts = [
            event.eventType.displayName,
            "\(qualityStyle.percentage) \(qualityStyle.status)",
            "at \(event.timeLabel)"
        ]
        if showMetadata {
            let cloud: String
            if let cloudCover = event.cloudCover {
                cloud = cloudCover.formatted(.percent.precision(.fractionLength(0)))
            } else {
                cloud = "—"
            }
            parts.append("Cloud cover \(cloud)")
            parts.append("golden hour \(windowAccessibility(event.goldenHour))")
            parts.append("blue hour \(windowAccessibility(event.blueHour))")
        }
        return parts.joined(separator: ", ")
    }

    private func windowAccessibility(_ window: MagicHourWindow?) -> String {
        guard let window,
              let start = PresentationFormatting.timeString(window.start, timeZone: timeZone),
              let end = PresentationFormatting.timeString(window.end, timeZone: timeZone) else {
            return "—"
        }
        return "\(start) to \(end)"
    }
}

struct LargeEventPrimaryLine: View {
    let event: WidgetEventContent

    var body: some View {
        let qualityStyle = WidgetQualityStyle.resolve(
            quality: event.quality,
            qualityText: event.qualityText
        )

        HStack(spacing: 6) {
            Label {
                Text(event.eventType.displayName)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: event.eventType.symbolName)
                    .foregroundStyle(event.eventType.iconColor)
            }
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)

            Spacer(minLength: 4)

            Text(qualityStyle.percentage)
                .font(.caption.weight(.bold))
                .foregroundStyle(qualityStyle.tint)

            Text(qualityStyle.status)
                .font(.caption2.weight(.medium))
                .foregroundStyle(qualityStyle.tint)
                .lineLimit(1)

            Text(event.timeLabel)
                .font(.caption.weight(.semibold).monospacedDigit())
                .frame(minWidth: 42, alignment: .trailing)
        }
    }
}

struct LargeMetadataLine: View {
    let cloudCover: Double?
    let goldenHour: MagicHourWindow?
    let blueHour: MagicHourWindow?
    let timeZone: TimeZone

    var body: some View {
        ViewThatFits(in: .horizontal) {
            oneLineLayout
            twoLineFallback
        }
        .font(.caption2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var oneLineLayout: some View {
        HStack(spacing: 10) {
            Label(cloudLabel, systemImage: "cloud.fill")
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .fixedSize(horizontal: true, vertical: false)

            MetadataToken(
                label: "Gold",
                value: windowLabel(goldenHour),
                tint: .orange
            )

            MetadataToken(
                label: "Blue",
                value: windowLabel(blueHour),
                tint: .cyan
            )
        }
        .lineLimit(1)
    }

    private var twoLineFallback: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Label(cloudLabel, systemImage: "cloud.fill")
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)

                MetadataToken(
                    label: "Gold",
                    value: windowLabel(goldenHour),
                    tint: .orange
                )
            }

            MetadataToken(
                label: "Blue",
                value: windowLabel(blueHour),
                tint: .cyan
            )
        }
    }

    private var cloudLabel: String {
        guard let cloudCover else { return "—" }
        return cloudCover.formatted(.percent.precision(.fractionLength(0)))
    }

    private func windowLabel(_ window: MagicHourWindow?) -> String {
        guard let window,
              let start = PresentationFormatting.timeString(window.start, timeZone: timeZone),
              let end = PresentationFormatting.timeString(window.end, timeZone: timeZone) else {
            return "—"
        }
        return "\(start)–\(end)"
    }

    private var accessibilityDescription: String {
        "Cloud cover \(cloudLabel). Golden hour \(windowLabel(goldenHour)). Blue hour \(windowLabel(blueHour))."
    }
}

private struct MetadataToken: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .fontWeight(.semibold)
                .foregroundStyle(tint)

            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(1)
    }
}
