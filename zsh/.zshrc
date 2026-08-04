# ~/.zshrc

# --- FUNCTIONS ---
export GEMINI_API_KEY="AIzaSyCeQNCEUY-iFlwnuIlKF82GIIg725KmmNg"

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
