/// The one place the backend URL is set. Every release build talks to the
/// production server; for local development pass a dart-define:
///
///     flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
///
/// (10.0.2.2 is your machine as seen from the Android emulator; a real phone
/// on the same Wi-Fi uses your LAN IP.) Production needs no flag — the
/// default below is baked in.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://backend.eventsexclusive.africa',
);
