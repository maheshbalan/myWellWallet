# MyWellWallet ↔ 1upHealth technical design

Companion to [ONEUP_HEALTH_CONNECTION_DESIGN.md](ONEUP_HEALTH_CONNECTION_DESIGN.md). This file is the contract for the sandbox client: what to type into the 1up app definition, and the exact sequence the iPhone runs after **Connect health plan**.

No `client_id`, `client_secret`, or access token belongs in git.

## 1. The flow in plain language

The member never types their health-plan password, member id, or email code into MyWellWallet. Those fields exist only on 1up’s page, or on the health plan’s own login, inside an Apple system browser sheet. Our app cannot read that page. When the member finishes, 1up sends the phone back to `mywellwallet://1up/callback` with a short-lived code. That code is not the health record. It is a one-time ticket, good for five minutes, that we trade for a token.

**How we get an access token.** The member taps **Add a provider**, picks one plan or clinic, and we open that provider’s authorize URL. After they approve, we `POST` the code, our `client_id`, and our `client_secret` to `https://auth.1uphealthdemo.com/oauth2/token` with `grant_type=authorization_code`. The JSON field `access_token` is what we send as `Authorization: Bearer` on later FHIR downloads. One token is one member at one provider. A second provider is a second approval and a second token.

**Where we persist it.** The access token, and the refresh token when 1up includes one, go in the iOS Keychain under that connection’s id. They are not written to SQLite, logs, or the FHIR JSON. SQLite stores the connection’s display name, kind, 1up system id, authorize URL, FHIR Patient id, last sync time, and status. The downloaded chart goes in `fhir_patients` and `fhir_resources`, tagged with `1up-patient-access` and the connection id.

**How we get a refresh token.** We do not generate one. We keep `refresh_token` only if that same token JSON contains it. 1up’s third-party app policy says a Patient Access app can be issued a refresh token, and that 1up can revoke it. Their older Connect API FAQ says the access token, the refresh token, and the authorization code each expire after 7200 seconds, that there is only one refresh token for a given access token, and that a new pair can be requested before those two hours end. The published demo curl only says to copy `access_token`. The first successful sandbox exchange is what tells us whether `refresh_token` and `expires_in` are present. If they are, a later refresh is:

```
POST https://auth.1uphealthdemo.com/oauth2/token
grant_type=refresh_token
refresh_token={REFRESH_TOKEN}
client_id={CLIENT_ID}
client_secret={CLIENT_SECRET}
```

If 1up returns a new refresh token, it replaces the one in the Keychain. If the field is missing on the original response, or this call fails, we do not invent another endpoint. That connection shows **Reconnect**. The member approves again on 1up’s page. Every other connection is left alone.

**How sign-in stays out of our sight.** `ASWebAuthenticationSession` is the system browser, not a WebView we own. We do not add member-id, date-of-birth, email, or password fields for this step. We do not log the redirect URL. The session object gives us the code and the `state` value, and we discard the code as soon as the token call returns.

**Refresh strategy.** For each connection, if expiry is within 10 minutes, or a FHIR call returns 401, run the refresh-token call above before downloading. **Refresh** on that row downloads FHIR again after the token check. When the app becomes active, do the same for any connection whose last sync is older than its interval. The default interval is 24 hours, with the same choices as Apple Health. iOS will not reliably do this while the app is suspended, so this is an on-open and on-tap strategy, not an overnight guarantee.

**Add a provider, including several.** The button adds a connection. It does not wipe existing ones. The member can have a health plan and a clinic, or several of each, which is the normal case for a chronic disease.

