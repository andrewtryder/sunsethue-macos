import Foundation
import MapKit
import CoreLocation
import SunsetHueCore

@MainActor
final class PlaceSearchController: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = ""
    @Published private(set) var results: [MKLocalSearchCompletion] = []
    @Published private(set) var isResolving = false
    @Published var errorMessage: String?

    private let completer = MKLocalSearchCompleter()
    private var suppressNextCompleterUpdate = false

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func updateQuery(_ value: String) {
        query = value
        completer.queryFragment = value
    }

    /// Syncs the search field to the selected place without reopening suggestions.
    func syncToSelectedName(_ name: String) {
        suppressNextCompleterUpdate = true
        query = name
        results = []
        completer.queryFragment = ""
        errorMessage = nil
    }

    func clearResults() {
        results = []
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        if suppressNextCompleterUpdate {
            suppressNextCompleterUpdate = false
            results = []
            return
        }
        results = Array(completer.results.prefix(8))
        errorMessage = nil
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        if suppressNextCompleterUpdate {
            suppressNextCompleterUpdate = false
        }
        results = []
        errorMessage = "Place search is temporarily unavailable."
    }

    func resolve(_ completion: MKLocalSearchCompletion) async throws -> ResolvedPlace {
        isResolving = true
        defer { isResolving = false }

        let request = MKLocalSearch.Request(completion: completion)
        let response = try await MKLocalSearch(request: request).start()

        guard let item = response.mapItems.first else {
            throw PlaceSearchError.noResult
        }

        let coordinate: CLLocationCoordinate2D
        if #available(macOS 26, *) {
            coordinate = item.location.coordinate
        } else {
            coordinate = item.placemark.coordinate
        }

        return ResolvedPlace(
            name: preferredDisplayName(item: item, completion: completion),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            timeZoneIdentifier: item.timeZone?.identifier
        )
    }

    private func preferredDisplayName(
        item: MKMapItem,
        completion: MKLocalSearchCompletion
    ) -> String {
        if let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return completion.title
    }
}

enum PlaceSearchError: LocalizedError {
    case noResult

    var errorDescription: String? {
        "The selected place could not be resolved."
    }
}
