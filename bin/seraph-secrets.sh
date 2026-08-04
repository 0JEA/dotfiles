#!/usr/bin/env bash
# seraph-secrets.sh — one home for Seraph credentials, and a way to PROVE they work.
#
# WHY THIS EXISTS (2026-08-03): credentials kept going missing, and worse, kept being
# believed. Two separate failures, both real:
#   1. A gitignored file was the ONLY copy. `backend/.env.studio-platform-dev-0jea` held
#      OUTBOUND_ALLOWLIST nowhere else, so a full deploy silently DELETED the dev safety rail.
#   2. Existence was mistaken for validity. RESEND_API_KEY was "set" for weeks while every send
#      failed; TWILIO creds are "set" right now and 401 on every call. A secret being present
#      proves nothing. Only exercising it proves anything (CLAUDE.md rule 5).
#
# So this script does exactly two jobs: keep credentials in TWO places that are not a
# gitignored file, and EXERCISE them on demand.
#
# Storage:
#   - Local keychain: libsecret / gnome-keyring via `secret-tool`, attribute service=seraph.
#     Readable unattended while the login keyring is unlocked. No install needed.
#   - Cloud:          Google Secret Manager on studio-platform-dev-0jea. This is the copy that
#     actually feeds the deployed Functions, so it is the source of truth for runtime.
#
# SECURITY, PLAINLY: anything running as this user can read the unlocked keyring. That is the
# price of unattended access and you should know you are paying it. Do not put a Stripe LIVE
# key in here without deciding you are comfortable with that.

set -uo pipefail

PROJECT="studio-platform-dev-0jea"
GCLOUD="$HOME/google-cloud-sdk/bin/gcloud"
SERVICE="seraph"

die() { echo "error: $*" >&2; exit 1; }
have_gcloud() { [ -x "$GCLOUD" ]; }

usage() {
  cat <<'EOF'
seraph-secrets.sh — store, retrieve and VERIFY Seraph credentials

  put <NAME>            read a value from stdin, store in keyring + Secret Manager
                        (stdin so the value never lands in shell history)
  get <NAME>            print value: keyring first, Secret Manager as fallback
  list                  names known to Secret Manager, and whether each is mirrored locally
  check                 EXERCISE Resend / Stripe / Twilio and report VALID or INVALID
  pull                  copy every Secret Manager secret into the local keyring
  backup-env            mirror the gitignored backend/.env.<project> into the keyring
  restore-env           write that env file back out from the keyring

Examples:
  printf '%s' 'SK...' | ~/bin/seraph-secrets.sh put STRIPE_SECRET_KEY
  ~/bin/seraph-secrets.sh check
EOF
}

kc_put() { printf '%s' "$2" | secret-tool store --label="seraph:$1" service "$SERVICE" name "$1"; }
kc_get() { secret-tool lookup service "$SERVICE" name "$1" 2>/dev/null; }

cmd_put() {
  local name="${1:-}"; [ -n "$name" ] || die "usage: put <NAME>"
  local val; val="$(cat)"
  [ -n "$val" ] || die "empty value on stdin"
  kc_put "$name" "$val" || die "keyring write failed"
  echo "keyring: stored $name (${#val} chars)"
  if have_gcloud; then
    if "$GCLOUD" secrets describe "$name" --project="$PROJECT" >/dev/null 2>&1; then
      printf '%s' "$val" | "$GCLOUD" secrets versions add "$name" --project="$PROJECT" --data-file=- >/dev/null 2>&1 \
        && echo "secret manager: new version added" || echo "secret manager: FAILED"
    else
      "$GCLOUD" secrets create "$name" --project="$PROJECT" --replication-policy=automatic >/dev/null 2>&1
      printf '%s' "$val" | "$GCLOUD" secrets versions add "$name" --project="$PROJECT" --data-file=- >/dev/null 2>&1 \
        && echo "secret manager: created + first version" || echo "secret manager: FAILED"
    fi
    echo "NOTE: Functions read a PINNED version. Redeploy the consumers for this to take effect."
  fi
}

cmd_get() {
  local name="${1:-}"; [ -n "$name" ] || die "usage: get <NAME>"
  local v; v="$(kc_get "$name")"
  if [ -n "$v" ]; then printf '%s\n' "$v"; return 0; fi
  have_gcloud || die "not in keyring and gcloud unavailable"
  "$GCLOUD" secrets versions access latest --secret="$name" --project="$PROJECT" 2>/dev/null \
    || die "not found in keyring or Secret Manager: $name"
}

cmd_pull() {
  have_gcloud || die "gcloud not found"
  local n=0
  while read -r s; do
    [ -n "$s" ] || continue
    local v; v="$("$GCLOUD" secrets versions access latest --secret="$s" --project="$PROJECT" 2>/dev/null)"
    [ -n "$v" ] && kc_put "$s" "$v" && n=$((n+1))
  done < <("$GCLOUD" secrets list --project="$PROJECT" --format='value(name.basename())' 2>/dev/null)
  echo "mirrored $n secrets into the local keyring"
}

