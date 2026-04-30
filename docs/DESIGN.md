# Design — AI Hub

## Architecture

```
┌─────────────────────────────┐
│      MCP Client (AI)        │
│  (Cline, Claude Desktop)    │
└──────────┬──────────────────┘
           │ JSON-RPC 2.0 over stdin/stdout
           ▼
┌─────────────────────────────┐
│   generative-mcp-hub.pl     │
│                             │
│  ┌───────────────────────┐  │
│  │    Main Loop          │  │
│  │  (infinite stdin)     │  │
│  └───────┬───────────────┘  │
│          │                   │
│  ┌───────┴───────────────┐  │
│  │   tools/list handler  │  │
│  │   tools/call handler  │  │
│  └───────┬───────────────┘  │
│          │                   │
│  ┌───────┴───────────────┐  │
│  │   Built-in Tools      │  │
│  │  ┌─────────────────┐  │  │
│  │  │ tool_generate    │  │  │
│  │  │ tool_list        │  │  │
│  │  │ tool_export      │  │  │
│  │  │ tool_import      │  │  │
│  │  │ tool_remove      │  │  │
│  │  └─────────────────┘  │  │
│  └───────┬───────────────┘  │
│          │                   │
│  ┌───────┴───────────────┐  │
│  │   Tool Registry (%)   │  │
│  │  (in-memory hashref)  │  │
│  └───────┬───────────────┘  │
│          │                   │
│  ┌───────┴───────────────┐  │
│  │   Safe Sandbox        │  │
│  │  (compile + execute)  │  │
│  └───────────────────────┘  │
└─────────────────────────────┘
```

## Data Flow

### Tool Generation
1. AI calls `tools/call` with `tool_generate`
2. Hub receives name, schema, Perl code
3. Code is parsed for `use Module;` statements
4. Whitelisted modules are loaded and shared into Safe
5. Code is wrapped in `sub { my $args = shift; ... }` and compiled via `Safe::reval`
6. Compiled coderef is stored in `%tool_registry`
7. Tool appears in subsequent `tools/list` calls

### Tool Execution
1. AI calls `tools/call` with generated tool name
2. Hub looks up tool in `%tool_registry`
3. Compiled coderef is executed with `$args` hashref
4. Result is wrapped in `{ status => "success", data => $result }`
5. Errors return `{ status => "error", data => "Runtime error: ..." }`

## Security Model

### Safe Sandbox
- **Module whitelist:** Only explicitly listed modules are allowed
  - `MIME::Base64`, `Digest::MD5`, `URI::Escape`, `JSON`, `Scalar::Util`, `Cwd`, `Time::Piece`
- **No system calls:** `system()`, `exec()`, `qx()`, `open()` are blocked by default in Safe
- **No file I/O:** File operations are restricted
- **No network:** Socket operations are blocked
- **Compile-time validation:** Code is parsed for `use` statements before compilation
- **Runtime isolation:** Each execution runs in the same Safe compartment (persistent state within session)

## Transport

- **stdin/stdout** (stdio MCP transport)
- **Logging to stderr** — stdout is reserved for JSON-RPC protocol messages
- **UTF-8** encoding throughout

## File Structure

```
ai-hub/
├── generative-mcp-hub.pl   # Main MCP server (one file, zero build deps)
├── README.md               # Project overview and quick start
├── docs/
│   ├── CONTEXT.md          # Project context (for AI memory)
│   ├── DESIGN.md           # Architecture and design (this file)
│   └── STATUS.md           # Changelog and status
```

## Future Ideas

- File-based persistence for generated tools (JSON on disk)
- More whitelisted Safe modules
- Sandbox timeout via `alarm()` + `eval`
- Tool code hash verification (prevent tampering)
- README.md generation from tools/list
- Integration with memory-store-mcp for tool memory