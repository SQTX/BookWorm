#!/usr/bin/env bash
#
# Exercise a deployed BookWorm API end to end, from outside the server.
#
#   ./smoke-test.sh https://api.example.com you@example.com
#
# Prompts for the password rather than taking it as an argument: arguments end
# up in shell history and in the process list, where any other user on the
# machine can read them.
#
# Everything it creates is deleted before it exits, so it is safe to run against
# a live instance — though on a server that already holds real data you are
# still writing to the same database, so prefer a moment when nothing else is
# syncing.

set -euo pipefail

API="${1:-}"
EMAIL="${2:-}"

if [ -z "$API" ] || [ -z "$EMAIL" ]; then
    echo "usage: $0 <api-url> <email>" >&2
    exit 1
fi

read -rsp "password for $EMAIL: " PASSWORD
echo

# Extract one field from a JSON body without assuming jq is installed.
json() { python3 -c "import sys,json;print(json.load(sys.stdin).get('$1',''))"; }

pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; exit 1; }

echo
echo "→ $API"
echo

# --- reachable and healthy ---------------------------------------------------
health=$(curl -fsS --max-time 15 "$API/health" || echo '{}')
[ "$(echo "$health" | json status)" = "ok" ] \
    && pass "health: ok" \
    || fail "health returned: $health (503 means the database is unreachable)"

# --- anonymous access is refused ---------------------------------------------
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$API/v1/books")
[ "$code" = "401" ] && pass "anonymous /v1/books: 401" || fail "expected 401, got $code"

# --- login -------------------------------------------------------------------
login=$(curl -fsS --max-time 15 "$API/v1/auth/login" \
    -H 'content-type: application/json' \
    --data-raw "$(python3 -c "import json,sys;print(json.dumps({'email':sys.argv[1],'password':sys.argv[2]}))" "$EMAIL" "$PASSWORD")" \
    || echo '{}')

TOKEN=$(echo "$login" | json accessToken)
REFRESH=$(echo "$login" | json refreshToken)
[ -n "$TOKEN" ] && pass "login: token issued" || fail "login rejected — wrong email or password"

AUTH="authorization: Bearer $TOKEN"

# --- create ------------------------------------------------------------------
created=$(curl -fsS --max-time 15 "$API/v1/books" -H "$AUTH" \
    -H 'content-type: application/json' \
    --data-raw '{"title":"Smoke test","author":"smoke-test","pageCount":300,"status":"reading"}')

BOOK_ID=$(echo "$created" | json id)
[ -n "$BOOK_ID" ] && pass "create book: id $BOOK_ID" || fail "create failed: $created"

# --- progress writes a reading session ---------------------------------------
progress=$(curl -fsS --max-time 15 "$API/v1/books/$BOOK_ID/progress" -H "$AUTH" \
    -H 'content-type: application/json' --data-raw '{"currentPage":42}')

[ "$(echo "$progress" | json pagesRead)" = "42" ] \
    && pass "progress: 42 pages recorded" \
    || fail "progress failed: $progress"

# --- sync sees it ------------------------------------------------------------
sync=$(curl -fsS --max-time 20 "$API/v1/sync" -H "$AUTH")
echo "$sync" | grep -q 'Smoke test' \
    && pass "sync: the book appears in the change feed" \
    || fail "sync did not return the book"

echo "$sync" | grep -q 'serverTime' \
    && pass "sync: server cursor returned" \
    || fail "sync response has no serverTime"

# --- token refresh rotates ---------------------------------------------------
refreshed=$(curl -fsS --max-time 15 "$API/v1/auth/refresh" \
    -H 'content-type: application/json' \
    --data-raw "$(python3 -c "import json,sys;print(json.dumps({'refreshToken':sys.argv[1]}))" "$REFRESH")")

NEW_REFRESH=$(echo "$refreshed" | json refreshToken)
[ -n "$NEW_REFRESH" ] && [ "$NEW_REFRESH" != "$REFRESH" ] \
    && pass "refresh: token rotated" \
    || fail "refresh did not rotate the token"

# --- clean up ----------------------------------------------------------------
curl -fsS -o /dev/null --max-time 15 -X DELETE "$API/v1/books/$BOOK_ID" -H "$AUTH"
gone=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$API/v1/books/$BOOK_ID" -H "$AUTH")
[ "$gone" = "404" ] && pass "delete: book removed" || fail "book still readable after delete ($gone)"

curl -fsS -o /dev/null --max-time 15 "$API/v1/auth/logout" \
    -H 'content-type: application/json' \
    --data-raw "$(python3 -c "import json,sys;print(json.dumps({'refreshToken':sys.argv[1]}))" "$NEW_REFRESH")"
pass "logout: session revoked"

echo
echo "All checks passed. The API is reachable, authenticated and writing."
