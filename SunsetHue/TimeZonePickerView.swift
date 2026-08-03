import SwiftUI
import SunsetHueCore

struct TimeZonePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Current") {
                    timeZoneButton(selection)
                    if selection != TimeZone.autoupdatingCurrent.identifier {
                        timeZoneButton(TimeZone.autoupdatingCurrent.identifier)
                    }
                }

                Section("Suggested United States") {
                    ForEach(TimeZoneCatalog.filter(TimeZoneCatalog.unitedStates, searchText: searchText), id: \.self) {
                        timeZoneButton($0)
                    }
                }

                Section("Suggested Europe") {
                    ForEach(TimeZoneCatalog.filter(TimeZoneCatalog.europe, searchText: searchText), id: \.self) {
                        timeZoneButton($0)
                    }
                }

                Section("All Time Zones") {
                    ForEach(TimeZoneCatalog.filter(TimeZoneCatalog.remaining, searchText: searchText), id: \.self) {
                        timeZoneButton($0)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search time zones")
            .navigationTitle("Choose Time Zone")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 560)
    }

    private func timeZoneButton(_ identifier: String) -> some View {
        Button {
            selection = identifier
            dismiss()
        } label: {
            TimeZoneRow(identifier: identifier, selected: identifier == selection)
        }
        .buttonStyle(.plain)
    }
}

struct TimeZoneRow: View {
    let identifier: String
    let selected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(TimeZoneCatalog.friendlyCity(for: identifier))
                    .font(.body.weight(.medium))
                Text(secondaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Selected")
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(TimeZoneCatalog.friendlyCity(for: identifier)), \(identifier)")
    }

    private var secondaryLine: String {
        let abbreviation = TimeZoneCatalog.displayAbbreviation(for: identifier)
        let gmt = TimeZoneCatalog.displayGMTOffset(for: identifier)
        let parts = [identifier, abbreviation, gmt].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }
}
