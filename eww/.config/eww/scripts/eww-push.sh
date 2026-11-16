#!/usr/bin/env bash
# Push a value straight into a running eww instance: eww-push.sh <var> <value>
#
# WHY: every control in the panel used to wait for its defpoll to come round
# before the UI changed -- volume on a 1s interval, toggles and brightness on
# 2s. Clicking a tile therefore did nothing visible for up to two seconds, which
# read as the panel being slow when it was really just idle. The action scripts
# now hand eww the new state the moment they finish, and the poll stays on as a
# safety net for changes made outside the panel.
#
# Silent and non-fatal by design: if eww is not running this must not fail the
# action itself, and it must NOT start a daemon as a side effect -- `eww update`
# alone would. `eww ping` is the guard.
set -uo pipefail

[ -n "${1:-}" ] || exit 0
eww ping >/dev/null 2>&1 || exit 0
eww update "$1=${2:-}" >/dev/null 2>&1 || true
