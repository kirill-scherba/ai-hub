# Future Ideas & Pending Tasks 🐪🎩

## Context Weaver

**Goal:** Automate Memory Bank updates by analyzing `git diff` and project documentation directly within an MCP tool.

### Required Infrastructure (The "Safe Bridges")

To make `context_weaver` efficient and token-saving, we need to implement the following helper functions in `generative-mcp-hub.pl` and share them with the `Safe` sandbox:

1. **`_safe_read_file($path)`**:
    - Reads UTF-8 content of a file.
    - **Constraint:** Only allows paths within `/home/kirill/go/src/github.com/kirill-scherba/`.
2. **`_safe_git_diff($dir)`**:
    - Returns raw `git diff HEAD`.
    - **Constraint:** Only for whitelisted directories.
3. **`_safe_glob($pattern)`**:
    - Finds files (e.g., `docs/*.md`).
    - **Constraint:** Pattern must be within the whitelist.

### Implementation Notes

- Use `Cwd::abs_path` for reliable path validation.
- Ensure the server remains responsive during startup (avoid blocking calls in `hub_check`).
- Consider why adding these helpers caused a timeout in `opencode` (possibly related to `Safe->share` or an implicit dependency).

### The Tool Itself

```perl
my $dir = $args->{dir} // ".";
my $diff = _safe_git_diff($dir);
my @docs = @{_safe_glob("$dir/docs/*.md") // []};
# ... analysis logic ...
```

## Log Oracle

Integration with `log-user` to correlate runtime errors with codebase context.
