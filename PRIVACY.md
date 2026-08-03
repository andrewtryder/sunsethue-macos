# Privacy

SunsetHue sends the configured latitude, longitude, forecast date, event type, and API key to api.sunsethue.com over HTTPS when retrieving a forecast. The API key is stored in the macOS Keychain. Forecast data and application preferences are stored locally.

Location Services is accessed only when you select “Use Current Location.” SunsetHue does not continuously monitor your location. When available, reverse geocoding may resolve a geographic time zone for that coordinate.

Place search sends the search terms you type to Apple through MapKit so nearby places can be suggested. SunsetHue does not retain a local search history of those terms.

When update checking is enabled or “Check Now” is selected, SunsetHue contacts GitHub’s API to determine the latest published version.

SunsetHue contains no analytics, advertising, tracking, telemetry, or third-party crash-reporting service.

The widget does not access the API key or contact SunsetHue directly. It reads sanitized forecast information stored locally by the main application.

When notifications are enabled, SunsetHue schedules local notifications through macOS. No push notification server is used. Notifications may display the selected location name, event time, and forecast quality in Notification Center or on the lock screen, depending on the user’s macOS notification-preview settings.

Threshold notifications are evaluated locally after SunsetHue retrieves a new forecast.

Diagnostic exports exclude the API key and exact coordinates by default.
