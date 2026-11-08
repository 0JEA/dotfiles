#!/usr/bin/env bash
# Install the .desktop entries and refresh the caches that actually matter.
#
# WHY THESE ARE COPIED RATHER THAN STOWED:
# Every other package in this repo is symlinked by stow. These are not, because
# Dolphin kept showing "what do you want to open this with?" on a double-click
# while `xdg-mime`, `gio` and `kde-open` all reported the correct application
# and KDE's own open path demonstrably reached the wrapper.
#
# Being a stow SYMLINK is the last structural difference between these entries
# and every entry that works, so they are installed as real files. Be honest
# about the evidence though: that is a suspicion, NOT a proven cause. If Dolphin
# still shows the chooser as real files, the symlink was never the problem and
# the difference lies somewhere else in Dolphin's resolution.
#
# The copies in ~/.local/share/applications are disposable; this directory stays
# the source of truth, so edit here and re-run.
#
# The wrapper in .local/bin IS still stowed — a symlinked executable is fine,
# only the .desktop entries were a problem.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/applications"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

mkdir -p "$DEST"

for f in "$SRC"/*.desktop; do
    name="$(basename "$f")"
    # Remove first: if a previous run (or `stow desktop`) left a symlink here,
    # cp would write THROUGH it back into the repo instead of replacing it.
    rm -f "$DEST/$name"
    cp "$f" "$DEST/$name"
    echo "installed $name"
done

update-desktop-database "$DEST" 2>/dev/null || true

# --noincremental is REQUIRED, not belt-and-braces: the default incremental
# rebuild keys off directory mtimes and silently skips newly added entries,
# which leaves Dolphin unable to resolve them.
if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
    echo "rebuilt ksycoca (full)"
fi

echo
echo "Done. A RUNNING Dolphin still caches the old associations - restart it."
