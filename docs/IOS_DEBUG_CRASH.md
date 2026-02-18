# iOS Debug crash: "Unable to flip between RX and RW memory protection"

## What you see
- App crashes immediately on physical iPhone with SIGABRT.
- Console: `virtual_memory_posix.cc: error: Unable to flip between RX and RW memory protection on pages` during `Dart_Initialize`.

## Why it happens
- **Debug** builds use the Dart VM in JIT mode, which needs to flip memory between executable and writable.
- On iOS 18.4+ / iOS 26, the OS blocks this for security, so the VM fails to start.

## What to do

### Option A: Run in Release on device (recommended for testing on phone)
- **Xcode:** Choose the **Runner** scheme, then set run configuration to **Release** (Product → Scheme → Edit Scheme → Run → Build Configuration → **Release**). Then Run (⌘R).
- **Terminal:**  
  `cd /Users/veenamahesh/myWellWallet && flutter run --release -d 00008150-001D39123A7A401C`

You lose hot reload and debugger on device, but the app runs.

### Option B: Debug on Simulator
- Use an iOS Simulator for day-to-day debug (no JIT restriction there).
- Use Release on the physical device when you need to test on the phone.

### Option C: Upgrade Flutter
- Newer Flutter versions may improve this; try `flutter upgrade` and test debug on device again.
