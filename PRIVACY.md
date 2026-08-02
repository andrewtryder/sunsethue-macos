# Privacy

SunsetHue sends the configured latitude, longitude, forecast date, event type, and API key to api.sunsethue.com over HTTPS when retrieving a forecast. The API key is stored in the macOS Keychain. Forecast data and application preferences are stored locally.

Location Services is accessed only when you select “Use Current Location.” SunsetHue does not continuously monitor your location.

When update checking is enabled or “Check Now” is selected, SunsetHue contacts GitHub’s API to determine the latest published version.

SunsetHue contains no analytics, advertising, tracking, telemetry, or third-party crash-reporting service.

The widget does not access the API key or contact SunsetHue directly. It reads sanitized forecast information stored locally by the main application.

Diagnostic exports exclude the API key and exact coordinates by default.
