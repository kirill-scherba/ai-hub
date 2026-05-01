# AI Hub — Context

## What is AI Hub?

AI Hub is a platform for creating, sharing, and discovering MCP tools across AI assistants.

It consists of two components:

### 1. **Hub Server** (Go)
- HTTP REST API server written in Go, running on port 8484
- Stores tools in keyvalembd (libSQL + Ollama embeddings)
- Allows publishing, searching (semantically), retrieving, and deleting tools
- Endpoints:
  - `POST /tools` — create/publish a tool
  - `GET /tools?prefix=` — list tools with optional prefix filter
  - `GET /tools/{name}` — retrieve a specific tool
  - `DELETE /tools/{name}` — delete a tool
  - `GET /search?q=...&limit=N` — semantic search across tools
- Flags: `--port`, `AI_HUB_PORT`, `AI_HUB_DATA_DIR`

### 2. **generative-mcp-hub.pl** (Perl MCP Server)
- MCP server communicating via JSON-RPC 2.0 over stdin/stdout
- Allows AI to generate new MCP tools in Perl via the Safe sandbox
- Tools:
  - `tool_generate` — create a new tool
  - `tool_list` — list all tools
  - `tool_export` / `tool_import` — export/import as JSON
  - `tool_remove` — delete a tool
  - **hub_publish** — publish a local tool to the Hub Server
  - **hub_search** — semantic search for tools on the Hub
  - **hub_pull** — download a tool from the Hub and install it locally
  - **hub_list** — list tools available on the Hub
- Flags: `--hub-url <URL>`, `AI_HUB_SERVER_URL`

## Architecture

```
┌─────────────┐     HTTP/REST      ┌──────────────────┐
│  MCP Client  │ ◄──── JSON-RPC ───► │ generative-mcp-  │
│  (AI Assistant) │                  │ hub.pl (Perl)    │
└─────────────┘                     └────────┬─────────┘
                                              │ --hub-url http://host:8484
                                              ▼
                                    ┌──────────────────┐
                                    │  Hub Server (Go)  │
                                    │  port :8484        │
                                    │  keyvalembd        │
                                    │  + Ollama embeds   │
                                    └──────────────────┘
```

## Key Concepts

- **Tool definition** — JSON object with name, description, inputSchema, code, created_at
- **Semantic search** — via Ollama embedding (model embeddinggemma:latest)
- **Safe sandbox** — Perl Safe module for secure code execution
- **Persistence** — tools are saved to disk (tools.json) and in keyvalembd (hub.db)