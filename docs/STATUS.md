# Project Status — AI Hub

## 2026-04-30: Initial Release (v0.1.0)

### What was built

- **generative-mcp-hub.pl** — core MCP server (one file, ~600 lines)
- 5 built-in tools: `tool_generate`, `tool_list`, `tool_export`, `tool_import`, `tool_remove`
- Safe sandbox for AI-generated Perl code
- Export/Import system for tool sharing
- Full documentation (README.md, docs/CONTEXT.md, docs/DESIGN.md, docs/STATUS.md)

### Architecture

- One-file Perl MCP server (inspired by db-tool-mcp)
- JSON-RPC 2.0 over stdin/stdout
- In-memory tool registry (`%tool_registry`)
- Safe sandbox with whitelisted modules

### Security

- Perl's built-in `Safe->new()` sandbox
- 7 whitelisted modules (MIME::Base64, Digest::MD5, URI::Escape, JSON, Scalar::Util, Cwd, Time::Piece)
- Built-in tools cannot be overwritten
- Tool names validated against regex

## 2026-04-30: Verification

### What was verified

- [x] Git status checked — working tree clean, on master
- [x] Full code read (~600 lines)
- [x] All 5 built-in tools tested via MCP
  - `tool_list` — returns list (5 builtin, 0 generated)
  - `tool_generate` — creates tool from name + schema + Perl code
  - `tool_export` — exports generated tool as JSON
  - `tool_import` — imports tool from JSON
  - `tool_remove` — removes generated tool
- [x] Full cycle tested: generate → list → execute → export → remove
- [x] Memory Bank read (CONTEXT.md, DESIGN.md, STATUS.md)

### Issues Found

#### 1. UTF-8 encoding issue (fixed)

**Problem:** Cyrillic characters displayed as `ÃÂÃÂ°...` (mojibake — double UTF-8 encoding).
**Cause:** The combination of `JSON->new->utf8` + `binmode(STDOUT, ":utf8")` caused double encoding: JSON encoded the string into UTF-8 bytes, then STDOUT decoded/re-encoded them again.
**Fix:** Removed `->utf8` flag from JSON constructor. Kept `JSON->new->allow_nonref` + `binmode(STDOUT, ":utf8")` — analogous to db-tool-mcp where this scheme works correctly.

#### 2. Server does not restart on Cline CLI reconnection

**Problem:** After `pkill` of old ai-hub processes, Cline CLI does not restart the server automatically. Requires restart of Cline CLI itself.

### Next Steps

- [x] Test with actual MCP client (added to Cline config) — **done** (works via Cline MCP)
- [x] Add file-based persistence (JSON on disk) — to save generated tools between sessions
- [ ] Add sandbox timeout via alarm() — protection against infinite loops
- [ ] Expand Safe-whitelisted modules — more useful modules for AI-generated code
- [ ] Submit to Cline Marketplace — after stabilization

## 2026-05-01: Built-in weather + Persistence (v0.2.0)

### What was done

- **weather — built-in** weather tool. Supports Cyrillic (Москва, Саратов, etc.). Uses `wttr.in` API.
- **File-based persistence** — generated tools are automatically saved to `tools.json` and loaded on server startup.
  - `save_tools()` called after `tool_generate` and `tool_remove`
  - `load_tools()` called on server startup (before `initialized`)
  - File created next to `generative-mcp-hub.pl` in `$FindBin::Bin`

### Test Protocol

- [x] `weather(city: "Москва")` — returned temperature, humidity, wind, description. Cyrillic passed correctly.
- [x] `tool_generate(name: "hello")` → `tools.json` created with tool definition.
- [x] Server restart → `hello` loaded from `tools.json` → `hello(name: "Cline")` returned `{"greeting":"Hello, Cline!"}`.

### Architectural Changes

- Built-in tools count: 6 (`tool_generate`, `tool_list`, `tool_export`, `tool_import`, `tool_remove`, `weather`)
- Added `save_tools()` and `load_tools()` functions in `%tool_registry` namespace
- `tools.json` — lightweight JSON file, no database required

## 2026-05-01: Built-in exchange_rate (v0.2.1)

### What was done

- **exchange_rate — built-in** currency exchange tool. Default: USD → RUB. Supports any ISO 4217 pair.
- Uses `exchangerate-api.com` API (free, no API key required).
- Built-in tools count increased to 7.

### Test Protocol

- [x] `exchange_rate(base: "USD", target: "RUB")` → `{"rate": 74.98, "date": "2026-05-01"}`
- [x] `exchange_rate(base: "EUR", target: "RUB")` → `{"rate": 87.94, "date": "2026-05-01"}`
- [x] Cyrillic currency names not applicable but `base`/`target` are ISO codes — works universally.

### Documentation

- [x] All docs translated to English (CONTEXT.md, DESIGN.md, STATUS.md)
