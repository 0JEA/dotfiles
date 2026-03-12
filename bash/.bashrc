# ~/.bashrc

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# --- FUNCTIONS ---
export GEMINI_API_KEY="AIzaSyD83Gg8FLpOkZgv5lXmh_9qqP7kJHzUSn0"
gem() {
  local sys="You are a concise terminal assistant. The user is in a terminal. Keep answers short and direct. No filler, no affirmations, no unnecessary markdown. Use plain text by default — only use code blocks or lists when they genuinely help. Always answer the question directly — never respond with a shell command when the user asked a factual question."
  local res
  res=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$GEMINI_API_KEY" \
    -H 'Content-Type: application/json' \
    -d "$(jq -n --arg sys "$sys" --arg user "$*" \
      '{systemInstruction:{parts:[{text:$sys}]},contents:[{role:"user",parts:[{text:$user}]}]}')")
  if echo "$res" | jq -e '.candidates' &>/dev/null; then
    echo "$res" | jq -r '[.candidates[0].content.parts[] | select(.text)] | last | .text'
  else
    echo "$res" | jq -r '.error.message // "Unknown error"' >&2
  fi
}

# --- ALIASES ---
alias ls='eza --icons --git'
alias ll='eza -lh --icons --git'
alias tree='eza --tree --icons'
alias grep='grep --color=auto'
alias qutebrowser='setsid qutebrowser &'
alias pep9='setsid env QT_QPA_PLATFORM=xcb JAVA_TOOL_OPTIONS="-Dawt.useSystemAAFontSettings=lcd -Dswing.aatext=true -Dsun.java2d.xrender=true -Dsun.java2d.uiScale=1.5 -Dswing.defaultlaf=com.sun.java.swing.plaf.gtk.GTKLookAndFeel" ~/applications/pep.AppImage &'

# --- STARSHIP PROMPT ---
eval "$(starship init bash)"

# --- AUTO-TMUX ---
# Use "exec" to replace the bash process with tmux.
# When you exit tmux, the terminal window will close.
if [[ -z "$TMUX" ]] && [[ "$TERM" != "linux" ]]; then
  exec tmux new-session
fi
export PATH="$HOME/.local/bin:$PATH"
