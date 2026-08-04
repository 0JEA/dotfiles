# Claude Code config, tracked so a new machine gets it

Deploy by symlinking into place (the dotfiles convention — each dir mirrors the path under `$HOME`):

```bash
mkdir -p ~/.claude/agents
cp  ~/dotfiles/claude/settings.template.json ~/.claude/settings.json   # COPY, do not symlink
ln -sf ~/dotfiles/claude/.claude/agents/*.md ~/.claude/agents/
```

**Copy, never symlink `settings.json`.** Claude Code rewrites it every time you approve a
permission, so a symlink would write your live allow-rules — and therefore anything typed into
them — straight back into this repo. That is exactly how a plaintext sudo password reached a
public repo on 2026-08-03. Refresh the template deliberately with `bash claude/sync-settings.sh`,
which strips `permissions` and refuses to write if the result still looks secret-bearing.

**What is here**
- `settings.template.json` — model, effort, UI prefs, and `enabledPlugins` (all 11 plugins), with
  `permissions` REMOVED. Copy it into place and Claude Code re-downloads every plugin listed.
- `PLUGINS.md` — the same plugin list in readable form, with what each one provides.
- `sync-settings.sh` — regenerates the template safely.
- `agents/` — the three CUSTOM agents. These exist nowhere else and are not downloadable:
  `alberta-lawyer`, `doc-writer`, `graphics-engineering-tutor`.

**Deliberately NOT here**
- `~/.claude/.credentials.json` — real credentials. Never commit.
- `settings.local.json` — machine-local overrides.
- `projects/`, `sessions/`, `file-history/`, `security/` — session state and caches (2.3 GB).
  The one exception is `projects/-home-coke/memory`, which is its own repo (`claude-memory`).

**Personal skills** live in their own repo, cloned to `~/.claude/skills`
(`git@github.com:0JEA/claude-skills.git`) — keep it on `main`.
