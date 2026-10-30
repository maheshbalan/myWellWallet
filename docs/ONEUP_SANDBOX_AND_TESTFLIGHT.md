# 1up sandbox build and TestFlight

Version `1.5.0` (build 3) is the test build. Android is not part of this build.

## 1. Sandbox client

1. In the [1up Dev Portal](https://docs.1up.health/docs/dev-portal), create a Patient Access client named `MyWellWallet`.
2. Redirect URL, copied exactly: `mywellwallet://1up/callback`
3. Copy `config/oneup_local.example.json` to `config/oneup_local.json` and paste the sandbox client id and secret. That file stays off git.
4. Email `payer-patient-access@1up.health` and ask them to sync that client id to the demo environment. The authorize URL does not work until they confirm.

Rebuild so the secret is compiled into this binary only:

```bash
flutter run --release -d 00008150-001D39123A7A401C \
  --dart-define-from-file=config/oneup_local.json
```

Use Release on a physical iPhone. Debug crashes with the memory-protection error in `docs/IOS_DEBUG_CRASH.md`.

On the phone: Profile → Clinical records → **1up Health** → **Add a provider** → **Demo Health Plan**. Sign in on 1up’s page as the synthetic member (John Allen, DOB 10/19/1940, member id 123456789123, zip 02114). The password is not stored in the app. The token goes to the Keychain. The chart goes into `fhir_resources` tagged `1up-patient-access`.

The Fetch Data tab stays hidden while 1up is selected. Apple Health is unchanged. Switching back to **FHIR MCP server** shows Fetch Data again.

A later production build adds `--dart-define=LOCK_CLINICAL_TO_ONEUP=true`. That hides the toggle and does not start MCP. Do not use that flag for the sandbox test. Before production, the token exchange also has to move off the phone so the client secret is not inside the app.

## 2. TestFlight

This build sets `ITSAppUsesNonExemptEncryption` to false because the app uses ordinary HTTPS, not a custom cipher. App Store Connect should not ask the export-compliance question again for this binary.

From the project root, with the same local 1up file if the TestFlight build should be able to connect:

```bash
flutter clean
flutter pub get
flutter build ipa --dart-define-from-file=config/oneup_local.json
```

The signed archive is `build/ios/ipa/`. Upload it with the Transporter app, or from Xcode Organizer after **Product → Archive**, using team `95SRV94839` and an App Store distribution profile. A development profile can install on your phone and cannot be the file TestFlight accepts.

In App Store Connect, add the build to an internal TestFlight group. The first upload needs the app record `com.mywellwallet.mywellwallet` if it does not exist yet, plus the privacy policy URL and a short description. Screenshots can be the phone you already use.

Chat answers come from a SELECT that MedGemma writes against the schema. The model has to finish downloading before a question can run.