- **Health plans.** Patient Access says the member selects the plan in our app, then we open that plan’s authorize URL. The same `client_id` is used across plan environments after 1up approves production. There is no documented typeahead API for plan names. We filter our list of enabled plans as they type.
- **Clinics and health systems.** 1up’s Provider Search does take a partial name: `GET https://api.1up.health/connect/system/provider?query={text}` matches a doctor, clinic, hospital, or address and returns a FHIR Bundle of Organizations with the health-system id used to open that system’s connect URL. That route is part of the Connect API. Patient Connect, the product that published it, is scheduled to sunset on September 30, 2026. We ask 1up if the route still works for this app before sending keystrokes there. Until then, sandbox **Add a provider** lists only the demo health plan, and the search box filters that list locally.

## 2. Value to enter in the 1up app definition

In the [1up Dev Portal](https://docs.1up.health/docs/dev-portal), **Create a Client** with:

| Portal field | Value |
|--------------|--------|
| Access type | Patient Access |
| Client name | `MyWellWallet` |
| Redirect URL | `mywellwallet://1up/callback` |

That redirect string is copied exactly. It includes the scheme `mywellwallet://`, it has no trailing slash, and it has no query string. 1up requires the protocol on the redirect URL. The same string is the OAuth `redirect_uri`. When it is placed on the authorize request it is percent-encoded as `mywellwallet%3A%2F%2F1up%2Fcallback`. The portal field itself is **not** percent-encoded.

After the client exists, copy `client_id` and `client_secret` from **Sandbox Clients** into a local gitignored config. Then email `payer-patient-access@1up.health` and ask them to sync that `client_id` to the demo environment. The authorize URL below does not work until that sync is done.

Do not register `http://localhost`, an `https://` page we do not host, or a second redirect, for the sandbox client. One redirect keeps the match unambiguous.

## 3. iOS callback that receives that URL

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
- URL: the authorize URL in section 5
- `prefersEphemeralWebBrowserSession`: false, so the member can finish the demo identity form

The session succeeds only when 1up redirects to a URL whose scheme is `mywellwallet`. That is why the portal redirect and this scheme must be the same word.

## 4. Components

| Piece | Role |
|-------|------|
| Profile **Clinical records** toggle | `mcp` or `oneup`, stored as `clinical_record_source`. Default `mcp`. Only the selected source is started and queried. |
| Profile **Add a provider** | Shown only when the toggle is `oneup`. Search, then one authorization. Adds a connection. Does not collect the test member’s name or member id. Those are typed into 1up’s page. |
| `OneUpAuthClient` | Builds the authorize URL, runs the web session, checks `state`, exchanges the code. |
| `OneUpFhirClient` | `GET`s FHIR R4 with `Authorization: Bearer`. |
| `OneUpSyncService` | Orders auth, then fetch, then local save. |
| Keychain | One item per connection: `access_token`, `refresh_token` if present, `expires_at`. Account is the connection id. Not SQLite. |
| `DatabaseService` | Writes `fhir_patients` and `fhir_resources`, same tables the MCP fetch uses today. |
| Apple Health services | Not called from this flow. |

Startup calls `MCPClient.initialize()` only when `clinical_record_source` is `mcp`. It never calls 1up at startup. A 1up sync runs only from **Connect health plan** or **Sync now**, and only when the source is `oneup`.

A production build sets `clinical_record_source` to `oneup` and does not render the toggle. Writes to the setting are ignored. `MCPClient` stays compiled in and is not initialized.

## 5. Authorize request

Sandbox URL, as published by 1up, plus a `state` value we generate so a stale callback cannot be reused:

```
GET https://auth.1uphealthdemo.com/oauth2/authorize/test
  ?client_id={CLIENT_ID}
  &redirect_uri=mywellwallet%3A%2F%2F1up%2Fcallback
  &state={STATE}
```

`STATE` is 32 bytes from a secure random generator, hex-encoded, held in memory until the session returns. It is not written to disk.

1up’s published demo link requires `client_id` and `redirect_uri` only. `state` is added for the client check in section 6. Scopes 1up documents for Patient Access are `patient/*.read`, `launch/patient`, and `openid`. The first sandbox attempt does **not** send `scope`, because the published demo URL does not include it and the demo auth app already binds the token to the member who just signed in. If a later test shows the token is missing read access, add:

```
&scope=patient%2F*.read%20launch%2Fpatient%20openid
```

`patient/*.read` must be encoded as `patient%2F*.read`. A literal slash in the query would be wrong.

## 6. Logic sequence

```
Profile.ClinicalRecords toggle
        │
        ├─ mcp ── MCPClient.initialize on startup
        │         Fetch Data tab visible
        │         OneUpSyncService is not called
        │
        └─ oneup ─ MCPClient is not initialized
                    Fetch Data tab hidden
                    │
                    ▼
Profile.ConnectHealthPlan
        │
        ▼
OneUpSyncService.connect()
        │
        ├─1─ generate state, keep it in the auth session
        │
        ├─2─ ASWebAuthenticationSession
        │       opens the authorize URL in section 5
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
        │     if refresh_token is present, store it on this connection
        │     if expires_in is present, record expiry = now + expires_in
        │     write the Keychain item for this connection id
        │     drop the code from memory
        │
        ├─8─ FHIR reads, section 7, using the bearer token
        │
        └─9─ replace previous rows tagged with this connection id
              leave every other connection in place
              set this row to connected and last synced
```

Canceling the web sheet returns the user to Profile with no token change and no database write.

**Refresh** on a connection skips steps 1–5 when that connection’s Keychain item has an access token and it is not inside the 10-minute expiry window. It starts at step 8. If expiry is inside that window, it runs the refresh-token POST in section 1 first, then step 8. A 401 after that drops only this connection’s Keychain item and shows **Reconnect** on that row.

## 7. FHIR reads

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
  "tag": [
    { "system": "urn:mywellwallet:provenance", "code": "1up-patient-access" },
    { "system": "urn:mywellwallet:connection", "code": "{connection-id}" }
  ]
}
```

`fhir_patients.patient_id` and `fhir_resources.patient_id` are that `Patient.id`. The local `users.id` is stored beside the connection so a later query can join Apple Health (`health_*`.`user_id`) to this plan record. Replacing a sync deletes only rows whose connection tag is this connection id. Other connections and `health_*` rows are left alone.

Paging: if a bundle has `link.relation = next`, follow it before moving to the next resource type.

## 8. Token request and response

```
POST https://auth.1uphealthdemo.com/oauth2/token
Content-Type: application/x-www-form-urlencoded

