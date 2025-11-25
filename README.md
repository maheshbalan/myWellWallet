# MyWellWallet

A Flutter mobile application for managing health records via FHIR MCP Server.

## Features

- Connect to FHIR MCP Server via HTTP/SSE
- View list of patients
- View detailed patient information
- Modern, clean UI with Material Design 3

## Setup

1. **Install Flutter dependencies:**
   ```bash
   flutter pub get
   ```

2. **Generate JSON serialization code:**
   ```bash
   flutter pub run build_runner build
   ```

3. **Run the app:**
   ```bash
   flutter run
   ```

## Configuration

The app is configured to connect to:
- **MCP Server**: `https://mcp-fhir-server-maheshbalan1.replit.app`

To change the server URL, modify `lib/main.dart`:
```dart
final mcpClient = MCPClient(
  baseUrl: 'YOUR_SERVER_URL_HERE',
);
```

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── models/                   # Data models
│   └── patient.dart
├── services/                 # MCP client service
│   └── mcp_client.dart
├── providers/                # State management
│   └── patient_provider.dart
├── screens/                  # UI screens
│   ├── home_screen.dart
│   ├── patient_list_screen.dart
│   └── patient_detail_screen.dart
└── widgets/                  # Reusable widgets
    ├── patient_card.dart
    └── info_section.dart
```

## Requirements

- Flutter SDK >=3.0.0
- Dart SDK >=3.0.0

## Dependencies

- `provider` - State management
- `http` - HTTP requests
- `sse` - Server-Sent Events support
- `go_router` - Navigation
- `json_annotation` - JSON serialization
- `intl` - Date formatting
- `font_awesome_flutter` - Icons
