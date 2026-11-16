# LAPTOP shell setup. Sourced by ~/.bashrc via ~/.config/bash/machine.sh.

# SSH agent for the rosecityogs deploy key.
# ONE persistent agent per login, via socket-activated `systemctl --user ssh-agent.socket`.
# Do NOT spawn a per-shell agent here: that re-decrypted the passphrase-protected
# deploy key on EVERY new terminal (~475ms of KDF blocking the prompt) and leaked
# one ssh-agent process + socket per window. Measured 2026-08-28: 519ms -> 47ms.
[ -z "$SSH_AUTH_SOCK" ] && export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$UID}/ssh-agent.socket"
# Load the key off the critical path so it never blocks the prompt.
if ! ssh-add -l 2>/dev/null | grep -q rosecityogs; then
  { SSH_ASKPASS="$HOME/websites/.ssh_askpass.sh" SSH_ASKPASS_REQUIRE=force DISPLAY=dummy \
      ssh-add "$HOME/websites/rosecityogs_deploy_key" < /dev/null 2>/dev/null; } &
  disown 2>/dev/null
fi

alias r5rs='plt-r5rs'
export PATH="$HOME/bin:$PATH"   # local scripts (repo-health.sh, seraph-secrets.sh)
