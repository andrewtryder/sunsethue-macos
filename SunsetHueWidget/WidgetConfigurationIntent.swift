import AppIntents
import Foundation
import SunsetHueCore

enum WidgetEventMode: String, AppEnum {
    case sunrise
    case sunset
    case both

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Event")
    static let caseDisplayRepresentations: [WidgetEventMode: DisplayRepresentation] = [
        .sunrise: "Sunrise",
        .sunset: "Sunset",
        .both: "Both",
    ]
}

enum WidgetPreferredDay: String, AppEnum {
    case today
    case tomorrow
    case upcoming

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Display")
    static let caseDisplayRepresentations: [WidgetPreferredDay: DisplayRepresentation] = [
        .today: "Today",
        .tomorrow: "Tomorrow",
        .upcoming: "Next Events",
    ]
}

enum WidgetDetailLevel: String, AppEnum {
    case compact
    case detailed

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Detail")
    static let caseDisplayRepresentations: [WidgetDetailLevel: DisplayRepresentation] = [
        .compact: "Compact",
        .detailed: "Detailed",
    ]
}

struct LocationEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Location")
    static let defaultQuery = LocationEntityQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    init(location: SavedLocation) {
        self.id = location.id
        self.name = location.name
    }
}

struct LocationEntityQuery: EntityQuery {
    func entities(for identifiers: [LocationEntity.ID]) async throws -> [LocationEntity] {
        let locations = (try? await SharedStorageFactory.makeSettingsStore().load())?.value.locations ?? []
        return locations
            .filter { identifiers.contains($0.id) }
            .map(LocationEntity.init)
    }

    func suggestedEntities() async throws -> [LocationEntity] {
        let locations = (try? await SharedStorageFactory.makeSettingsStore().load())?.value.locations ?? []
        return locations.map(LocationEntity.init)
    }

    func defaultResult() async -> LocationEntity? {
        try? await suggestedEntities().first
    }
}

struct SunsetHueWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "SunsetHue"
    static let description = IntentDescription("Show sunrise and sunset forecast quality for a saved location.")

    @Parameter(title: "Location")
    var location: LocationEntity?

    @Parameter(title: "Event", default: .both)
    var eventMode: WidgetEventMode

    @Parameter(title: "Display", default: .today)
    var preferredDay: WidgetPreferredDay

    @Parameter(title: "Detail", default: .compact)
    var detailLevel: WidgetDetailLevel
}
