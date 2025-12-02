# Mobile Client Integration Guide

## Overview

This guide explains how your Mobile Client Wallet app connects to the FHIR MCP Server securely using API key authentication.

## Quick Start

### 1. Get Your API Key

1. Go to the admin portal: `https://your-domain.replit.app/admin/login`
2. Login with admin credentials
3. Generate a new API key with a descriptive name (e.g., "Mobile Client Production")
4. **Copy the key immediately** - it won't be shown again

### 2. Include API Key in Requests

Add the `X-API-Key` header to all MCP requests:

```http
POST /mcp HTTP/1.1
Host: your-domain.replit.app
Content-Type: application/json
X-API-Key: YOUR_API_KEY_HERE

{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2024-11-05",
    "capabilities": {},
    "clientInfo": {
      "name": "mobile-client",
      "version": "1.0"
    }
  }
}
```

## Mobile App Implementation

### iOS (Swift)

```swift
import Foundation

class MCPClient {
    let baseURL: URL
    let apiKey: String
    var sessionId: String?
    
    init(baseURL: String, apiKey: String) {
        self.baseURL = URL(string: baseURL)!
        self.apiKey = apiKey
    }
    
    func makeRequest(_ jsonRPC: [String: Any]) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent("mcp"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        
        if let sessionId = sessionId {
            request.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonRPC)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            if let newSessionId = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id") {
                self.sessionId = newSessionId
            }
        }
        
        return data
    }
    
    func initialize() async throws {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "protocolVersion": "2024-11-05",
                "capabilities": [:],
                "clientInfo": ["name": "ios-client", "version": "1.0"]
            ]
        ]
        _ = try await makeRequest(request)
    }
    
    func getPatient(name: String) async throws -> Data {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/call",
            "params": [
                "name": "request_patient_resource",
                "arguments": [
                    "request": [
                        "method": "GET",
                        "path": "/Patient?name=\(name)"
                    ]
                ]
            ]
        ]
        return try await makeRequest(request)
    }
}

// Usage
let client = MCPClient(
    baseURL: "https://your-domain.replit.app",
    apiKey: KeychainHelper.getAPIKey() // Store securely!
)
try await client.initialize()
let patientData = try await client.getPatient(name: "Ruben688")
```

### Android (Kotlin)

```kotlin
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

class MCPClient(
    private val baseUrl: String,
    private val apiKey: String
) {
    private val client = OkHttpClient()
    private var sessionId: String? = null
    
    suspend fun makeRequest(jsonRPC: JSONObject): String = withContext(Dispatchers.IO) {
        val requestBody = jsonRPC.toString()
            .toRequestBody("application/json".toMediaType())
        
        val requestBuilder = Request.Builder()
            .url("$baseUrl/mcp")
            .post(requestBody)
            .header("Content-Type", "application/json")
            .header("X-API-Key", apiKey)
        
        sessionId?.let {
            requestBuilder.header("Mcp-Session-Id", it)
        }
        
        val response = client.newCall(requestBuilder.build()).execute()
        
        response.header("Mcp-Session-Id")?.let {
            sessionId = it
        }
        
        response.body?.string() ?: throw Exception("Empty response")
    }
    
    suspend fun initialize() {
        val request = JSONObject().apply {
            put("jsonrpc", "2.0")
            put("id", 1)
            put("method", "initialize")
            put("params", JSONObject().apply {
                put("protocolVersion", "2024-11-05")
                put("capabilities", JSONObject())
                put("clientInfo", JSONObject().apply {
                    put("name", "android-client")
                    put("version", "1.0")
                })
            })
        }
        makeRequest(request)
    }
    
    suspend fun getPatient(name: String): String {
        val request = JSONObject().apply {
            put("jsonrpc", "2.0")
            put("id", 2)
            put("method", "tools/call")
            put("params", JSONObject().apply {
                put("name", "request_patient_resource")
                put("arguments", JSONObject().apply {
                    put("request", JSONObject().apply {
                        put("method", "GET")
                        put("path", "/Patient?name=$name")
                    })
                })
            })
        }
        return makeRequest(request)
    }
}

// Usage
val client = MCPClient(
    baseUrl = "https://your-domain.replit.app",
    apiKey = SecurePreferences.getApiKey(context) // Store securely!
)
client.initialize()
val patientData = client.getPatient("Ruben688")
```

### React Native / JavaScript

