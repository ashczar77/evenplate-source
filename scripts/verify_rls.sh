#!/usr/bin/env bash
# Verifies that the entitlement hardening in supabase/schema.sql is actually
# live on a Supabase project. Run this after applying the schema.
#
# Usage:
#   scripts/verify_rls.sh                  # reads SUPABASE_URL / SUPABASE_ANON_KEY from .env
#   SUPABASE_TEST_JWT=<token> scripts/verify_rls.sh
#
# Supply SUPABASE_TEST_JWT for a disposable verified test account.
# make test-db uses transaction fixtures and does not need a customer token.
#
# Read only apart from one deliberate consume_scan_credit call, which spends a
# single free scan belonging to the throwaway test user.

set -uo pipefail

ENV_FILE="${ENV_FILE:-.env}"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a && source "$ENV_FILE" && set +a
fi

: "${SUPABASE_URL:?Set SUPABASE_URL (or put it in .env)}"
: "${SUPABASE_ANON_KEY:?Set SUPABASE_ANON_KEY (or put it in .env)}"

BASE="${SUPABASE_URL%/}"
PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '  PASS  %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '  FAIL  %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
info() { printf '        %s\n' "$1"; }

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "This script needs jq. Install it with: brew install jq" >&2
    exit 1
  fi
}
require_jq

# Obtain an access token.
TOKEN="${SUPABASE_TEST_JWT:-}"
if [[ -z "$TOKEN" ]]; then
  echo "Set SUPABASE_TEST_JWT for a disposable verified test account." >&2
  echo "Use make test-db for transactional regression checks. Keep anonymous signup disabled." >&2
  exit 1
fi

