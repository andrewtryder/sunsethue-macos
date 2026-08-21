import Foundation
import os

public struct ForecastService: Sendable {
    private let transport: any HTTPTransport
    private let dateCalculator: ForecastDateCalculator
    private let logger = Logger(subsystem: "com.andrewtryder.SunsetHue", category: "Forecast")

    public init(
        transport: any HTTPTransport = URLSessionTransport(),
        dateCalculator: ForecastDateCalculator = ForecastDateCalculator()
    ) {
        self.transport = transport
        self.dateCalculator = dateCalculator
    }

    public func refresh(
        location: SavedLocation,
        apiKey: String,
        now: Date = Date()
    ) async throws -> LocationForecastBundle {
        guard let timeZone = location.timeZone else {
            throw SunsetHueError.invalidLocation("Time zone identifier is invalid.")
        }
        let validated = try location.validated()
        let events = validated.enabledEvents
        guard !events.isEmpty else {
            throw SunsetHueError.invalidLocation("Enable at least sunrise or sunset.")
        }

        let client = SunsetHueClient(apiKey: apiKey, transport: transport)
        // Internal operational cache horizon requires at least 2 days to ensure continuous
        // next-event resolution across local-day rollover, independent of user-configured display forecastDays.
        let effectiveForecastDays = min(
            SunsetHueConstants.maxForecastDays,
            max(validated.forecastDays, SunsetHueConstants.minimumOperationalForecastDays)
        )
        let dates = dateCalculator.localCalendarDates(
            dayCount: effectiveForecastDays,
            timeZone: timeZone,
            now: now
        )

        var keys: [ForecastKey] = []
        for (offset, _) in dates.enumerated() {
            for event in events {
                keys.append(ForecastKey(dayOffset: offset, eventType: event))
            }
        }

        let forecasts = try await fetchAll(
            keys: keys,
            dates: dates,
            coordinates: validated.coordinates,
            timeZone: timeZone,
            client: client
        )

        return LocationForecastBundle(
            locationID: validated.id,
            fetchedAt: now,
            keyedForecasts: forecasts
        )
    }

    /// Preserves previous cache on transient failure; replaces on success.
    public func refreshPreservingCache(
        location: SavedLocation,
        apiKey: String,
        previous: LocationForecastBundle?,
        now: Date = Date()
    ) async -> RefreshOutcome {
        do {
            let bundle = try await refresh(location: location, apiKey: apiKey, now: now)
            return RefreshOutcome(bundle: bundle, error: nil, usedCache: false)
        } catch let error as SunsetHueError {
            logger.error("Refresh failed: \(error.diagnosticDescription, privacy: .public)")
            if error.isTransient, let previous {
                return RefreshOutcome(bundle: previous, error: error, usedCache: true)
            }
            return RefreshOutcome(bundle: previous, error: error, usedCache: previous != nil)
        } catch {
            logger.error("Refresh failed with unexpected error")
            let mapped = SunsetHueError.networkUnavailable
            if let previous {
                return RefreshOutcome(bundle: previous, error: mapped, usedCache: true)
            }
            return RefreshOutcome(bundle: nil, error: mapped, usedCache: false)
        }
    }

    private func fetchAll(
        keys: [ForecastKey],
        dates: [Date],
        coordinates: Coordinates,
        timeZone: TimeZone,
        client: SunsetHueClient
    ) async throws -> [ForecastKey: EventForecast] {
        try await withThrowingTaskGroup(of: (ForecastKey, EventForecast).self) { group in
            var iterator = keys.makeIterator()
            var inFlight = 0
            var results: [ForecastKey: EventForecast] = [:]

            func enqueueNext() {
                while inFlight < SunsetHueConstants.fetchConcurrencyLimit, let key = iterator.next() {
                    inFlight += 1
                    let forecastDate = dates[key.dayOffset]
                    group.addTask {
                        let forecast = try await client.fetchEvent(
                            coordinates: coordinates,
                            date: forecastDate,
                            eventType: key.eventType,
                            forecast: true,
                            timeZone: timeZone
                        )
                        return (key, forecast.withForecastDate(forecastDate))
                    }
                }
            }

            enqueueNext()
            while let (key, forecast) = try await group.next() {
                inFlight -= 1
                results[key] = forecast
                enqueueNext()
            }

            // Atomic completeness: every requested key must be present.
            guard results.count == keys.count else {
                throw SunsetHueError.invalidResponse("incomplete_forecast_grid")
            }
            return results
        }
    }
}
