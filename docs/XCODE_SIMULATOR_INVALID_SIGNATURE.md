# Fix: Xcode Simulator "Invalid Signature" (SimDiskImageErrorDomain -67061)

When downloading a simulator runtime (e.g. iOS 26.3.1), Xcode can fail with:

- **-67061 invalid signature (code or signature have been modified)**
- **Domain: SimDiskImageErrorDomain, Code: 5**

That usually means the download was corrupted or modified (e.g. interrupted, antivirus, or cache).

---

## Try these in order

### 1. Remove the failed runtime and retry

1. Quit **Xcode** completely.
2. Open **Xcode** → **Settings…** (or **Preferences…**) → **Platforms** tab.
3. In the list, find **iOS 26.3.1** (or the one that was downloading).
4. **Right‑click** it → **Delete** / **Remove** (if the option is there). This removes the broken/incomplete copy.
5. Close Settings and try **Get** / **Download** again for that runtime.

---

### 2. Clear the simulator download cache and retry

Sometimes the bad file is in the cache. With **Xcode quit**:

```bash
# Kill the simulator service so nothing is using the files
sudo killall -9 com.apple.CoreSimulator.CoreSimulatorService 2>/dev/null

# Clear Xcode’s download caches for simulator assets (optional; safe)
rm -rf ~/Library/Caches/com.apple.dt.Xcode/Downloads/* 2>/dev/null
rm -rf ~/Library/Developer/Xcode/iOS\ DeviceSupport/* 2>/dev/null
```

Then **restart your Mac**, open Xcode, go to **Settings → Platforms**, and try downloading the 26.3.1 simulator again.

---

### 3. Use an existing simulator (no 26.3.1 needed)

You already have **iOS 26.1** and **iOS 26.2** runtimes. You can run your app on those:

- In Xcode: **Window → Devices and Simulators → Simulators** → pick an **iPhone** with **iOS 26.1** or **26.2**.
- Or in Terminal:
  ```bash
  flutter devices
  flutter run -d "iPhone 16"   # or whatever simulator name you see
  ```

You don’t need 26.3.1 to develop; 26.2 is enough for most testing.

---

### 4. If you really need 26.3.1: manual download

1. Go to [developer.apple.com/download/all/](https://developer.apple.com/download/all/) and sign in.
2. Search for **“iOS 26.3.1 Simulator”** (or the exact name Apple uses) and download the **.dmg**.
3. In Terminal:
   ```bash
   xcrun simctl runtime add ~/Downloads/iOS_26.3_Simulator_Runtime.dmg
   ```
   (Use the actual filename you downloaded.)
4. Restart Xcode; the new runtime should appear under **Settings → Platforms** and in the simulator list.

---

### 5. Security software

If you use **antivirus** or **security tools** that scan or modify files as they’re written, temporarily exclude:

- `/Applications/Xcode.app`
- `~/Library/Developer`
- `~/Library/Caches/com.apple.dt.Xcode`

Then try the download again. macOS **XProtect** has also been known to interfere with simulator disk images; keeping macOS and Xcode up to date can help.

---

**Summary:** Remove the failed 26.3.1 runtime in **Xcode → Settings → Platforms**, clear caches and restart if needed, and retry the download. For daily development, using the existing **26.1 or 26.2** simulator is enough.
