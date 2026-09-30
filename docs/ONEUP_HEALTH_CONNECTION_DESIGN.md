# Connecting MyWellWallet to 1upHealth

Design only. No client credentials, tokens, or production access are part of this document.

The call sequence, registered redirect URL, and iOS callback setup are in [ONEUP_HEALTH_TECHNICAL_DESIGN.md](ONEUP_HEALTH_TECHNICAL_DESIGN.md).

Apple Health stays as it is. Clinical records come from either the FHIR MCP server or 1up Patient Access. A Profile toggle picks one. The MCP client stays in the app. When production 1up is turned on, the toggle is locked to 1up and is no longer shown.

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

The existing merge in `docs/INTEGRATED_HEALTH_EHR_DESIGN.md` still applies. Apple Health is always on. The clinical side is whichever source the toggle has selected. MCP rows keep the `ehr-fhir` tag. 1up rows use `1up-patient-access`. A query reads Apple Health plus the active clinical tag, not both clinical tags at once.

```
┌──────────────────────────┐
│  Apple HealthKit         │
│  always on               │
└────────────┬─────────────┘
             │
             ▼
┌──────────────────────────┐      Profile toggle (one clinical source)
│  health_* tables         │      ┌─────────────┬──────────────────┐
│  user_id                 │      │ MCP server  │ 1up Patient Access │
└────────────┬─────────────┘      └──────┬──────┴────────┬─────────┘
             │                           │               │
             │                           ▼               ▼
             │                    fhir_resources   fhir_resources
             │                    tag ehr-fhir     tag 1up-patient-access
             └──────────────┬────────────┬───────────────┘
                            ▼            ▼
                 LocalQueryService reads apple-health
                 plus the tag for the selected source
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

## 5. MCP server and 1up are a toggle

The MCP FHIR gateway stays. It is the clinical source we already have, and it may become the main way the wallet talks to provider systems later. 1up is the other clinical source, used for health-plan records. The member uses one of them at a time. Apple Health is not on this toggle.

Profile shows **Clinical records** with two choices:

| Choice | What the UI does | What startup does |
|--------|------------------|-------------------|
| **MCP server** | **Fetch Data** stays in the bottom nav. The 1up **Connect health plan** card is hidden. | `MCPClient.initialize()` runs, as it does today. 1up is not called. |
| **1upHealth** | **Fetch Data** is hidden. Profile shows **Health plan** next to **Apple Health**: Connect, last synced, and Sync now. | Startup does not call MCP, so a down MCP host does not block the app. |

The choice is stored on the device as `clinical_record_source` = `mcp` or `oneup`. The default is `mcp`, so a build with the toggle still behaves as the app does today until someone switches it.

Switching does not delete the other source’s rows. Queries use `apple-health` plus either `ehr-fhir` or `1up-patient-access`, matching the toggle. Home chat still reads the local database. It does not call MCP or 1up on each question.

### Production lock

When we are ready for production 1up, the toggle is compiled out of the UI. The stored source is forced to `oneup`. There is no switch to turn 1up off. **Fetch Data** stays unlinked. `MCPClient` and the fetch screen remain in the project so a later provider-system path can turn them back on without rewriting them. That later change is another explicit build. It is not a setting the member can flip.

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

- A 1up sync replaces the previous 1up rows for that patient. It does not delete `health_*` rows or rows tagged `ehr-fhir`.
- While the toggle is `oneup`, query plans use `dataSources: ["1up-patient-access", "apple-health"]`. While it is `mcp`, they use `dataSources: ["ehr-fhir", "apple-health"]`.

Apple rows stay keyed by `users.id`. 1up rows stay keyed by FHIR Patient id. The app already has one local profile; the sync records the link between that profile and the Patient id it just downloaded. Queries must not mix two users.

## 7. What the first build includes

1. Sandbox client in the Dev Portal, redirect URL registered, demo sync requested from 1up.
2. Profile action **Connect health plan**, using the demo auth URL and the synthetic member.
3. Token exchange and a one-shot read of Patient plus the minimum resource set, plus any other types the demo server returns.
4. Save into the existing FHIR tables with the 1up provenance tag.
5. Profile toggle **Clinical records**: MCP server or 1upHealth. Default MCP. 1up mode hides Fetch Data and skips MCP at startup. MCP mode leaves Fetch Data as it is.
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

After 1up accepts that request, they sync the production client id and redirect URI to the plan environments. The app then points at those hosts instead of `1uphealthdemo.com`. That production build locks the clinical-records toggle to 1up and removes the switch from Profile. The MCP client stays in the codebase. The member flow is the same shape: plan auth app, approval, FHIR read, local store. Apple Health is still a separate connection on the phone.
