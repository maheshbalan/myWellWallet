# Apple Health (HealthKit) Setup

MyWellWallet can sync **glucose (CGM)**, **heart rate**, **steps**, and **blood pressure** from Apple Health on iPhone for a diabetes & heart-health dashboard.

## 1. Info.plist

The project already includes:

- `NSHealthShareUsageDescription` – read health data
- `NSHealthUpdateUsageDescription` – write health data (optional)

## 2. HealthKit entitlement

The project includes **Runner/Runner.entitlements** with the HealthKit entitlement so the app can request Health access and appear under **Settings → Privacy & Security → Health**.

If the app still does not appear under Health after tapping "Connect to Apple Health", add the capability in Xcode so your provisioning profile includes HealthKit:

1. Open the iOS project in Xcode: **Right-click `ios` folder → Open in Xcode**
2. Select the **Runner** target.
3. Open the **Signing & Capabilities** tab.
4. Click **+ Capability** and add **HealthKit** (this updates your App ID and provisioning profile).
5. Rebuild and run the app, then try **Connect to Apple Health** again.

## 3. In the app (iPhone)

1. Open **Profile**.
2. In the **Apple Health** section, choose a **Sync interval** (e.g. every 24 hours).
3. Tap **Connect to Apple Health** and allow the requested health data types.
4. After the first sync, use **View Health** (or the **Health** tab) to see the dashboard and detail screens (glucose, heart rate, steps, blood pressure).

## 4. Sync interval

- **Every 6 hours** / **Every 12 hours** / **Every 24 hours** / **Every week**  
  These control how often the app will re-fetch from Apple Health when you open the app or tap **Sync now** in Profile.  
  Automatic background sync depends on iOS; the interval is used when the user triggers a sync or when the app checks “is sync due?” on launch.

## 5. Data stored locally

Synced data is stored in the app’s SQLite database (see `SQLITE_SCHEMA.md` – Apple Health tables). It is not sent to a server unless you add that behavior.

## 6. Android

Apple Health is **iOS only**. On Android, the Health screen shows a message that Apple Health is available only on iPhone. Future versions could support Google Health Connect with a similar flow.
