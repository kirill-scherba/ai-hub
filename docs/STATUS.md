# Project Status — AI Hub

## 2026-04-30: Initial Release (v0.1.0)

### What was built
- **generative-mcp-hub.pl** — core MCP server (one file, 451 lines)
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

### Next steps
- [ ] Test with actual MCP client (add to Cline config)
- [ ] Add file-based persistence (JSON on disk)
- [ ] Add sandbox timeout via alarm()
- [ ] Expand Safe-whitelisted modules
- [ ] Publish to GitHub
- [ ] Submit to Cline Marketplace