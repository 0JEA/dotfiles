# Claude Code config, tracked so a new machine gets it

Deploy by symlinking into place (the dotfiles convention — each dir mirrors the path under `$HOME`):

```bash
mkdir -p ~/.claude/agents
ln -sf ~/dotfiles/claude/.claude/settings.json ~/.claude/settings.json
ln -sf ~/dotfiles/claude/.claude/agents/*.md   ~/.claude/agents/
```

**What is here**
- `settings.json` — permissions, model, and `enabledPlugins`. Claude Code re-downloads every
  plugin listed there from the `claude-plugins-official` marketplace on first run, so the plugin
  skills (superpowers, stripe, feature-dev, frontend-design, playwright, firebase, context7,
  claude-md-management, the LSPs, security-guidance) do NOT need copying.
- `agents/` — the three CUSTOM agents. These exist nowhere else and are not downloadable:
  `alberta-lawyer`, `doc-writer`, `graphics-engineering-tutor`.

**Deliberately NOT here**
- `~/.claude/.credentials.json` — real credentials. Never commit.
- `settings.local.json` — machine-local overrides.
- `projects/`, `sessions/`, `file-history/`, `security/` — session state and caches (2.3 GB).
  The one exception is `projects/-home-coke/memory`, which is its own repo (`claude-memory`).

**Personal skills** live in their own repo, cloned to `~/.claude/skills`
(`git@github.com:0JEA/claude-skills.git`) — keep it on `main`.
