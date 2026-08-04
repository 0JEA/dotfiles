#!/usr/bin/env bash
# claude/sync-settings.sh — export a SAFE copy of ~/.claude/settings.json into dotfiles.
#
# `permissions` is dropped, always. That block accumulates allow-rules verbatim as you approve
# commands, so it captures whatever was typed — on 2026-08-03 it contained a plaintext sudo
# password (`Bash(printf <password>:*)`) and that got pushed to a public repo. Permission rules
# are also machine-specific (this laptop's BAT0 paths, waybar), so they should not travel anyway.
#
# Everything else — model, effort, plugin list, UI prefs — is safe and worth keeping.
#
#   bash claude/sync-settings.sh    # refresh the template after changing settings
set -euo pipefail
SRC="$HOME/.claude/settings.json"
DST="$HOME/dotfiles/claude/settings.template.json"
node -e '
const fs=require("fs");
const j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
delete j.permissions;            // NEVER export: can contain typed secrets
const out=JSON.stringify(j,null,2)+"\n";
if(/printf |password|sk_|re_[A-Za-z0-9]|ghp_|AIza/i.test(out)){
  console.error("REFUSING: sanitized output still looks like it contains a secret."); process.exit(1);
}
fs.writeFileSync(process.argv[2], out);
console.log("wrote "+process.argv[2]+" with keys: "+Object.keys(j).join(", "));
' "$SRC" "$DST"
