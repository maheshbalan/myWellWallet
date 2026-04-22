# Mobile App MCP Client

This document explains how to build a mobile app client for the FHIR MCP Server.

## Current Server Limitation

The current FastMCP HTTP/SSE server requires a **persistent SSE connection** for session management. Each HTTP request after `initialize` requires a session ID that's maintained through the persistent connection.

## Solution Options

### Option 1: Use FastMCP Client (Recommended for Testing)

The FastMCP Python client handles SSE sessions automatically:

```python
from fastmcp import Client

async with Client("https://mcp-fhir-server-maheshbalan1.replit.app/mcp") as client:
    tools = await client.list_tools()
    result = await client.call_tool("request_patient_resource", {
        "request": {"method": "GET", "path": "/Patient", "body": None}
    })
```

**Note**: The FastMCP Client has a known issue where it can list tools but fails to call them over HTTP/SSE. This appears to be a bug in FastMCP 2.13.1.

### Option 2: Server Configuration Change (Recommended for Production)

For mobile apps, you need **stateless requests**. The server should be configured to:

1. **Support stateless mode**: Allow requests without requiring a persistent session
2. **Use session tokens**: Return a session token from `initialize` that can be used in subsequent requests
3. **Or use WebSockets**: Switch from HTTP/SSE to WebSockets for better mobile support

### Option 3: Maintain Persistent Connection (Complex for Mobile)

Maintain a persistent SSE connection in your mobile app. This is complex because:
- Mobile apps can go to background/foreground
- Network changes (WiFi to cellular)
- Battery optimization kills background connections

## Working Example

See `simple_mcp_client.py` for a basic implementation. However, it currently fails because the server requires session management.

## Next Steps

1. **Modify the server** to support stateless requests OR return session tokens
2. **Or use WebSockets** instead of HTTP/SSE for better mobile support
3. **Or use the FastMCP stdio transport** locally and create an API gateway

## Mobile App Integration

For React Native, Flutter, or native mobile apps:

1. Use HTTP client libraries that support SSE (e.g., `react-native-sse` for React Native)
2. Maintain the SSE connection in a service/background task
3. Handle reconnection logic for network changes
4. Store session state appropriately

## Example Mobile Client Structure

```javascript
// React Native example
import { EventSource } from 'react-native-sse';

class MCPClient {
  constructor(url) {
    this.url = url;
    this.eventSource = null;
  }
  
  async initialize() {
    // Send initialize request
    // Maintain SSE connection
    // Handle session management
  }
  
  async listTools() {
    // Send tools/list over SSE connection
  }
  
  async callTool(name, args) {
    // Send tools/call over SSE connection
  }
}
```

