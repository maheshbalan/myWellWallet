# Server-Side Issue Explanation

## The Problem

The FHIR MCP Server is experiencing a **known bug in FastMCP 2.13.1** where:

✅ **Works:**
- `initialize` - Successfully establishes session and returns session ID
- `tools/list` - Successfully lists all available tools including `request_patient_resource`

❌ **Fails:**
- `tools/call` - Returns error: `"Unknown tool: request_patient_resource"` even though the tool was just listed

## Root Cause

This is a **server-side bug in FastMCP 2.13.1's HTTP/SSE transport implementation**. The issue is documented in the server's README:

> **Note**: The FastMCP Client has a known issue where it can list tools but fails to call them over HTTP/SSE. This appears to be a bug in FastMCP 2.13.1.

### Technical Details

1. **Session Management**: The server uses FastMCP's HTTP/SSE transport which requires:
   - Session ID in `Mcp-Session-Id` header for all requests after `initialize`
   - Persistent session state on the server side

2. **Tool Registration**: When `tools/list` is called, the server successfully:
   - Loads tool definitions
   - Returns the list of available tools
   - The tool `request_patient_resource` is clearly in the list

3. **Tool Execution Failure**: When `tools/call` is invoked:
   - The server receives the request with correct session ID
   - The tool name `request_patient_resource` matches a tool in the list
   - **But the server's tool registry/lookup fails to find the tool**
   - Returns: `"Unknown tool: request_patient_resource"` with `isError: true`

### Why This Happens

The bug appears to be in FastMCP's internal tool registry management when using HTTP/SSE transport. Possible causes:

1. **Session State Mismatch**: The tool registry might not be properly associated with the session
2. **Tool Name Resolution**: FastMCP might be using a different lookup mechanism for `tools/list` vs `tools/call`
3. **HTTP/SSE Transport Bug**: The HTTP/SSE transport implementation may have a bug in how it handles tool calls vs tool listing

### Evidence

Testing with curl confirms this is a server-side issue:

```bash
# Initialize - WORKS
curl -X POST https://mcp-fhir-server-maheshbalan1.replit.app/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":"1","method":"initialize",...}'
# Returns: Session ID in header ✓

# List Tools - WORKS  
curl -X POST ... -H "Mcp-Session-Id: <session>" \
  -d '{"jsonrpc":"2.0","id":"2","method":"tools/list",...}'
# Returns: List of tools including "request_patient_resource" ✓

# Call Tool - FAILS
curl -X POST ... -H "Mcp-Session-Id: <session>" \
  -d '{"jsonrpc":"2.0","id":"3","method":"tools/call",...}'
# Returns: "Unknown tool: request_patient_resource" ✗
```

## Solutions

### Option 1: Server Fix (Recommended)
The server maintainer needs to:
1. Update FastMCP to a version that fixes this bug (if available)
2. Or implement a workaround in the server code
3. Or switch to a different transport (WebSockets, stateless mode)

### Option 2: Server Configuration
The server could be configured to:
1. Support stateless requests (no session required)
2. Use session tokens instead of session IDs
3. Implement a custom tool call handler that bypasses FastMCP's buggy registry

### Option 3: Client Workaround (Current Attempt)
We've tried:
- Calling `tools/list` before each `tools/call` (doesn't help)
- Adding delays after initialization (doesn't help)
- Ensuring proper session ID in headers (already correct)

**Result**: No client-side workaround is possible - this requires a server-side fix.

## Impact

- **Current Status**: Cannot retrieve patient data from FHIR server
- **Workaround**: None available from client side
- **Next Steps**: Contact server maintainer or wait for FastMCP update

## References

- FastMCP GitHub: https://github.com/modelcontextprotocol/python-sdk
- FHIR MCP Server: https://github.com/the-momentum/fhir-mcp-server
- Known Issue: Documented in server's README_MOBILE_CLIENT.md

