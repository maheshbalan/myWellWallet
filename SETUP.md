# MyWellWallet Setup Guide

## Overview

MyWellWallet is a Flutter mobile application that connects to the FHIR MCP Server via HTTP/SSE to manage health records.

## Prerequisites

- Flutter SDK >=3.8.0
- Dart SDK >=3.8.0
- Android Studio / Xcode (for mobile development)
- VS Code or Android Studio (recommended IDE)

## Installation Steps

1. **Install dependencies:**
   ```bash
   cd ~/myWellWallet
   flutter pub get
   ```

2. **Generate JSON serialization code:**
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

3. **Verify the setup:**
   ```bash
   flutter doctor
   ```

## Running the App

### iOS
```bash
flutter run -d ios
```

### Android
```bash
flutter run -d android
```

### Web (for testing)
```bash
flutter run -d chrome
```

## Configuration

The app is configured to connect to:
- **MCP Server**: `https://mcp-fhir-server-maheshbalan1.replit.app`

To change the server URL, edit `lib/main.dart`:
```dart
final mcpClient = MCPClient(
  baseUrl: 'YOUR_SERVER_URL_HERE',
);
```

## Project Structure

```
myWellWallet/
├── lib/
│   ├── main.dart                    # App entry point & routing
│   ├── models/                      # Data models
│   │   ├── patient.dart
│   │   └── patient.g.dart          # Generated JSON serialization
│   ├── services/                    # API services
│   │   └── mcp_client.dart         # MCP HTTP/SSE client
│   ├── providers/                   # State management (Provider)
│   │   └── patient_provider.dart
│   ├── screens/                     # UI screens
│   │   ├── home_screen.dart
│   │   ├── patient_list_screen.dart
│   │   └── patient_detail_screen.dart
│   └── widgets/                     # Reusable widgets
│       ├── patient_card.dart
│       └── info_section.dart
├── assets/                          # Images, icons, etc.
├── pubspec.yaml                     # Dependencies
└── README.md
```

## Features

### Current Features
- ✅ Connect to FHIR MCP Server
- ✅ List all patients
- ✅ View patient details
- ✅ Modern Material Design 3 UI
- ✅ Error handling and loading states
- ✅ Pull-to-refresh

### Screens

1. **Home Screen** - Welcome screen with navigation to patient list
2. **Patient List Screen** - Displays all patients with search capability
3. **Patient Detail Screen** - Shows comprehensive patient information

## HTTP/SSE Implementation Notes

The app uses HTTP POST requests with Server-Sent Events (SSE) responses. Each request:
1. Sends a JSON-RPC 2.0 message
2. Receives an SSE-formatted response
3. Parses the response to extract data

**Note**: The current MCP server implementation requires session management. The client handles this by:
- Initializing a session on first connection
- Maintaining session state
- Sending requests with proper headers

## Troubleshooting

### Build Errors
- Run `flutter clean` then `flutter pub get`
- Regenerate JSON files: `flutter pub run build_runner build --delete-conflicting-outputs`

### Connection Issues
- Verify the MCP server is running and accessible
- Check network connectivity
- Review server logs for errors

### JSON Serialization Errors
- Ensure `patient.g.dart` is generated
- Run: `flutter pub run build_runner build --delete-conflicting-outputs`

## Next Steps

1. **Test the connection** once the server is deployed
2. **Customize the UI** based on design requirements
3. **Add more features**:
   - Search functionality
   - Filter patients
   - Add/edit patient records
   - View medical history
   - View prescriptions
   - View lab results

## Development

### Adding New Features

1. **New Models**: Add to `lib/models/` and run build_runner
2. **New Screens**: Add to `lib/screens/` and update routing in `main.dart`
3. **New Services**: Add to `lib/services/` and integrate with providers
4. **New Widgets**: Add to `lib/widgets/` for reusable components

### State Management

The app uses Provider for state management. To add new state:
1. Create a provider in `lib/providers/`
2. Add it to `MultiProvider` in `main.dart`
3. Use `Consumer` or `Provider.of` in widgets

## License

This project is part of the MyWellWallet application.