UID_VALUE=$(curl -s "$BASE/auth/v1/user" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $TOKEN" | jq -r '.id // empty')

if [[ -z "$UID_VALUE" ]]; then
  echo "Token was rejected by /auth/v1/user. Is it expired?" >&2
  exit 1
fi

echo "Verifying entitlement hardening on $BASE"
echo "Acting as user $UID_VALUE"
echo

rest() {
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -s -o /tmp/rls_body -w '%{http_code}' -X "$method" "$BASE/rest/v1/$path" \
      -H "apikey: $SUPABASE_ANON_KEY" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -H "Prefer: return=representation" \
      -d "$body"
  else
    curl -s -o /tmp/rls_body -w '%{http_code}' -X "$method" "$BASE/rest/v1/$path" \
      -H "apikey: $SUPABASE_ANON_KEY" \
      -H "Authorization: Bearer $TOKEN"
  fi
}

echo "1. Self-granting Pro must be rejected"
CODE=$(rest PATCH "profiles?id=eq.$UID_VALUE" '{"is_pro":true}')
BODY=$(cat /tmp/rls_body)
# Re-read is the source of truth: a 200 with no rows is also a successful block.
CODE_READ=$(rest GET "profiles?id=eq.$UID_VALUE&select=is_pro,free_scans_remaining")
# Read the value with tostring rather than the // operator, which treats a
# legitimate false as absent and would report it as "unknown".
IS_PRO=$(jq -r 'if length == 0 then "no-row" else (.[0].is_pro | tostring) end' /tmp/rls_body)
if [[ "$IS_PRO" == "true" ]]; then
  fail "is_pro is now true. The privilege escalation is still open."
  info "PATCH returned $CODE: $BODY"
else
  pass "is_pro remained $IS_PRO after a self-grant attempt (PATCH got $CODE)"
fi
[[ "$CODE_READ" == "200" ]] || info "note: profile re-read returned $CODE_READ"

echo
echo "2. Awarding free scans to yourself must be rejected"
CODE=$(rest PATCH "profiles?id=eq.$UID_VALUE" '{"free_scans_remaining":999}')
BODY=$(cat /tmp/rls_body)
rest GET "profiles?id=eq.$UID_VALUE&select=free_scans_remaining" >/dev/null
REMAINING=$(jq -r 'if length == 0 then "no-row" else (.[0].free_scans_remaining | tostring) end' /tmp/rls_body)
if [[ "$REMAINING" == "999" ]]; then
  fail "free_scans_remaining was set to 999 by the client."
  info "PATCH returned $CODE: $BODY"
else
  pass "free_scans_remaining stayed at $REMAINING (PATCH got $CODE)"
fi

echo
echo "3. Refund function must not be callable by end users"
CODE=$(rest POST "rpc/refund_scan_credit" "{\"p_user_id\":\"$UID_VALUE\",\"p_purchased\":false}")
BODY=$(cat /tmp/rls_body)
if [[ "$CODE" == "200" ]]; then
  fail "refund_scan_credit executed as an ordinary user. Scans can be minted."
  info "Response: $BODY"
else
  pass "refund_scan_credit refused with HTTP $CODE"
fi

echo
echo "4. Other users' profiles must not be readable"
CODE=$(rest GET "profiles?select=id")
ROWS=$(jq -r 'if type=="array" then length else -1 end' /tmp/rls_body)
if [[ "$ROWS" -gt 1 ]]; then
  fail "Able to read $ROWS profile rows. RLS is not isolating users."
elif [[ "$ROWS" -lt 0 ]]; then
  fail "Unexpected response reading profiles (HTTP $CODE): $(cat /tmp/rls_body)"
else
  pass "Only $ROWS profile row visible"
fi

echo
echo "5. consume_scan_credit must exist and be callable (spends 1 credit)"
CODE=$(rest POST "rpc/consume_scan_credit" '{}')
BODY=$(cat /tmp/rls_body)
if [[ "$CODE" != "200" ]]; then
  fail "consume_scan_credit returned HTTP $CODE: $BODY"
  info "Has supabase/schema.sql been applied to this project?"
else
  # has("allowed") rather than // so that a genuine allowed=false, which is what
  # an exhausted quota returns, is not misreported as a malformed response.
  ALLOWED=$(printf '%s' "$BODY" | jq -r 'if has("allowed") then (.allowed | tostring) else "missing" end')
  if [[ "$ALLOWED" == "missing" ]]; then
    fail "consume_scan_credit returned no 'allowed' field: $BODY"
  else
    pass "consume_scan_credit responded allowed=$ALLOWED ($BODY)"
  fi
fi

echo
echo "6. The profile must be entirely read only, including email"
# Confirms the table level revoke also cleared the old update (email) column
# grant, which is the only reason the column privilege is gone.
SENTINEL="rls-probe-$UID_VALUE@example.invalid"
CODE=$(rest PATCH "profiles?id=eq.$UID_VALUE" "{\"email\":\"$SENTINEL\"}")
BODY=$(cat /tmp/rls_body)
rest GET "profiles?id=eq.$UID_VALUE&select=email" >/dev/null
EMAIL=$(jq -r 'if length == 0 then "no-row" else (.[0].email | tostring) end' /tmp/rls_body)
if [[ "$EMAIL" == "$SENTINEL" ]]; then
  fail "email was rewritten by the client. The update grant is still live."
  info "PATCH returned $CODE: $BODY"
else
  pass "email stayed $EMAIL (PATCH got $CODE)"
fi

echo
echo "7. A client must not be able to stamp promo_pro_until on itself"
CODE=$(rest PATCH "profiles?id=eq.$UID_VALUE" '{"promo_pro_until":"2099-01-01T00:00:00Z"}')
BODY=$(cat /tmp/rls_body)
rest GET "profiles?id=eq.$UID_VALUE&select=promo_pro_until" >/dev/null
PROMO=$(jq -r 'if length == 0 then "no-row" else (.[0].promo_pro_until | tostring) end' /tmp/rls_body)
if [[ "$PROMO" == "2099-01-01T00:00:00Z" || "$PROMO" == "2099-01-01T00:00:00+00:00" ]]; then
  fail "promo_pro_until was rewritten by the client."
  info "PATCH returned $CODE: $BODY"
else
  pass "promo_pro_until stayed $PROMO (PATCH got $CODE)"
fi

echo
echo "8. Guessing a promo code must not grant Pro"
CODE=$(rest POST "rpc/redeem_promo_code" '{"p_code":"SHIPATON2026"}')
BODY=$(cat /tmp/rls_body)
REDEEMED=$(printf '%s' "$BODY" | jq -r 'if type=="object" and has("redeemed") then (.redeemed | tostring) else "missing" end')
if [[ "$REDEEMED" == "true" ]]; then
  fail "A guessed code granted Pro. Response: $BODY"
else
  pass "guessed code refused (HTTP $CODE, redeemed=$REDEEMED)"
fi

echo
echo "9. Promo code rows must not be readable by clients"
CODE=$(rest GET "promo_codes?select=*")
ROWS=$(jq -r 'if type=="array" then length else -1 end' /tmp/rls_body)
if [[ "$ROWS" -gt 0 ]]; then
  fail "Able to read $ROWS promo_codes rows."
  info "GET returned $CODE: $(cat /tmp/rls_body)"
else
  pass "promo_codes hidden from the client (HTTP $CODE)"
fi

echo
echo "-----"
printf 'passed: %s   failed: %s\n' "$PASS_COUNT" "$FAIL_COUNT"
if [[ "$FAIL_COUNT" -gt 0 ]]; then
  echo "Apply supabase/schema.sql to this project, then re-run." >&2
  exit 1
fi
echo "Entitlement hardening looks correct."
