# MyWellWallet ↔ 1upHealth technical design

Companion to [ONEUP_HEALTH_CONNECTION_DESIGN.md](ONEUP_HEALTH_CONNECTION_DESIGN.md). This file is the contract for the sandbox client: what to type into the 1up app definition, and the exact sequence the iPhone runs after **Connect health plan**.

No `client_id`, `client_secret`, or access token belongs in git.

## 1. Value to enter in the 1up app definition

In the [1up Dev Portal](https://docs.1up.health/docs/dev-portal), **Create a Client** with:

| Portal field | Value |
|--------------|--------|
| Access type | Patient Access |
| Client name | `MyWellWallet` |
| Redirect URL | `mywellwallet://1up/callback` |

That redirect string is copied exactly. It includes the scheme `mywellwallet://`, it has no trailing slash, and it has no query string. 1up requires the protocol on the redirect URL. The same string is the OAuth `redirect_uri`. When it is placed on the authorize request it is percent-encoded as `mywellwallet%3A%2F%2F1up%2Fcallback`. The portal field itself is **not** percent-encoded.

After the client exists, copy `client_id` and `client_secret` from **Sandbox Clients** into a local gitignored config. Then email `payer-patient-access@1up.health` and ask them to sync that `client_id` to the demo environment. The authorize URL below does not work until that sync is done.

Do not register `http://localhost`, an `https://` page we do not host, or a second redirect, for the sandbox client. One redirect keeps the match unambiguous.

## 2. iOS callback that receives that URL

The app bundle id is `com.mywellwallet.mywellwallet`. `ios/Runner/Info.plist` does not declare a URL scheme yet. The sandbox build adds:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>com.mywellwallet.mywellwallet</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>mywellwallet</string>
    </array>
  </dict>
</array>
```

The scheme is only `mywellwallet`. The path `/1up/callback` is part of the redirect URL, not part of the scheme.

The connect button opens `ASWebAuthenticationSession` with:

- `callbackURLScheme`: `mywellwallet`
- URL: the authorize URL in section 4
- `prefersEphemeralWebBrowserSession`: false, so the member can finish the demo identity form

The session succeeds only when 1up redirects to a URL whose scheme is `mywellwallet`. That is why the portal redirect and this scheme must be the same word.

## 3. Components

| Piece | Role |
|-------|------|
| Profile **Connect health plan** | Starts the flow. Does not collect the test member’s name or member id. Those are typed into 1up’s demo page. |
| `OneUpAuthClient` | Builds the authorize URL, runs the web session, checks `state`, exchanges the code. |
| `OneUpFhirClient` | `GET`s FHIR R4 with `Authorization: Bearer`. |
| `OneUpSyncService` | Orders auth, then fetch, then local save. |
| Keychain | Stores `access_token` and `expires_in` for this profile. Not SQLite. |
| `DatabaseService` | Writes `fhir_patients` and `fhir_resources`, same tables the MCP fetch uses today. |
| Apple Health services | Not called from this flow. |

Startup does not call 1up. A sync runs only from **Connect health plan** or **Sync now**.

## 4. Authorize request

Sandbox URL, as published by 1up, plus a `state` value we generate so a stale callback cannot be reused:

```
GET https://auth.1uphealthdemo.com/oauth2/authorize/test
  ?client_id={CLIENT_ID}
  &redirect_uri=mywellwallet%3A%2F%2F1up%2Fcallback
  &state={STATE}
```

`STATE` is 32 bytes from a secure random generator, hex-encoded, held in memory until the session returns. It is not written to disk.

1up’s published demo link requires `client_id` and `redirect_uri` only. `state` is added for the client check in section 5. Scopes 1up documents for Patient Access are `patient/*.read`, `launch/patient`, and `openid`. The first sandbox attempt does **not** send `scope`, because the published demo URL does not include it and the demo auth app already binds the token to the member who just signed in. If a later test shows the token is missing read access, add:

```
&scope=patient%2F*.read%20launch%2Fpatient%20openid
```

`patient/*.read` must be encoded as `patient%2F*.read`. A literal slash in the query would be wrong.

## 5. Logic sequence

```
Profile.ConnectHealthPlan
        │
        ▼
OneUpSyncService.connect()
        │
        ├─1─ generate state, keep it in the auth session
        │
        ├─2─ ASWebAuthenticationSession
        │       opens the authorize URL in section 4
        │
        ▼
1up demo auth app (not our UI)
        member taps "Click here to confirm identity"
        enters the synthetic member from the product design
        approves MyWellWallet
        │
        ▼
1up redirects the browser to
        mywellwallet://1up/callback?code={CODE}&state={STATE}
        │
        ▼
iOS delivers that URL to the waiting session
        │
        ├─3─ if query has error → stop, show error_description
        ├─4─ if state ≠ session state → stop, discard the code
        ├─5─ if code is missing → stop
        │
        ├─6─ POST https://auth.1uphealthdemo.com/oauth2/token
        │       Content-Type: application/x-www-form-urlencoded
        │       client_id={CLIENT_ID}
        │       client_secret={CLIENT_SECRET}
        │       grant_type=authorization_code
        │       code={CODE}
        │
        │     The code expires in 5 minutes and is single-use.
        │     Step 6 runs immediately after step 5.
        │
        ├─7─ read access_token
        │     if expires_in is present, record expiry = now + expires_in
        │     write the token to the Keychain
        │     drop the code from memory
        │
        ├─8─ FHIR reads, section 6, using the bearer token
        │
        └─9─ replace this profile’s previous 1up rows
              set Profile status to connected and last synced
```

Canceling the web sheet returns the user to Profile with no token change and no database write.

**Sync now** skips steps 1–5 when the Keychain has a token and `expires_in` has not passed. It starts at step 8. If the FHIR call returns 401, it deletes that token and Profile shows **Reconnect**, which runs the full sequence again. 1up’s Patient Access guide does not document a refresh-token URL, so this client does not call one.

## 6. FHIR reads

Base URL: `https://api.1uphealthdemo.com/r4/`

Header on every call: `Authorization: Bearer {access_token}` and `Accept: application/fhir+json`.

The token is already limited to the member who consented, so these calls are not searched by name or member id.

Required, in order. A non-success on `Patient` aborts the sync and does not delete the previous local rows.

1. `GET /r4/Patient`
2. Take `Patient.id` from the first entry in the bundle (or the Patient resource itself if the server returns one resource).
3. `GET /r4/Coverage`
4. `GET /r4/ExplanationOfBenefit`
5. `GET /r4/Organization`
6. `GET /r4/Practitioner`
7. `GET /r4/Location`

Then try, and ignore 404 or an OperationOutcome that says the type is not supported:

`Observation`, `Condition`, `MedicationRequest`, `AllergyIntolerance`, `Procedure`, `DiagnosticReport`, `Encounter`, `Immunization`.

Each success is a FHIR Bundle or a single resource. Every entry is stored. Before insert, set:

```json
"meta": {
  "source": "https://1up.health",
  "tag": [{ "system": "urn:mywellwallet:provenance", "code": "1up-patient-access" }]
}
```

`fhir_patients.patient_id` and `fhir_resources.patient_id` are that `Patient.id`. The local `users.id` is stored beside it so a later query can join Apple Health (`health_*`.`user_id`) to this plan record. Replacing a sync deletes only rows tagged `1up-patient-access` for that patient. `health_*` rows are left alone.

Paging: if a bundle has `link.relation = next`, follow it before moving to the next resource type.

## 7. Token request and response

```
POST https://auth.1uphealthdemo.com/oauth2/token
Content-Type: application/x-www-form-urlencoded

client_id={CLIENT_ID}
&client_secret={CLIENT_SECRET}
&grant_type=authorization_code
&code={CODE}
```

Use the `access_token` string from the JSON body. Do not log the request body or the response body. `client_secret` is read from the gitignored local config for the sandbox spike. It is not a Dart constant. Before a production client exists, this POST moves off the phone so the secret is not inside the app binary. The phone would then send only the `code` to that exchanger and receive the `access_token`.

## 8. Failures

| Condition | Client behavior |
|-----------|-----------------|
| User closes the auth sheet | Stay on Profile. No write. |
| Redirect `error` | Show `error_description` or `error`. No token call. |
| `state` mismatch | Ignore the code. |
| Token HTTP error, or no `access_token` | Show the HTTP status. Leave the previous token in place if one existed. |
| `GET Patient` fails | Keep the new token so **Sync now** can retry. Keep previous FHIR rows. |
| A later required type fails | Keep Patient and any types already saved this run. Profile shows sync incomplete. |
| Optional type fails | Continue. |
| 401 on any FHIR call | Drop the token. Profile shows **Reconnect**. |

## 9. Portal checklist before the first phone test

1. Redirect URL in the sandbox client is exactly `mywellwallet://1up/callback`.
2. `Info.plist` scheme is `mywellwallet`.
3. `client_id` in the authorize URL is the sandbox client id.
4. 1up has confirmed the client is synced to `auth.1uphealthdemo.com`.
5. The phone is installed from this build, so iOS will open MyWellWallet for that scheme.
