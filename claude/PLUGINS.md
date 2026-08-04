# Claude Code plugins to re-enable on a new machine

All from the `claude-plugins-official` marketplace (`anthropics/claude-plugins-official`).
They are NOT in settings.json here — that file captures permission allow-rules verbatim and is
deliberately untracked. Re-enable with `/plugin` in Claude Code, or add an `enabledPlugins` block
to `~/.claude/settings.json` by hand.

| Plugin | Skills it provides |
|---|---|
| `clangd-lsp@claude-plugins-official` | C/C++ language server |
| `claude-md-management@claude-plugins-official` | revise-claude-md, claude-md-improver |
| `context7@claude-plugins-official` | live library documentation lookup |
| `feature-dev@claude-plugins-official` | code-architect, code-explorer, code-reviewer agents |
| `firebase@claude-plugins-official` | Firestore/Auth/Functions MCP tools |
| `frontend-design@claude-plugins-official` | frontend-design skill |
| `playwright@claude-plugins-official` | browser automation MCP (used to screenshot UI) |
| `pyright-lsp@claude-plugins-official` | Python language server |
| `security-guidance@claude-plugins-official` | security review guidance |
| `stripe@claude-plugins-official` | stripe-docs, connect-recommend, best-practices, test-cards, explain-error |
| `superpowers@claude-plugins-official` | brainstorming, TDD, systematic-debugging, writing-plans, worktrees, code-review — the process skills |

Verify after enabling: `/plugin` lists all 11, and `superpowers:brainstorming` appears in the skill list.
