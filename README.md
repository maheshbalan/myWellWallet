# MyWellWallet

<div align="center">

**A modern Flutter mobile application for managing health records via FHIR MCP Server**

[![Flutter](https://img.shields.io/badge/Flutter-3.8+-02569B?logo=flutter)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.8+-0175C2?logo=dart)](https://dart.dev/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

</div>

---

## 📱 Overview

MyWellWallet is a healthcare application that provides a clean, modern interface for managing patient health records. Built with Flutter and integrated with FHIR (Fast Healthcare Interoperability Resources) standards, the app connects to a Model Context Protocol (MCP) server to securely access and display patient information.

### Key Highlights

- 🎨 **Bauhaus-Inspired Design**: Clean, geometric, and calming UI perfect for healthcare applications
- 🔒 **FHIR Compliant**: Secure integration with FHIR-compliant health systems
- 🩺 **Apple Health (iOS)**: Health dashboard with glucose (CGM), heart rate, steps, and blood pressure synced from Apple Health
- 🎙️ **Voice Assistant**: Speech-to-text on the Home screen to ask questions about your health data
- 🚀 **Modern Architecture**: Built with Flutter and Material Design 3
- 📊 **Patient Management**: View patient lists and detailed health information
- 🌐 **MCP Integration**: Seamless connection to FHIR MCP Server via HTTP/SSE

---

## ✨ Features

### Core Functionality

- **Patient List View**: Browse all available patients with clean, card-based interface
- **Patient Details**: Comprehensive view of patient information including:
  - Personal information (name, gender, birth date)
  - Identifiers (medical record numbers, etc.)
  - Address information
  - Contact details (phone, email)
- **Real-time Data**: Connect to live FHIR MCP Server for up-to-date information
- **Error Handling**: Graceful error states with retry functionality
- **Pull-to-Refresh**: Easy data refresh with intuitive gestures

### Health & Apple Health (iOS)

- **Health Dashboard**: Dedicated `Health` tab summarizing:
  - Glucose (CGM)
  - Heart rate
  - Steps
  - Blood pressure
- **Detail Screens**: Individual views for each metric with trend cards and reading history.
- **Apple Health Sync**:
  - Connect from the **Profile → Apple Health** section.
  - Configurable sync interval (e.g., every 6/12/24 hours, weekly).
  - Data is stored locally in SQLite tables documented in `assets/docs/SQLITE_SCHEMA.md`.
- **Setup Guide**: See `docs/APPLE_HEALTH_SETUP.md` for HealthKit entitlements and iOS-specific setup.

### Voice Assistant

- **Speech-to-Text Input**: Tap the microphone on the Home screen to dictate your question.
- **Health-Aware Queries**: Voice queries are sent through the MCP/Gemma pipeline with patient context.
- **Permissions**:
  - Uses `permission_handler` with `Permission.microphone` and `Permission.speech`.
  - iOS `Info.plist` includes `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription`.
  - Podfile enables `PERMISSION_MICROPHONE` and `PERMISSION_SPEECH_RECOGNIZER` for iOS builds.

### Design Features

- **Bauhaus Aesthetic**: Geometric shapes, clean lines, and minimalist design
- **Calming Color Palette**: Soft blues, mint greens, and warm accents
- **Responsive Layout**: Optimized for various screen sizes
- **Accessibility**: Clear typography and high contrast for readability
- **Loading States**: Smooth loading indicators and transitions

---

## 🎨 Design Philosophy

MyWellWallet follows Bauhaus design principles adapted for healthcare:

- **Form Follows Function**: Every element serves a purpose
- **Geometric Simplicity**: Clean shapes and structured layouts
- **Calming Aesthetics**: Soft colors and generous white space
- **Modern Typography**: Clear, readable fonts with proper hierarchy
- **Minimalist Approach**: No unnecessary decorations or distractions

### Color Palette

- **Primary Blue**: `#4A90E2` - Trust and professionalism
- **Mint Green**: `#7ED321` - Health and wellness
- **Warm Accent**: `#F5A623` - Energy and positivity
- **Background**: `#F8F9FA` - Clean and calming
- **Text**: `#2C3E50` - Deep blue-gray for readability

---

## 🏗️ Architecture

### Project Structure

```
lib/
├── main.dart                     # App entry point, routing, and theme configuration
├── models/                       # Data models (Patient, User, FetchStatus, etc.)
├── services/                     # External + local service integrations
│   ├── mcp_client.dart           # FHIR MCP Server client (HTTP/SSE)
│   ├── apple_health_service.dart # Apple Health / HealthKit integration (iOS)
│   ├── database_service.dart     # SQLite database service
│   └── data_sync_service.dart    # Patient/health data sync orchestration
├── providers/                    # State management (Provider pattern)
│   ├── auth_provider.dart        # Authentication and current user
│   ├── patient_provider.dart     # Patient and local FHIR data state
│   └── query_provider.dart       # Conversation and query state for MCP/Gemma
├── screens/                      # UI screens
│   ├── home_screen.dart          # Home + voice assistant entry point
│   ├── login_screen.dart         # Authentication
│   ├── registration_screen.dart  # Account creation
│   ├── patient_list_screen.dart  # Patient list view
│   ├── patient_detail_screen.dart# Patient detail view
│   ├── profile_screen.dart       # Profile, Apple Health connection, sync interval
│   └── health_*.dart             # Health dashboard + detail screens (glucose, heart rate, steps, BP)
└── widgets/                      # Reusable UI components
    ├── patient_card.dart         # Patient list item card
    ├── info_section.dart         # Information section widget
    ├── conversation_message.dart # Chat-style messages for the assistant
    ├── app_bottom_nav.dart       # Bottom navigation bar (Home / Health / Profile)
    └── app_bar_logo.dart         # App bar logo with optional back navigation

### Technology Stack

- **Framework**: Flutter 3.8+
- **Language**: Dart 3.8+
- **State Management**: Provider
- **Navigation**: GoRouter
- **HTTP Client**: http package
- **JSON Serialization**: json_annotation + build_runner
- **Icons**: Font Awesome Flutter
- **Date Formatting**: intl

---

## 🚀 Getting Started

### Prerequisites

- **Flutter SDK**: 3.8.0 or higher
- **Dart SDK**: 3.8.0 or higher
- **Android Studio** or **VS Code** with Flutter extensions
- **Android SDK** (for Android development)
- **Xcode** (for iOS development, macOS only)

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/maheshbalan/myWellWallet.git
   cd myWellWallet
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Generate JSON serialization code:**
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

4. **Generate app icons:**
   ```bash
   flutter pub run flutter_launcher_icons
   ```

5. **Run the app:**
   ```bash
   flutter run
   ```

### Building for Production

#### Android

```bash
flutter build apk --release
# or for app bundle
flutter build appbundle --release
```

#### iOS

```bash
flutter build ios --release
```

---

## ⚙️ Configuration

### FHIR MCP Server

The app is configured to connect to:
```
https://mcp-fhir-server-maheshbalan1.replit.app
```

To change the server URL, modify `lib/main.dart`:

```dart
final mCPClient = MCPClient(
  baseUrl: 'YOUR_SERVER_URL_HERE',
);
```

### Apple Health (iOS)

- HealthKit entitlements and Info.plist keys are preconfigured for Apple Health.
- Follow `docs/APPLE_HEALTH_SETUP.md` to:
  - Ensure the **HealthKit** capability is enabled in Xcode.
  - Connect to Apple Health from **Profile → Apple Health**.
  - Choose a sync interval and run the first sync to populate the Health dashboard.

### App Icon

The app uses a custom icon located at `assets/icons/MyWellWallet.png`. The icon configuration is in `pubspec.yaml`:

```yaml
flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/icons/MyWellWallet.png"
  adaptive_icon_background: "#4A90E2"
```

To regenerate icons after changing the source image:
```bash
flutter pub run flutter_launcher_icons
```

---

## 🔌 FHIR MCP Server Integration

### MCP Protocol

MyWellWallet uses the Model Context Protocol (MCP) to communicate with the FHIR server:

- **Protocol**: JSON-RPC 2.0 over HTTP/SSE
- **Initialization**: Session-based connection
- **Tools**: Uses `request_patient_resource` tool for FHIR operations

### Supported Operations

1. **List Patients**: `GET /Patient`
   - Retrieves all available patients
   - Returns FHIR Bundle with Patient resources

2. **Get Patient Details**: `GET /Patient/{id}`
   - Retrieves specific patient by ID
   - Returns complete Patient resource

### MCP Client Implementation

The `MCPClient` class handles:
- Session initialization
- JSON-RPC request/response handling
- SSE (Server-Sent Events) parsing
- Error handling and retries
- FHIR resource parsing

---

## 📱 Screens

### Home Screen

- Welcome message and app branding
- Primary navigation to patient list
- Information about the app
- Clean, geometric design elements

### Patient List Screen

- Scrollable list of all patients
- Patient cards with key information
- Pull-to-refresh functionality
- Loading and error states
- Floating action button for refresh

### Patient Detail Screen

- Comprehensive patient information
- Organized sections:
  - Personal Information
  - Identifiers
  - Address
  - Contact Information
- Clean card-based layout

---

## 🧪 Development

### Running Tests

```bash
flutter test
```

### Code Generation

When modifying models, regenerate JSON serialization:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### Linting

The project uses `flutter_lints` for code quality:

```bash
flutter analyze
```

---

## 📦 Dependencies

### Main Dependencies

- **provider** (^6.1.1): State management
- **http** (^1.1.0): HTTP client for API calls
- **go_router** (^12.1.1): Declarative routing
- **json_annotation** (^4.9.0): JSON serialization annotations
- **intl** (^0.18.1): Internationalization and date formatting
- **font_awesome_flutter** (^10.6.0): Icon library

### Dev Dependencies

- **flutter_lints** (^3.0.1): Linting rules
- **build_runner** (^2.4.7): Code generation
- **json_serializable** (^6.7.1): JSON code generation
- **flutter_launcher_icons** (^0.13.1): App icon generation

---

## 🐛 Troubleshooting

### Common Issues

#### Build Errors

```bash
# Clean build cache
flutter clean
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
```

#### Connection Issues

- Verify the MCP server is running and accessible
- Check network connectivity
- Review server logs for errors
- Ensure the server URL is correct in `lib/main.dart`

#### JSON Serialization Errors

```bash
# Regenerate JSON files
flutter pub run build_runner build --delete-conflicting-outputs
```

#### Icon Generation Issues

- Ensure the source icon exists at `assets/icons/MyWellWallet.png`
- Check that the icon is a valid PNG image
- Run icon generation: `flutter pub run flutter_launcher_icons`

---

## 🔒 Security & Privacy

- **HTTPS**: All communications use secure HTTPS connections
- **Local-First Storage**: Patient and Apple Health data are stored locally in SQLite; nothing is sent to external servers unless you explicitly add that behavior
- **FHIR Compliance**: Follows FHIR security best practices
- **Session Management**: Secure session handling with MCP server

---

## 🛣️ Roadmap

### Planned Features

- [ ] Patient search and filtering
- [ ] Add/edit patient records
- [ ] Medical history view
- [ ] Prescription management
- [ ] Lab results display
- [ ] Offline data caching
- [ ] Biometric authentication
- [ ] Dark mode support
- [ ] Multi-language support

---

## 🤝 Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Code Style

- Follow Dart/Flutter style guidelines
- Run `flutter analyze` before committing
- Write meaningful commit messages
- Add comments for complex logic

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 👤 Author

**Mahesh Balan**

- GitHub: [@maheshbalan](https://github.com/maheshbalan)
- Repository: [myWellWallet](https://github.com/maheshbalan/myWellWallet)

---

## 🙏 Acknowledgments

- Flutter team for the amazing framework
- FHIR community for healthcare interoperability standards
- Bauhaus movement for design inspiration
- All contributors and testers

---

## 📞 Support

For support, please open an issue in the [GitHub repository](https://github.com/maheshbalan/myWellWallet/issues).

---

<div align="center">

**Built with ❤️ using Flutter**

[⭐ Star this repo](https://github.com/maheshbalan/myWellWallet) if you find it helpful!

</div>
