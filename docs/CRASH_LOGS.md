# Capturing crash logs (iOS / MyWellWallet)

When the app loads but then crashes, you need the **console output** or **crash report** to see the exception and stack trace.

## Option 1: Run from terminal (recommended)

1. Connect your iPhone with USB and unlock it.
2. In the project root run:
   ```bash
   flutter run -d <device_id>
   ```
   To see device id: `flutter devices`.
3. Use the app until it crashes. The **terminal will print** the Dart exception and stack trace (and any `debugPrint` / `LogService` output).
4. Copy the last 50–100 lines from the terminal and share them for debugging.

## Option 2: Run from Xcode

1. Open the iOS project:
   ```bash
   open ios/Runner.xcworkspace
   ```
2. Select your physical iPhone as the run destination (top toolbar).
3. **Product → Run** (or ⌘R).
4. When the app crashes, the **Xcode console** (bottom panel) shows:
   - Native crash (e.g. `SIGABRT`, `EXC_BAD_ACCESS`) and thread backtrace
   - Any Dart/Flutter exception and stack
   - `LogService.log()` output (via `debugPrint`)
5. Copy the console output from the moment the crash happens and share it.

## Option 3: Device crash reports (synced to Mac)

After a crash, the device may sync a report to your Mac:

- **Location**: `~/Library/Logs/DiagnosticReports/`
- Look for files named like `Runner-*.ips` or `mywellwallet-*.ips` (date/time in the name).
- Open the `.ips` file in a text editor to see the crash thread and stack.

If you don’t see a Runner/mywellwallet report, use Option 1 or 2 so the crash happens while the app is attached to the debugger.

## In-app logs

The app writes logs to a file via `LogService` (path is in app support directory). To read it:

- **From Xcode**: Run the app, then use **Window → Devices and Simulators**, select the device, select the app, and download the container; the log file is inside the container under `Library/Application Support/logs/app.log`.
- Or trigger the crash while running with `flutter run` or Xcode so the exception is in the console; that’s usually enough to diagnose.

## What was changed to reduce crashes

- **Startup**: Gemma model initialization no longer blocks the main screen; it runs in the background so the UI can show first.
- **Home screen**: Download progress and streaming response handlers check `mounted` before using `context` or calling `setState`, to avoid “setState after dispose” or using context after the widget is gone.

If the crash is in **native code** (e.g. llamadart / GGUF loading on iOS), the stack trace in Xcode will point to the C++/Metal layer; sharing that trace is needed to fix or work around it (e.g. skipping Gemma on iOS until the native library is fixed).
