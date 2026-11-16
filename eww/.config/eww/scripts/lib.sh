#!/usr/bin/env bash
# Shared guards for the panel's poll scripts. Source, do not execute.
#
# WHY THIS EXISTS: a defpoll script that prints NOTHING is the panel's worst
# failure mode. eww stores the empty string, the next render does field access
# on a string (gpu.available, volume.sink), that throws, and eww blanks the
# WHOLE widget tree -- not just the one card. The panel goes blank or loses
# rows for no visible reason.
#
# It is easy to hit. nvidia-smi returns the literal "[N/A]" for fields it cannot
# read (during a driver reload, in some power states, for fields a card does not
# expose), jq then rejects it with "invalid JSON text passed to --argjson", and
# the script exits 2 having printed nothing to stdout. Reproduced on this
# machine, not theorised.
#
# So: every poll script pipes its output through emit_json with a complete
# fallback object, and sanitises numbers with num() before handing them to jq.

# num <value> [default] -- echo the value if it is a plain number, else default.
# Guards against "[N/A]", "N/A", "", "unknown" and anything else non-numeric.
num() {
    local v="${1:-}" d="${2:-0}"
    case "$v" in
        ''|*[!0-9.-]*) printf '%s' "$d" ;;
        *)             printf '%s' "$v" ;;
    esac
}

# emit_json <fallback> -- read candidate JSON on stdin, print it if it parses,
# otherwise print the fallback. Never prints nothing.
emit_json() {
    local fallback="$1" out
    out=$(cat)
    if [ -n "$out" ] && printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
        printf '%s\n' "$out"
    else
        printf '%s\n' "$fallback"
    fi
}
