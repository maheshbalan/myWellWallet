# App Store signing (including RAG .md assets)

The app bundles RAG docs (`docs/*.md`) as Flutter assets. For App Store validation to pass, the **entire app bundle** (including those files) must be signed with a **distribution** certificate. You don’t sign the .md files separately—Xcode signs the whole app.

## 1. Use distribution signing

- In **Xcode**: open `ios/Runner.xcworkspace`.
- Select the **Runner** target → **Signing & Capabilities**.
- For **Release**:
  - **Team**: your Apple Developer team.
  - Either **Automatically manage signing** (Xcode will create an App Store profile) or a manual **Distribution** provisioning profile for App Store.
- Do **not** use a Development or Ad Hoc certificate for the build you upload to App Store Connect.

## 2. Clean and build so everything is signed

Do a full clean so no old artifacts are left, then build the IPA with Flutter so assets (including `docs/*.md`) are inside the app before signing:

```bash
# From project root
flutter clean
rm -rf build ios/build
flutter pub get
flutter build ipa
```

- **Important:** Use **Release**. Do not build for Simulator or Debug when creating the build you upload.
- The signed `.ipa` is under `build/ios/ipa/`. Upload that file (e.g. via **Transporter** or **Xcode → Window → Organizer → Distribute App** after dragging the IPA in or using “Distribute App” from an archive).

## 3. If you prefer to archive from Xcode

1. In Xcode: **Product → Scheme → Runner**, run destination **Any iOS Device (arm64)**.
2. **Product → Clean Build Folder** (Shift+Cmd+K).
3. **Product → Archive**.
4. In the Organizer, select the new archive → **Distribute App** → **App Store Connect** → **Upload**.

This uses the same signing and bundle contents; the important part is that the build is **Release** and uses a **distribution** profile so every file in the app (including `Runner.app/Frameworks/App.framework/flutter_assets/docs/*.md`) is signed.

## 4. If “not properly signed” still appears

- Confirm the build you uploaded was **Release** and **distribution-signed** (not Development/Ad Hoc).
- Try again with a completely clean state:
  - Close Xcode.
  - Delete `build/` and `ios/build/`.
  - In Xcode: **Product → Clean Build Folder**, then **Product → Archive** and upload again.

If it still fails, the next step is to ensure no build script or step modifies `App.framework` or `flutter_assets` after the signing step; we can add a check or adjust the build phases if needed.
