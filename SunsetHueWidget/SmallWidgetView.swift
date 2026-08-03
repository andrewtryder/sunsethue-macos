import SwiftUI
import SunsetHueCore

struct SmallWidgetView: View {
    let entry: SunsetHueEntry

    var body: some View {
        if let content = WidgetContentResolver.resolve(entry: entry, preferSingle: true) {
            let event = content.primary
            let style = WidgetQualityStyle.resolve(quality: event.quality, qualityText: event.qualityText)

            VStack(alignment: .leading, spacing: 5) {
                Text(content.locationName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Label {
                    Text("\(event.eventType.displayName) · \(event.dayLabel)")
                } icon: {
                    Image(systemName: event.eventType.symbolName)
                        .foregroundStyle(event.eventType.iconColor)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

                HStack(alignment: .firstTextBaseline) {
                    Text(style.percentage)
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .foregroundStyle(style.tint)
                        .minimumScaleFactor(0.7)
                        .accessibilityLabel("Forecast quality")
                        .accessibilityValue("\(style.percentage), \(style.status)")

                    Spacer(minLength: 6)

                    Text(event.timeLabel)
                        .font(.title3.weight(.semibold).monospacedDigit())
                }

                HStack {
                    QualityBadge(style: style)
                    Spacer()
                    Text("Event time")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let hint = content.hint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                } else {
                    MagicHourView(
                        goldenHourLabel: event.goldenHourLabel,
                        blueHourLabel: event.blueHourLabel,
                        cloudCoverLabel: event.cloudCoverLabel,
                        preferred: event.eventType == .sunrise ? .preferBlue : .preferGolden,
                        showCloud: false
                    )
                }

                Spacer(minLength: 0)

                UpdatedLabel(entry: entry)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(content.accessibilityLabel)
        } else {
            OnboardingWidgetView(message: entry.statusMessage ?? "No data")
        }
    }
}
