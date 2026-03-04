# Update Summary - March 4, 2026

This update introduces full local AI integration, an enhanced RAG pipeline, and significant stability improvements to MyWellWallet.

## Key Features

### 1. Local AI Integration (Gemma 2B)
- **On-Device Inference**: Integrated `llamadart` to run the Gemma 2 2B IT model entirely on-device.
- **Platform-Aware Performance**: 
  - **Desktop (Linux/Windows)**: Uses stable CPU backend to avoid rendering conflicts.
  - **Mobile (iOS/Android)**: Supports full GPU acceleration (Metal/Vulkan) for high-speed responses.
- **Streaming & Memory**: Character-by-character response streaming and a 10-turn conversation memory for natural follow-up support.
- **Persona**: Uses official Gemma 2 Chat Templates for a friendly, professional health assistant voice.

### 2. Enhanced RAG (Retrieval-Augmented Generation)
- **Recursive Extraction**: A new "Recursive Data Finder" locates health records buried in complex nested FHIR structures.
- **Intelligent Summarization**: Automatically strips raw JSON data down to essential clinical fields (dates, test results, visit reasons) to fit within AI context limits.
- **Robust Mapping**: Improved keyword-to-resource mapping ensures queries like "Test Results" reliably fetch `DiagnosticReport` records.

### 3. App Lifecycle & Stability
- **Global Initialization**: Added a startup splash screen that ensures MCP, RAG, and User Profile services are ready before interaction.
- **Proactive Context**: Automatically warms up the FHIR Patient ID upon login or registration, preventing "Missing Context" errors in chat.
- **Account Reset**: Implemented a thorough `resetApp()` logic that wipes all local data when switching accounts.

### 4. Diagnostics
- **Persistent Logging**: All system events are now logged to a local `app.log` file.
- **In-App Log Viewer**: Access detailed system logs directly from the Home Screen menu for easier debugging.

## UI & UX Improvements
- **Chat Layout**: Repositioned the chat input to the bottom for ergonomic use.
- **Session Control**: Added a "Back" button in the chat interface to reset the session and return to the home state.
- **Feedback**: Added a real-time download progress popup for the AI model and a status "Bolt" icon.
- **Bug Fixes**: Resolved chat bubble rendering exceptions and "Tokenization failed" errors.