cmd_list() {
  have_gcloud || die "gcloud not found"
  printf '%-32s %-18s %s\n' NAME "IN KEYRING" "SECRET MANAGER"
  while read -r s; do
    [ -n "$s" ] || continue
    local local_has="no"; [ -n "$(kc_get "$s")" ] && local_has="yes"
    printf '%-32s %-18s %s\n' "$s" "$local_has" "yes"
  done < <("$GCLOUD" secrets list --project="$PROJECT" --format='value(name.basename())' 2>/dev/null)
}

# ── The important one: prove the credentials actually work ───────────────────
cmd_check() {
  local fail=0
  echo "Exercising credentials. Existence is not validity."
  echo

  local rk; rk="$(cmd_get RESEND_API_KEY 2>/dev/null)"
  if [ -n "$rk" ]; then
    local out; out="$(curl -s -m 20 -o /tmp/.ss_resend -w '%{http_code}' -H "Authorization: Bearer $rk" https://api.resend.com/domains)"
    if [ "$out" = "200" ]; then
      echo "  RESEND      ✅ VALID   $(node -e 'try{const d=JSON.parse(require("fs").readFileSync("/tmp/.ss_resend","utf8"));const a=(d.data||d)[0]||{};console.log(a.name+" status="+a.status+" sending="+((a.capabilities||{}).sending))}catch(e){console.log("")}' 2>/dev/null)"
    else echo "  RESEND      🔴 INVALID (HTTP $out)"; fail=1; fi
  else echo "  RESEND      ⚠️  not stored"; fi

  local sk; sk="$(cmd_get STRIPE_SECRET_KEY 2>/dev/null)"
  if [ -n "$sk" ]; then
    local out; out="$(curl -s -m 20 -o /tmp/.ss_stripe -w '%{http_code}' -u "$sk:" https://api.stripe.com/v1/account)"
    local mode="LIVE"; case "$sk" in sk_test_*) mode="TEST";; esac
    if [ "$out" = "200" ]; then
      echo "  STRIPE      ✅ VALID   mode=$mode  $(node -e 'try{const d=JSON.parse(require("fs").readFileSync("/tmp/.ss_stripe","utf8"));console.log(d.id+" "+d.country+" charges="+d.charges_enabled)}catch(e){console.log("")}' 2>/dev/null)"
      [ "$mode" = "TEST" ] && echo "              ⚠️  TEST mode — no real money can move"
    else echo "  STRIPE      🔴 INVALID (HTTP $out)"; fail=1; fi
  else echo "  STRIPE      ⚠️  not stored"; fi

  local ts tk tsec tfrom
  ts="$(cmd_get TWILIO_ACCOUNT_SID 2>/dev/null)"; tk="$(cmd_get TWILIO_API_KEY_SID 2>/dev/null)"
  tsec="$(cmd_get TWILIO_API_KEY_SECRET 2>/dev/null)"; tfrom="$(cmd_get TWILIO_SMS_FROM 2>/dev/null)"
  if [ -n "$ts" ] && [ -n "$tk" ]; then
    local out; out="$(curl -s -m 20 -o /dev/null -w '%{http_code}' -u "$tk:$tsec" "https://api.twilio.com/2010-04-01/Accounts/$ts.json")"
    if [ "$out" = "200" ]; then echo "  TWILIO      ✅ VALID   from=$tfrom"
    else echo "  TWILIO      🔴 INVALID (HTTP $out) — SMS cannot send"; fail=1; fi
    case "$tfrom" in
      +1500555*) echo "              🔴 from-number is a Twilio MAGIC TEST number, not a real line";;
    esac
  else echo "  TWILIO      ⚠️  not stored"; fi

  rm -f /tmp/.ss_resend /tmp/.ss_stripe
  echo
  [ "$fail" = "0" ] && echo "All stored credentials exercised OK." || echo "At least one credential is DEAD. Do not trust any doc that says otherwise."
  return "$fail"
}

ENVFILE="$HOME/websites/sp-design/backend/.env.$PROJECT"

cmd_backup_env() {
  [ -f "$ENVFILE" ] || die "no env file at $ENVFILE"
  kc_put "ENVFILE_$PROJECT" "$(cat "$ENVFILE")" || die "keyring write failed"
  echo "backed up $ENVFILE into the keyring ($(wc -l < "$ENVFILE") lines)"
  echo "this file is GITIGNORED — the keyring is now its second copy, so a deploy cannot make it the only one"
}

cmd_restore_env() {
  local v; v="$(kc_get "ENVFILE_$PROJECT")"
  [ -n "$v" ] || die "no env backup in keyring"
  [ -f "$ENVFILE" ] && cp "$ENVFILE" "$ENVFILE.bak-$(date +%F-%H%M%S)"
  printf '%s' "$v" > "$ENVFILE"
  echo "restored $ENVFILE from keyring (previous copy saved alongside as .bak-*)"
}

case "${1:-}" in
  put) shift; cmd_put "$@";;
  get) shift; cmd_get "$@";;
  list) cmd_list;;
  check) cmd_check;;
  pull) cmd_pull;;
  backup-env) cmd_backup_env;;
  restore-env) cmd_restore_env;;
  *) usage;;
esac
