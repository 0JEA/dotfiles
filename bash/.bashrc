# ~/.bashrc

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# --- ALIASES ---
alias ls='eza --icons --git'
alias ll='eza -lh --icons --git'
alias tree='eza --tree --icons'
alias grep='grep --color=auto'

# Hide tmux status bar when running apps
nvim() { tmux set status off; command nvim "$@"; tmux set status on; }
yazi() { tmux set status off; command yazi "$@"; tmux set status on; }

# --- STARSHIP PROMPT ---
eval "$(starship init bash)"

# --- AUTO-TMUX ---
# Use "exec" to replace the bash process with tmux.
# When you exit tmux, the terminal window will close.
if [[ -z "$TMUX" ]] && [[ "$TERM" != "linux" ]]; then
    exec tmux new-session
fi
export PATH="$HOME/.local/bin:$PATH"
