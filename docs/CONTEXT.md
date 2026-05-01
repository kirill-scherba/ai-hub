# Project Context — AI Hub

## Overview

**Generative MCP Hub** — MCP server that lets AI assistants generate new MCP tools at runtime using Perl's Safe sandbox.

## Repository

- **URL:** github.com/kirill-scherba/ai-hub
- **Language:** Perl (JSON::PP, Safe, POSIX)
- **Protocol:** JSON-RPC 2.0 over stdin/stdout (MCP)

## Why This Exists

Existing MCP tool marketplaces are static: humans write tools, submit them, and clients install them. AI Hub flips this: AI assistants can write, compile, and execute Perl code in a Safe sandbox at runtime, registering the result as an instant MCP tool.

## Key Technologies

- **Perl 5** — the language (Safe sandbox since 1994)
- **Safe** — built-in sandbox for AI-generated code
- **JSON** — JSON-RPC 2.0 protocol (via JSON::PP)
- **MCP** — Model Context Protocol (stdio transport)

## Built-in Tools

1. `tool_generate` — create a tool from name + schema + Perl code
2. `tool_list` — list built-in and generated tools
3. `tool_export` — export a generated tool as JSON
4. `tool_import` — import a tool from JSON
5. `tool_remove` — remove a generated tool
6. `weather` — current weather for any city (supports Cyrillic)
7. `exchange_rate` — currency exchange rates (any ISO 4217 pair)

## Origin

- **Date:** 2026-04-30
- **Inspiration:** db-tool-mcp (github.com/kirill-scherba/db-tool-mcp)
- **User:** Kirill — Your Majesty
- **AI:** Baron (Cline incarnation)
