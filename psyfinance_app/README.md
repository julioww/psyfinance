# PsyFinance App

Flutter web application for PsyFinance — financial management for a solo psychology practice.

## Stack

- **Framework:** Flutter (web, Chrome)
- **State management:** Riverpod
- **HTTP client:** Dio
- **Routing:** go_router
- **Localization:** flutter_localizations (pt_BR)

## Prerequisites

- Flutter SDK (stable channel)
- Chrome browser

## Setup

```bash
# Install dependencies
flutter pub get

# Run on Chrome (default port 5000)
flutter run -d chrome --web-port 5000
```

The app will open at `http://localhost:5000`.

## Pointing at the local API

The API client (`lib/core/api_client.dart`) defaults to `http://localhost:3000`.
Make sure the API is running before launching the app:

```bash
# In psyfinance-api/
npm run dev
```

Then run the Flutter app — the HomeScreen will call `GET /health` and display **"API conectada ✓"**.

## Project Structure

```
lib/
├── core/
│   ├── api_client.dart   # Dio HTTP client with ApiException
│   ├── app_router.dart   # go_router configuration
│   ├── formatters.dart   # Date, currency, month name helpers
│   └── theme.dart        # Material 3 theme (seed: #1A6B5A)
├── screens/
│   └── home_screen.dart  # Health-check screen
└── main.dart             # App entry point (ProviderScope + pt_BR locale)
```

## Design System

- Material 3 (`useMaterial3: true`)
- Color seed: `#1A6B5A` (deep teal-green)
- Locale: `pt_BR`
- Date format: `DD/MM/YYYY`
- Currency: `R$ 1.000,00` (BRL) / `€1.000,00` (EUR)
