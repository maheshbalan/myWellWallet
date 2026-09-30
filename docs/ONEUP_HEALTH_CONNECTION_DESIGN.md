# Connecting MyWellWallet to 1upHealth

Design only. No client credentials, tokens, or production access are part of this document.

The call sequence, registered redirect URL, and iOS callback setup are in [ONEUP_HEALTH_TECHNICAL_DESIGN.md](ONEUP_HEALTH_TECHNICAL_DESIGN.md).

Apple Health stays as it is. 1upHealth replaces the FHIR MCP server as the source of clinical and claims records.

## 1. What we are connecting to

MyWellWallet is a patient wallet. The matching 1up product is **Patient Access**: a member authorizes the app, and the app reads that one member’s FHIR R4 data.

| 1up product | Fits this app? | Why |
|-------------|----------------|-----|
| **Patient Access** | Yes | Member consent, one member at a time, read-only FHIR. Sandbox uses synthetic data. Production requires a separate application to 1up. |
| Provider Access | No | Bulk data for a provider organization, client-credentials token, not a person’s wallet. |
| Payer-to-Payer | No | Payer-to-payer exchange, not a consumer app. |
| Patient Connect | No | 1up is sunsetting Patient Connect on September 30, 2026. Do not build on it. |

Sources:

- [Dev Portal overview](https://docs.1up.health/docs/dev-portal)
- [Info for third-party developers](https://docs.1up.health/docs/patient-access/dev-implementation)
- [Client credentials and OAuth 2.0](https://docs.1up.health/docs/get-started/o-auth)
- [Third-party applications](https://docs.1up.health/docs/get-started/third-party-apps)
- [Patient Connect sunset](https://docs.1up.health/docs/patient-connect)

## 2. Two sources, one wallet

Apple Health and 1up answer different questions. They stay separate until a query needs both.

| | Apple Health (already built) | 1up Patient Access (new) |
|--|------------------------------|---------------------------|
| What it is | Data on this iPhone | The member’s health-plan record |
| Examples | Glucose, heart rate, steps, blood pressure | Patient, Coverage, ExplanationOfBenefit, and whatever clinical resources that plan returns |
| How we connect | HealthKit permission in Profile | Member signs in to the plan’s 1up auth app and approves MyWellWallet |
| Where it lands | `health_*` tables, keyed by `users.id` | `fhir_patients` and `fhir_resources`, keyed by the FHIR Patient id |
| Provenance tag | `apple-health` | `1up-patient-access` |

The existing merge in `docs/INTEGRATED_HEALTH_EHR_DESIGN.md` still applies. The EHR side of that diagram stops being the MCP server and becomes 1up. Apple Health is unchanged.

```
┌──────────────────────────┐         ┌──────────────────────────┐
│  Apple HealthKit         │         │  1up Patient Access      │
│  (this iPhone)           │         │  (health plan, FHIR R4)  │
└────────────┬─────────────┘         └────────────┬─────────────┘
             │ Connect + Sync now                 │ Connect health plan
             ▼                                    ▼
┌──────────────────────────┐         ┌──────────────────────────┐
│  health_* tables         │         │  fhir_patients           │
│  user_id                 │         │  fhir_resources          │
└────────────┬─────────────┘         └────────────┬─────────────┘
             │                                    │
             └──────────────┬─────────────────────┘
                            ▼
                 LocalQueryService
                 dataSources:
                   apple-health
                   1up-patient-access
                            ▼
                 Home chat / Health screens
```

Device vitals stay on Apple Health even after 1up is connected. A plan may also return Observations or labs. Those are stored as FHIR with the 1up tag, not written into the Apple Health tables.

## 3. Sandbox first, production later

### Sandbox (what we build first)

1. In the [1up Dev Portal](https://docs.1up.health/docs/dev-portal), create a **sandbox client**. Access type is Patient Access. Register a redirect URL.
2. Email `payer-patient-access@1up.health` with the company name, a short description of MyWellWallet, and the sandbox `client_id`, and ask them to sync the app to the demo environment. Creating the client is not enough; 1up has to copy it into the demo auth app.
3. The member who connects is the published synthetic member, entered in 1up’s demo auth app (not stored in our repo):

   - First name John, last name Allen
   - Birthdate 10/19/1950
   - Plan member ID 123456789123
   - Zip 02114

4. Pull that member’s FHIR bundle into the local database and show it in the app.
5. Record a screen capture of that flow. 1up requires it for production.

### Production (later, not in the first build)

Email `cms-prod-access@1up.health` only after the sandbox flow works in the real UI. 1up asks for a privacy and security attestation, the screen recording, terms, privacy policy, logo, support email, and whether the app should be offered to one plan or to their plan network. Until that approval, the app talks only to the demo hosts below.

Demo hosts from 1up’s third-party developer guide:

| Step | URL |
|------|-----|
| Member authorization | `https://auth.1uphealthdemo.com/oauth2/authorize/test` |
| Token | `https://auth.1uphealthdemo.com/oauth2/token` |
| FHIR R4 | `https://api.1uphealthdemo.com/r4/` |

Every plan supports at least `Patient`, `Coverage`, `ExplanationOfBenefit`, `Organization`, `Practitioner`, and `Location`. Clinical resources such as `Observation` and `MedicationRequest` are included only when that plan publishes them. The sandbox sync should request the minimum set, then store any extra resource types the server returns.

Supported scopes: `patient/*.read`, `launch/patient`, and `openid`. Access is read-only and limited to the member who just consented.

## 4. Connection flow

The iPhone opens 1up in `ASWebAuthenticationSession` so the secret is not typed into a WebView we control, and so the callback returns to the app.

```
Profile  →  Connect health plan
                │
                ▼
     ASWebAuthenticationSession
     GET auth.1uphealthdemo.com/oauth2/authorize/test
         ?client_id=...
         &redirect_uri=mywellwallet://1up/callback
         &scope=patient/*.read launch/patient openid
                │
                ▼
     Demo auth app. User verifies as the test member
     and approves MyWellWallet.
                │
                ▼
     App receives ?code=...   (code expires in 5 minutes)
                │
                ▼
     POST auth.1uphealthdemo.com/oauth2/token
         grant_type=authorization_code
         client_id, client_secret, code
                │
                ▼
     access_token
                │
                ▼
     GET api.1uphealthdemo.com/r4/Patient
     and the other resource types
                │
                ▼
     Save into fhir_patients / fhir_resources
     tag meta.tag code = 1up-patient-access
```

Redirect URL registered in the Dev Portal must match exactly, including the scheme. For the sandbox build that is a custom scheme, `mywellwallet://1up/callback`, declared in the iOS project. A universal https link can replace it before production if 1up or App Review requires it.

The authorization `code` is single-use and lasts five minutes. Exchange it immediately. Do not log the code, the access token, or the client secret.

1up’s published Patient Access example uses `grant_type=authorization_code` and does not document a refresh URL. Store `expires_in` when the token response includes it. When the token is missing or expired, Profile shows **Reconnect** and the member runs the auth app again. Do not invent a refresh call.

### Where the client secret lives

1up’s token request requires `client_secret`. A secret compiled into the iPhone app can be extracted. For the sandbox spike, the secret stays in a local config file that is gitignored, the same way other developer keys are kept off GitHub. Before any production client exists, the token exchange moves to a small backend the phone calls, and the secret never ships in the app. The phone still holds only the member’s access token, in the Keychain, not in SQLite.

## 5. What happens to the MCP server

The MCP FHIR gateway is how **Fetch Data** fills `fhir_resources` today. That path is turned off in the UI when 1up sandbox mode is on.

- The bottom nav item **Fetch Data** is hidden.
- Startup no longer blocks on `MCPClient.initialize()`.
- Profile gains **Health plan** next to the existing **Apple Health** card: Connect, last synced, and Sync now.
- Home chat and Health screens keep reading the local database. They do not call MCP or 1up on each question.
- The MCP client code can remain in the tree behind the flag until the sandbox sync is proven, then it is removed.

Apple Health’s Profile card, HealthKit permission, and `health_*` tables are not part of this cutover.

## 6. Local storage

Reuse the tables in `docs/SQLITE_SCHEMA.md`.

- `fhir_patients.fhir_bundle` stores the Patient resource returned by 1up.
- `fhir_resources` stores each returned resource. `patient_id` is the FHIR Patient id from that bundle, not `users.id`.
- Each resource JSON gets a provenance tag so queries can tell the sources apart:

```json
"meta": {
  "source": "https://1up.health",
  "tag": [{ "system": "urn:mywellwallet:provenance", "code": "1up-patient-access" }]
}
```

- A sync replaces the previous 1up rows for that patient. It does not delete `health_*` rows.
- Query plans use `dataSources: ["1up-patient-access", "apple-health"]`. The old `ehr-fhir` source name is retired with the MCP path.

Apple rows stay keyed by `users.id`. 1up rows stay keyed by FHIR Patient id. The app already has one local profile; the sync records the link between that profile and the Patient id it just downloaded. Queries must not mix two users.

## 7. What the first build includes

1. Sandbox client in the Dev Portal, redirect URL registered, demo sync requested from 1up.
2. Profile action **Connect health plan**, using the demo auth URL and the synthetic member.
3. Token exchange and a one-shot read of Patient plus the minimum resource set, plus any other types the demo server returns.
4. Save into the existing FHIR tables with the 1up provenance tag.
5. Hide Fetch Data and stop requiring MCP at launch.
6. Leave Apple Health connect, sync, and the Health tab as they are.
7. Confirm a home question can see the stored 1up Patient or Coverage record and still see Apple Health vitals when those exist.

Out of scope until the sandbox path works on the phone: production credentials, a token-exchange backend, writing data back to 1up, and multiple health plans on one profile.

## 8. Production checklist (do not start until sandbox is visible in the app)

From 1up’s third-party application process:

- Privacy and security attestation
- Screen recording of MyWellWallet connecting to the demo plan and showing the synthetic record
- Terms of service and privacy policy
- App logo, user support email, and a security contact
- Short description of who the app is for
- Decision: one 1up payer customer, or their broader plan network

After 1up accepts that request, they sync the production client id and redirect URI to the plan environments. The app then points at those hosts instead of `1uphealthdemo.com`. The member flow is the same shape: plan auth app, approval, FHIR read, local store. Apple Health is still a separate connection on the phone.
