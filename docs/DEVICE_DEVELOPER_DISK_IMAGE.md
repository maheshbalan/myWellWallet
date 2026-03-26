# Fix: "Developer disk image could not be mounted" (iOS 26.3 / iPhone 17)

Your iPhone shows **iOS 26.3** but Xcode’s device support on this Mac only has images up to **16.4**. The mount/unmount error usually means the right disk image for 26.3 isn’t there or failed to install.

## Try these in order

### 1. Reinstall Xcode system resources

In **Terminal** (may need to quit Xcode first):

```bash
sudo installer -pkg /Applications/Xcode.app/Contents/Resources/Packages/XcodeSystemResources.pkg -target /
```

Then **restart your Mac**, reconnect the iPhone (unlocked, Trust if asked), and open **Xcode → Window → Devices and Simulators** again.

### 2. Restart everything

- Quit **Xcode** completely.
- **Restart the iPhone**.
- **Restart the Mac**.
- Connect the iPhone (unlocked), tap **Trust** if prompted.
- Open Xcode and check Devices and Simulators again.

### 3. Update Xcode

- **Xcode → Check for Updates** (or App Store).
- Install any update (e.g. 26.3.1). Newer builds often add or fix support for the latest iOS version.

### 4. Use the iOS Simulator (workaround)

You can run and debug the app **without the physical device**:

1. In Xcode: **Window → Devices and Simulators → Simulators**.
2. Pick an **iPhone** simulator with **iOS 26.x** (e.g. “iPhone 16” with iOS 26.2) or the latest listed.
3. From your project folder in Terminal:
   ```bash
   flutter run -d "iPhone 16"   # or the exact simulator name from `flutter devices`
   ```
4. Or in Xcode: open `ios/Runner.xcworkspace`, set the run destination to that simulator, then **Product → Run**.

The app will run in the simulator. Some features (e.g. real Health data, device-only sensors) won’t be there, but you can develop and test most of the app.

### 5. If the error persists

- Check **Apple Developer Forums** for “developer disk image could not be mounted” with your exact Xcode and iOS versions.
- Ensure the iPhone is on **Wi‑Fi** and has **Settings → General → Software Update** up to date (sometimes a point update fixes pairing).
- As a last resort, some users fix similar issues by clearing the developer disk image cache (requires sudo and may force re-download of images); only do this if you’re comfortable with the risk and have a backup.

---

**Summary:** The message appears because the developer disk image for **iOS 26.3** isn’t mounting. Reinstalling system resources, restarting, and updating Xcode often fix it. Until then, use the **iOS Simulator** to run the app.