client_id={CLIENT_ID}
&client_secret={CLIENT_SECRET}
&grant_type=authorization_code
&code={CODE}
```

Use the `access_token` string from the JSON body. Do not log the request body or the response body. `client_secret` is read from the gitignored local config for the sandbox spike. It is not a Dart constant. Before a production client exists, this POST moves off the phone so the secret is not inside the app binary. The phone would then send only the `code` to that exchanger and receive the `access_token`.

## 9. Failures

| Condition | Client behavior |
|-----------|-----------------|
| User closes the auth sheet | Stay on Profile. No write. |
| Redirect `error` | Show `error_description` or `error`. No token call. |
| `state` mismatch | Ignore the code. |
| Token HTTP error, or no `access_token` | Show the HTTP status. Leave the previous token in place if one existed. |
| `GET Patient` fails | Keep the new token so **Sync now** can retry. Keep previous FHIR rows. |
| A later required type fails | Keep Patient and any types already saved this run. Profile shows sync incomplete. |
| Optional type fails | Continue. |
| 401 on any FHIR call after a refresh attempt | Drop this connection’s Keychain item. That row shows **Reconnect**. |

## 10. Portal checklist before the first phone test

1. Redirect URL in the sandbox client is exactly `mywellwallet://1up/callback`.
2. `Info.plist` scheme is `mywellwallet`.
3. `client_id` in the authorize URL is the sandbox client id.
4. 1up has confirmed the client is synced to `auth.1uphealthdemo.com`.
5. The phone is installed from this build, so iOS will open MyWellWallet for that scheme.
