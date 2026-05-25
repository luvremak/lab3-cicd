#!/usr/bin/env bash
# verify.sh — post-deploy smoke tests, run on the target node via SSH.
#
# Exits non-zero on the first failed check; fails the CD workflow.
# Each check prints PASS/FAIL with a short reason.
#
# Checks (per the assignment requirements):
#   * Service availability via the reverse proxy (port 80)
#   * nginx routing rules from Lab 1:
#       - GET /            → 200 + text/html  (root, HTML only)
#       - GET /items       → 200              (business endpoint reachable)
#       - GET /health/*    → 404              (probes hidden from clients)
#       - GET /random_path → 404              (no catch-all leak)
#   * POST /items → GET /items round-trip (DB write actually reaches the DB)

set -uo pipefail   # NOT -e: we want to run all checks and tally results

BASE="http://127.0.0.1"
FAIL=0
PASS=0

note() { printf "  %s\n" "$*"; }
pass() { PASS=$((PASS + 1)); printf "[PASS] %s\n" "$*"; }
fail() { FAIL=$((FAIL + 1)); printf "[FAIL] %s\n" "$*" >&2; }

# --- helper: status-code check ----------------------------------------------
check_status() {
    local label="$1" url="$2" expected="$3" accept="${4:-}"
    local headers=()
    [ -n "$accept" ] && headers=(-H "Accept: ${accept}")
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" "${headers[@]}" "$url")
    if [ "$code" = "$expected" ]; then
        pass "$label (got $code)"
    else
        fail "$label (expected $expected, got $code)"
    fi
}

echo "=== mywebapp deployment verification ==="
echo

# --- 1. service availability ------------------------------------------------
check_status "service reachable via nginx (GET /items)" \
             "${BASE}/items" 200

# --- 2. nginx routing -------------------------------------------------------
check_status "root returns HTML (Accept: text/html)" \
             "${BASE}/" 200 "text/html"

content_type=$(curl -s -o /dev/null -w "%{content_type}" -H "Accept: text/html" "${BASE}/")
if echo "$content_type" | grep -q "text/html"; then
    pass "root Content-Type is text/html (got: $content_type)"
else
    fail "root Content-Type should contain text/html (got: $content_type)"
fi

check_status "/health/alive is hidden by nginx" \
             "${BASE}/health/alive" 404
check_status "/health/ready is hidden by nginx" \
             "${BASE}/health/ready" 404
check_status "unknown path returns 404"  \
             "${BASE}/no-such-endpoint" 404

# --- 3. round-trip: POST then GET (DB connectivity) ------------------------
post_code=$(curl -s -o /tmp/verify_post.json -w "%{http_code}" \
    -X POST -H "Content-Type: application/json" \
    -d "{\"name\":\"verify-$$\",\"quantity\":1}" \
    "${BASE}/items")
if [ "$post_code" = "201" ]; then
    pass "POST /items returns 201"
    item_id=$(python3 -c 'import json; print(json.load(open("/tmp/verify_post.json"))["id"])' 2>/dev/null || echo "")
    if [ -n "$item_id" ]; then
        get_code=$(curl -s -o /dev/null -w "%{http_code}" "${BASE}/items/${item_id}")
        [ "$get_code" = "200" ] \
            && pass "GET /items/${item_id} returns 200 (DB write was persisted)" \
            || fail "GET /items/${item_id} returns $get_code (DB write may not have persisted)"
    else
        fail "POST /items did not return a parseable id"
    fi
else
    fail "POST /items returned $post_code (expected 201)"
fi
rm -f /tmp/verify_post.json

# --- 4. nginx config sanity (optional, requires sudo) ----------------------
if sudo -n nginx -t >/dev/null 2>&1; then
    pass "nginx configuration is syntactically valid (nginx -t)"
else
    note "nginx -t skipped (no sudo)"
fi

echo
echo "=== summary: ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ] || exit 1
