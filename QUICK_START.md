# MyWellWallet - Quick Start Guide

## ✅ Project Created Successfully!

Your Flutter app is ready at: `~/myWellWallet`

## 🚀 Quick Start

1. **Navigate to the project:**
   ```bash
   cd ~/myWellWallet
   ```

2. **Get dependencies:**
   ```bash
   flutter pub get
   ```

3. **Generate JSON serialization (if needed):**
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

4. **Run the app:**
   ```bash
   flutter run
   ```

## 📱 What's Included

### Screens
- **Home Screen** - Welcome page with navigation
- **Patient List** - Shows all patients from FHIR server
- **Patient Details** - Comprehensive patient information view

### Features
- ✅ HTTP/SSE MCP Client integration
- ✅ Patient listing and details
- ✅ Modern Material Design 3 UI
- ✅ Error handling and loading states
- ✅ Pull-to-refresh functionality

## 🔧 Configuration

The app connects to:
```
https://mcp-fhir-server-maheshbalan1.replit.app
```

To change this, edit `lib/main.dart` line ~25.

## ⚠️ Important Notes

### HTTP/SSE Session Management

The current FHIR MCP Server requires session management for HTTP/SSE. The client implementation handles:
- Session initialization
- Request/response parsing
- Error handling

**Note**: If you encounter "Missing session ID" errors, the server may need to be configured for stateless requests, or you may need to implement persistent SSE connection handling.

### Testing

1. **Ensure the MCP server is running** at the configured URL
2. **Test the connection** by running the app and navigating to "View Patients"
3. **Check logs** if connection fails

## 📂 Project Structure

```
lib/
├── main.dart              # App entry & routing
├── models/                # Patient data models
├── services/              # MCP client service
├── providers/             # State management
├── screens/               # UI screens
└── widgets/               # Reusable components
```

## 🎨 UI Features

- Material Design 3
- Clean, modern interface
- Responsive layouts
- Loading indicators
- Error messages
- Patient cards with avatars
- Detailed information sections

## 🔄 Next Steps

1. **Test the app** once your server is deployed
2. **Customize UI** based on your design requirements
3. **Add features**:
   - Search functionality
   - Patient filtering
   - Add/edit capabilities
   - Medical history
   - Lab results
   - Prescriptions

## 📚 Documentation

- See `SETUP.md` for detailed setup instructions
- See `README.md` for project overview

## 🐛 Troubleshooting

**Build errors?**
```bash
flutter clean
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
```

**Connection issues?**
- Verify server URL is correct
- Check server is running
- Review network connectivity

**JSON errors?**
- Ensure `patient.g.dart` exists
- Run build_runner again

## 📞 Support

For issues with:
- **MCP Server**: Check server logs and configuration
- **Flutter**: Run `flutter doctor` to check setup
- **Dependencies**: Run `flutter pub get`

