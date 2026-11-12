# ~/.zshrc

# --- FUNCTIONS ---

# GitHub MCP server reads its token from here; pulled from the gh keyring (no plaintext token)
export GITHUB_PERSONAL_ACCESS_TOKEN="$(gh auth token)"

# --- ALIASES ---
alias ls='eza --icons --git'
alias ll='eza -lh --icons --git'
alias tree='eza --tree --icons'
alias grep='grep --color=auto'
alias qutebrowser='setsid qutebrowser &'
alias pep9='setsid env QT_QPA_PLATFORM=xcb QT_XCB_GL_INTEGRATION=none JAVA_TOOL_OPTIONS="-Dawt.useSystemAAFontSettings=lcd -Dswing.aatext=true -Dsun.java2d.xrender=true -Dsun.java2d.uiScale=1.5 -Dswing.defaultlaf=com.sun.java.swing.plaf.gtk.GTKLookAndFeel" ~/applications/pep.AppImage &'

# --- STARSHIP PROMPT ---
eval "$(starship init zsh)"

# --- AUTO-TMUX ---
if [[ -z "$TMUX" ]] && [[ "$TERM" != "linux" ]]; then
    exec tmux new-session -s "session_$(date +%s)"
fi

# Basic History settings
HISTSIZE=1000
SAVEHIST=1000
HISTFILE=~/.zsh_history

# Prompt initialization
autoload -Uz compinit && compinit
# XDG user dirs (Documents/Downloads/Pictures/...). Without this the vars are
# unset in the shell and scripts fall back to $HOME. Added 2026-08-28.
if [[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs" ]]; then
  set -a; source "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"; set +a
fi

export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"


# Added by Antigravity CLI installer
export PATH="/home/john/.local/bin:$PATH"

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/home/john/google-cloud-sdk/path.zsh.inc' ]; then . '/home/john/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/home/john/google-cloud-sdk/completion.zsh.inc' ]; then . '/home/john/google-cloud-sdk/completion.zsh.inc'; fi

# seraph tooling (DESKTOP-SETUP.md step 6)
export PATH="$HOME/bin:$PATH"

# ssh-agent (systemd user socket)
export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"

# Default editor for git, crontab -e, sudoedit, etc.
export EDITOR=nvim
export VISUAL=nvim

# Raise Claude Code's per-session web-search cap (default 200 was hit during long research runs)
export CLAUDE_CODE_MAX_WEB_SEARCHES_PER_SESSION=100000

# Secrets live in ~/.secrets/env (untracked, chmod 600) — never commit keys here
[ -f "$HOME/.secrets/env" ] && . "$HOME/.secrets/env"

# ~/.local/bin (adopted from the laptop, which hardcoded /home/coke/.local/bin)
export PATH="$HOME/.local/bin:$PATH"

# Racket user-scope binaries: plt-r5rs (the R5RS runner/REPL, from the r5rs-lib
# package) lands here rather than in /usr/bin, because it was installed with
# `raco pkg install` instead of pacman. The directory is version-stamped
# (.../racket/9.3/bin), so this globs instead of hardcoding a version that a
# Racket upgrade would silently invalidate. (N) is zsh's null_glob qualifier:
# without it, no Racket install would make this an error rather than a no-op.
for _racket_bin in "$HOME"/.local/share/racket/*/bin(N); do
  export PATH="$_racket_bin:$PATH"
done
unset _racket_bin