```javascript
class MCPClient {
  constructor(baseUrl, apiKey) {
    this.baseUrl = baseUrl;
    this.apiKey = apiKey;
    this.sessionId = null;
  }

  async makeRequest(jsonRPC) {
    const headers = {
      'Content-Type': 'application/json',
      'X-API-Key': this.apiKey,
    };

    if (this.sessionId) {
      headers['Mcp-Session-Id'] = this.sessionId;
    }

    const response = await fetch(`${this.baseUrl}/mcp`, {
      method: 'POST',
      headers,
      body: JSON.stringify(jsonRPC),
    });

    const newSessionId = response.headers.get('Mcp-Session-Id');
    if (newSessionId) {
      this.sessionId = newSessionId;
    }

    const text = await response.text();
    // Parse SSE format
    const lines = text.split('\n');
    for (const line of lines) {
      if (line.startsWith('data: ')) {
        return JSON.parse(line.substring(6));
      }
    }
    throw new Error('Invalid response format');
  }

  async initialize() {
    return this.makeRequest({
      jsonrpc: '2.0',
      id: 1,
      method: 'initialize',
      params: {
        protocolVersion: '2024-11-05',
        capabilities: {},
        clientInfo: { name: 'mobile-client', version: '1.0' },
      },
    });
  }

  async getPatient(name) {
    return this.makeRequest({
      jsonrpc: '2.0',
      id: 2,
      method: 'tools/call',
      params: {
        name: 'request_patient_resource',
        arguments: {
          request: {
            method: 'GET',
            path: `/Patient?name=${name}`,
          },
        },
      },
    });
  }
}

// Usage
import * as SecureStore from 'expo-secure-store';

const apiKey = await SecureStore.getItemAsync('MCP_API_KEY');
const client = new MCPClient('https://your-domain.replit.app', apiKey);
await client.initialize();
const patient = await client.getPatient('Ruben688');
```

## Security Best Practices

### API Key Storage

**DO:**
- Store API keys in secure/encrypted storage (iOS Keychain, Android Keystore, Expo SecureStore)
- Fetch keys at runtime from secure storage
- Use different keys for development/staging/production

**DON'T:**
- Hardcode API keys in source code
- Store keys in plain text files or preferences
- Log API keys to console
- Commit API keys to version control

### Error Handling

| Status Code | Meaning | Action |
|-------------|---------|--------|
| 401 | Invalid/Missing API key | Check key is correct, not revoked |
| 429 | Rate limit exceeded | Wait and retry with exponential backoff |
| 500 | Server error | Retry with backoff, report if persistent |

### Rate Limiting

The server implements rate limiting to prevent abuse:
- Limit: 100 requests per minute per API key
- Response when exceeded: HTTP 429 with retry information

Implement exponential backoff in your client:

```javascript
async function requestWithRetry(fn, maxRetries = 3) {
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      if (error.status === 429 && attempt < maxRetries - 1) {
        const delay = Math.pow(2, attempt) * 1000; // 1s, 2s, 4s
        await new Promise(resolve => setTimeout(resolve, delay));
        continue;
      }
      throw error;
    }
  }
}
```

## Available MCP Tools

After initialization, you can use these tools to access FHIR data:

| Tool Name | Description |
|-----------|-------------|
| `request_patient_resource` | Query patient records |
| `request_observation_resource` | Query observations (labs, vitals) |
| `request_condition_resource` | Query conditions/diagnoses |
| `request_medication_resource` | Query medications |
| `request_immunization_resource` | Query immunizations |
| `request_encounter_resource` | Query encounters/visits |
| `request_allergy_intolerance_resource` | Query allergies |
| `request_family_member_history_resource` | Query family history |
| `request_document_reference_resource` | Query documents |
| `request_generic_resource` | Query any FHIR resource |

## Example: Complete Patient Record Retrieval

```javascript
async function getCompletePatientRecord(client, patientName) {
  // 1. Find patient
  const patientResult = await client.makeRequest({
    jsonrpc: '2.0',
    id: 1,
    method: 'tools/call',
    params: {
      name: 'request_patient_resource',
      arguments: { request: { method: 'GET', path: `/Patient?name=${patientName}` } },
    },
  });
  
  const patientId = extractPatientId(patientResult);
  
  // 2. Get all related records in parallel
  const [conditions, observations, medications] = await Promise.all([
    client.makeRequest({
      jsonrpc: '2.0', id: 2, method: 'tools/call',
      params: { name: 'request_condition_resource',
        arguments: { request: { method: 'GET', path: `/Condition?patient=${patientId}` } }
      }
    }),
    client.makeRequest({
      jsonrpc: '2.0', id: 3, method: 'tools/call',
      params: { name: 'request_observation_resource',
        arguments: { request: { method: 'GET', path: `/Observation?patient=${patientId}` } }
      }
    }),
    client.makeRequest({
      jsonrpc: '2.0', id: 4, method: 'tools/call',
      params: { name: 'request_medication_resource',
        arguments: { request: { method: 'GET', path: `/MedicationRequest?patient=${patientId}` } }
      }
    }),
  ]);
  
  return { patient: patientResult, conditions, observations, medications };
}
```

## Troubleshooting

### "Missing API key" Error
- Ensure `X-API-Key` header is included in request
- Check header name is exactly `X-API-Key` (case-sensitive)

### "Invalid API key" Error  
- Verify the key is correct (no extra spaces)
- Check if the key has been revoked in admin portal
- Ensure key is active (not expired)

### Empty Response
- Include `Accept: application/json, text/event-stream` header
- Parse SSE format (lines starting with `data: `)

### Session Issues
- Always include `Mcp-Session-Id` header after initialization
- If session expires, re-initialize to get new session

## Support

For issues with the FHIR MCP Server:
1. Check the admin portal audit logs for request history
2. Verify API key is active and not rate-limited
3. Review server logs for detailed error messages
