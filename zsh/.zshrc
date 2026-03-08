# ~/.zshrc

# --- ALIASES ---
alias ls='eza --icons --git'
alias ll='eza -lh --icons --git'
alias tree='eza --tree --icons'
alias grep='grep --color=auto'

# Hide tmux status bar when running apps
nvim() { tmux set status off; command nvim "$@"; tmux set status on; }
yazi() { tmux set status off; command yazi "$@"; tmux set status on; }

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
