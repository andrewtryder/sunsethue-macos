import AppIntents
import Foundation
import SunsetHueCore

enum WidgetEventMode: String, AppEnum {
    case sunrise
    case sunset
    case both

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Event")
    static var caseDisplayRepresentations: [WidgetEventMode: DisplayRepresentation] = [
        .sunrise: "Sunrise",
        .sunset: "Sunset",
        .both: "Both",
    ]
}

enum WidgetPreferredDay: String, AppEnum {
    case today
    case tomorrow

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Day")
    static var caseDisplayRepresentations: [WidgetPreferredDay: DisplayRepresentation] = [
        .today: "Today",
        .tomorrow: "Tomorrow",
    ]
}

enum WidgetDetailLevel: String, AppEnum {
    case compact
    case detailed

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Detail")
    static var caseDisplayRepresentations: [WidgetDetailLevel: DisplayRepresentation] = [
        .compact: "Compact",
        .detailed: "Detailed",
    ]
}

struct LocationEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Location")
    static var defaultQuery = LocationEntityQuery()

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
        let locations = (try? await SharedStorageFactory.makeSettingsStore().load())?.locations ?? []
        return locations
            .filter { identifiers.contains($0.id) }
            .map(LocationEntity.init)
    }

    func suggestedEntities() async throws -> [LocationEntity] {
        let locations = (try? await SharedStorageFactory.makeSettingsStore().load())?.locations ?? []
        return locations.map(LocationEntity.init)
    }

    func defaultResult() async -> LocationEntity? {
        try? await suggestedEntities().first
    }
}

struct SunsetHueWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "SunsetHue"
    static var description = IntentDescription("Show sunrise and sunset forecast quality for a saved location.")

    @Parameter(title: "Location")
    var location: LocationEntity?

    @Parameter(title: "Event", default: .both)
    var eventMode: WidgetEventMode

    @Parameter(title: "Day", default: .today)
    var preferredDay: WidgetPreferredDay

    @Parameter(title: "Detail", default: .compact)
    var detailLevel: WidgetDetailLevel
}
