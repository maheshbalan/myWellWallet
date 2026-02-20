# iOS Debug crash: "Unable to flip between RX and RW memory protection"

**Always run the app in Release (or Profile) when using a physical iPhone.** Debug builds will crash.

## What you see
- App crashes immediately on physical iPhone with SIGABRT.
- Console: `virtual_memory_posix.cc: error: Unable to flip between RX and RW memory protection on pages` during `Dart_Initialize`.

## Why it happens
- **Debug** builds use the Dart VM in JIT mode, which needs to flip memory between executable (RX) and writable (RW).
- iOS on physical devices blocks this for security, so the VM fails to start.

## What to do

### Option A: Run in Release on device (required for physical iPhone)
- **Xcode:** Product → Scheme → Edit Scheme → Run → Build Configuration → **Release**. Then **Product → Clean Build Folder** (⇧⌘K), then Run (⌘R). **Delete the app from the iPhone** first if you previously installed a Debug build, so Xcode installs a fresh Release build.
- **Terminal (recommended):**  
  `flutter run --release -d <device_id>`  
  Example: `flutter run --release -d 00008150-001D39123A7A401C`  
  List devices: `flutter devices`

**If you still see the "Unable to flip..." crash with Release:** The project’s iOS Run Script now forces `CONFIGURATION=Release` when building for a physical device (`iphoneos`), so the Flutter build is always Release when targeting the phone. Do a **Clean Build Folder** in Xcode, **delete the app from the iPhone**, then build and run again.

You lose hot reload and debugger on device, but the app runs.

### Option B: Debug on Simulator
- Use an iOS Simulator for day-to-day debug (no JIT restriction there).
- Use Release on the physical device when you need to test on the phone.

### Option C: Upgrade Flutter
- Newer Flutter versions may improve this; try `flutter upgrade` and test debug on device again.
