# ~/.bashrc

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# --- FUNCTIONS ---
export GEMINI_API_KEY="AIzaSyCeQNCEUY-iFlwnuIlKF82GIIg725KmmNg"

# --- ALIASES ---
alias ls='eza --icons --git'
alias ll='eza -lh --icons --git'
alias tree='eza --tree --icons'
alias grep='grep --color=auto'
alias qutebrowser='setsid qutebrowser &'
alias pep9='setsid env QT_QPA_PLATFORM=xcb QT_XCB_GL_INTEGRATION=none JAVA_TOOL_OPTIONS="-Dawt.useSystemAAFontSettings=lcd -Dswing.aatext=true -Dsun.java2d.xrender=true -Dsun.java2d.uiScale=1.5 -Dswing.defaultlaf=com.sun.java.swing.plaf.gtk.GTKLookAndFeel" ~/applications/pep.AppImage &'

# --- STARSHIP PROMPT ---
eval "$(starship init bash)"

# --- AUTO-TMUX ---
# Use "exec" to replace the bash process with tmux.
# When you exit tmux, the terminal window will close.
if [[ -z "$TMUX" ]] && [[ "$TERM" != "linux" ]]; then
  exec tmux new-session
fi
export PATH="$HOME/.local/bin:$PATH"


# Added by Antigravity CLI installer
export PATH="/home/john/.local/bin:$PATH"

# Raise Claude Code's per-session web-search cap (default 200 was hit during long research runs)
export CLAUDE_CODE_MAX_WEB_SEARCHES_PER_SESSION=100000

# Secrets live in ~/.secrets/env (untracked, chmod 600) — never commit keys here
[ -f "$HOME/.secrets/env" ] && . "$HOME/.secrets/env"

# ~/.local/bin (adopted from the laptop, which hardcoded /home/coke/.local/bin)
export PATH="$HOME/.local/bin:$PATH"
