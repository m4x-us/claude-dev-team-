#!/usr/bin/env bash
# ===========================================
# SHIPPING GATE — Quality Enforcement Gate
# ===========================================
# Run this after every feature. Paste the output
# into the conversation. The output IS the report.
# You cannot fake what a script prints.
#
# Exit codes:
#   0 = all checks passed
#   1 = one or more checks FAILED (do not ship)
#
# Usage: bash scripts/shipping-gate.sh [directory]
# Example: bash scripts/shipping-gate.sh apps/web/src/app/api/sms
# ===========================================

set -uo pipefail

TARGET_DIR="${1:-.}"
FAIL_COUNT=0

echo "=== SHIPPING GATE REPORT ==="
echo "Directory: $TARGET_DIR"
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# ===========================================
# SECTION 1: Anti-pattern scan
# ===========================================
echo "--- ANTI-PATTERNS ---"

# Only flag truly empty catch bodies. TypeScript 4+ no-binding `catch {` with a non-empty body
# is valid (and required for observable error handling without an unused binding).
count=$(find "$TARGET_DIR" \( -name '*.ts' -o -name '*.tsx' \) 2>/dev/null \
  | grep -v '\.test\.' | grep -v node_modules | sort | while read -r f; do
    [ -f "$f" ] || continue
    grep -E 'catch\s*\{\s*\}' "$f" 2>/dev/null
    awk '
      /catch[[:space:]]*\{[[:space:]]*$/ { in_catch=1; empty=1; next }
      in_catch && /[^[:space:]{}]/ { empty=0 }
      in_catch && /}/ { if(empty) print "empty_catch"; in_catch=0; empty=0 }
    ' "$f" 2>/dev/null
  done | wc -l | tr -d ' ')
echo "Bare catches: $count $([ "$count" = "0" ] && echo '✓' || echo '✗ FAIL')"
[ "$count" != "0" ] && FAIL_COUNT=$((FAIL_COUNT + 1))

count=$(grep -rn 'dangerouslySetInnerHTML' "$TARGET_DIR" --include='*.tsx' 2>/dev/null | grep -v '\.test\.' | wc -l | tr -d ' ')
echo "dangerouslySetInnerHTML: $count $([ "$count" = "0" ] && echo '✓' || echo '✗ FAIL')"
[ "$count" != "0" ] && FAIL_COUNT=$((FAIL_COUNT + 1))

count=$(grep -rn 'eval(' "$TARGET_DIR" --include='*.ts' --include='*.tsx' 2>/dev/null | grep -v '\.test\.' | wc -l | tr -d ' ')
echo "eval(): $count $([ "$count" = "0" ] && echo '✓' || echo '✗ FAIL')"
[ "$count" != "0" ] && FAIL_COUNT=$((FAIL_COUNT + 1))

count=$(grep -rn 'alert(' "$TARGET_DIR" --include='*.tsx' 2>/dev/null | grep -v '\.test\.' | wc -l | tr -d ' ')
echo "alert(): $count $([ "$count" = "0" ] && echo '✓' || echo '✗ FAIL')"
[ "$count" != "0" ] && FAIL_COUNT=$((FAIL_COUNT + 1))

count=$(grep -rn "process\.env\.\w* || ''" "$TARGET_DIR" --include='*.ts' --include='*.tsx' 2>/dev/null | grep -v '\.test\.' | wc -l | tr -d ' ')
echo "process.env || '' fallback: $count $([ "$count" = "0" ] && echo '✓' || echo '✗ WARN')"
# WARN only — not a FAIL_COUNT increment

_ta_overflow=0
while IFS= read -r _f; do
  if grep -q '<textarea' "$_f" 2>/dev/null && grep -q 'overflow-hidden' "$_f" 2>/dev/null; then
    _ta_overflow=$((_ta_overflow + 1))
  fi
done < <(find "$TARGET_DIR" -name "*.tsx" -not -path "*/node_modules/*" 2>/dev/null | grep -v '\.test\.')
echo "textarea overflow-hidden (clips content): $_ta_overflow $([ "$_ta_overflow" = "0" ] && echo '✓' || echo '✗ FAIL')"
[ "$_ta_overflow" != "0" ] && FAIL_COUNT=$((FAIL_COUNT + 1))

# Email subject/snippet are normalized at fetch boundary via normalizeEmailMessage/List.
# Display components must render email.subject and email.snippet directly — no decoding needed.
# If decodeHtmlEntities appears on .subject or .snippet in a display component, the data
# was not normalized at the fetch boundary and entities could appear raw in other code paths.
_raw_display=$(grep -rn "decodeHtmlEntities.*\.subject\b\|decodeHtmlEntities.*\.snippet\b" \
  "$TARGET_DIR" --include="*.tsx" 2>/dev/null | grep -v '\.test\.' | wc -l | tr -d ' ')
echo "decodeHtmlEntities on .subject/.snippet in display layer: $_raw_display $([ "$_raw_display" = "0" ] && echo '✓' || echo '✗ FAIL — normalize at fetch boundary via normalizeEmailMessage()')"
if [ "$_raw_display" != "0" ]; then
  FAIL_COUNT=$((FAIL_COUNT + 1))
  grep -rn "decodeHtmlEntities.*\.subject\b\|decodeHtmlEntities.*\.snippet\b" \
    "$TARGET_DIR" --include="*.tsx" 2>/dev/null | grep -v '\.test\.' | head -5
fi

# Raw <iframe srcDoc> in dashboard display components bypasses EmailBodyRenderer's
# keyboard forwarding, CSP, resize observer, and privacy protections.
# This check is scoped to apps/web/src/app/dashboard/ only — EmailBodyRenderer itself
# legitimately uses srcDoc to create the isolated iframe.
_dash_dir="apps/web/src/app/dashboard"
if [ -d "$_dash_dir" ]; then
  _raw_srcdoc=$(grep -rn 'srcDoc=' "$_dash_dir" --include="*.tsx" 2>/dev/null | grep -v '\.test\.' | wc -l | tr -d ' ')
  echo "Raw <iframe srcDoc> in display layer: $_raw_srcdoc $([ "$_raw_srcdoc" = "0" ] && echo '✓' || echo '✗ FAIL — use EmailBodyRenderer instead')"
  if [ "$_raw_srcdoc" != "0" ]; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
    grep -rn 'srcDoc=' "$_dash_dir" --include="*.tsx" 2>/dev/null | grep -v '\.test\.' | head -5
  fi
else
  echo "Raw <iframe srcDoc> in display layer: 0 ✓ (no dashboard dir in scope)"
fi

_zany_count=$(grep -rn 'z\.any()' "$TARGET_DIR" --include='*.ts' --include='*.tsx' 2>/dev/null | grep -v '\.test\.' | grep -E 'validation|schema' | wc -l | tr -d ' ')
echo "z.any() in validation schemas: $_zany_count $([ "$_zany_count" = "0" ] && echo '✓' || echo '✗ FAIL — use a typed z.object() or z.enum() schema')"
[ "$_zany_count" != "0" ] && FAIL_COUNT=$((FAIL_COUNT + 1))

echo ""

# ===========================================
# SECTION 2: Test coverage check
# ===========================================
echo "--- TEST COVERAGE ---"

ROUTE_FILES=$(find "$TARGET_DIR" -name "route.ts" -not -path "*/node_modules/*" -not -name "*.test.*" 2>/dev/null || true)
MISSING_TESTS=0
if [ -n "$ROUTE_FILES" ]; then
  while IFS= read -r f; do
    TEST_FILE="${f%.ts}.test.ts"
    if [[ -f "$TEST_FILE" ]]; then
      # Check the test file has at least 3 expect() calls
      EXPECT_COUNT=$(grep -c "expect(" "$TEST_FILE" 2>/dev/null || echo 0)
      if [ "$EXPECT_COUNT" -lt 3 ]; then
        echo "  ✗ $(echo "$f" | sed 's|.*/app/||') — TEST HAS ONLY $EXPECT_COUNT expect() call(s) (min 3)"
        MISSING_TESTS=$((MISSING_TESTS + 1))
      else
        echo "  ✓ $(echo "$f" | sed 's|.*/app/||') ($EXPECT_COUNT assertions)"
      fi
    else
      echo "  ✗ $(echo "$f" | sed 's|.*/app/||') — MISSING TEST"
      MISSING_TESTS=$((MISSING_TESTS + 1))
    fi
  done <<< "$ROUTE_FILES"
else
  echo "  No route files found in $TARGET_DIR"
fi
[ "$MISSING_TESTS" -gt 0 ] && FAIL_COUNT=$((FAIL_COUNT + MISSING_TESTS))

echo ""

# ===========================================
# SECTION 3: Auth & feature flag check
# ===========================================
echo "--- AUTH & FEATURE FLAGS ---"

AUTH_FAIL=0
if [ -n "$ROUTE_FILES" ]; then
  while IFS= read -r f; do
    short=$(echo "$f" | sed 's|.*/app/||')
    # manageToken = public scheduling endpoint secured by unguessable token (not session auth)
    # scheduling_oauth_state = OAuth callback secured by one-time cookie state (CSRF protected)
    # @/lib/cors = intentionally public endpoint for the booking widget (no session required)
    has_auth=$(grep -E 'requireSchedulingAuth|requireAuth|getSession|verifyTwilioSignature|verifyAcuitySecret|manageToken|scheduling_oauth_state|@/lib/cors|INTERNAL_API_SECRET' "$f" 2>/dev/null | wc -l | tr -d ' ')
    has_flag=$(grep -E 'requireFeature|isFeatureEnabled' "$f" 2>/dev/null | wc -l | tr -d ' ')

    auth_status="$([ "$has_auth" -gt 0 ] && echo 'auth ✓' || echo 'NO AUTH ✗')"
    flag_status="$([ "$has_flag" -gt 0 ] && echo 'flag ✓' || echo 'no flag')"

    echo "  $short: $auth_status | $flag_status"
    [ "$has_auth" -eq 0 ] && AUTH_FAIL=$((AUTH_FAIL + 1))
  done <<< "$ROUTE_FILES"
fi
[ "$AUTH_FAIL" -gt 0 ] && FAIL_COUNT=$((FAIL_COUNT + AUTH_FAIL))

echo ""

# ===========================================
# SECTION 4: Worker-specific checks
# ===========================================
if echo "$TARGET_DIR" | grep -q 'worker'; then
  echo "--- WORKER CHECKS ---"
  count=$(grep -rn 'organization.*findFirst' "$TARGET_DIR" --include='*.ts' 2>/dev/null | grep -v '//' | grep -v '\.test\.' | wc -l | tr -d ' ')
  echo "org.findFirst in code: $count $([ "$count" = "0" ] && echo '✓' || echo '✗ FAIL')"
  [ "$count" != "0" ] && FAIL_COUNT=$((FAIL_COUNT + 1))

  bang=$(grep -rn 'this\.redis!' "$TARGET_DIR" --include='*.ts' 2>/dev/null | grep -v '\.test\.' | wc -l | tr -d ' ')
  echo "this.redis! assertions: $bang $([ "$bang" = "0" ] && echo '✓' || echo '✗ FAIL')"
  [ "$bang" != "0" ] && FAIL_COUNT=$((FAIL_COUNT + 1))

  echo ""
fi

# ===========================================
# SECTION 5: Redis Stream Integrity
# ===========================================
# Runs only when the target directory contains Redis stream consumer files.
# Checks for the two most common ways to silently break at-least-once delivery:
#   A) Using a Redis stream command without a toHaveBeenCalledWith assertion
#      for that command — wrong args (stream key typo, bad consumer name) cause
#      silent message loss that passes all tests.
#   B) XPENDING without a pagination loop — a count-limited single call silently
#      drops all messages beyond the first batch when PEL > count limit.
REDIS_CONSUMER_FILES=$(find "$TARGET_DIR" -name "*.ts" -not -name "*.test.*" \
  -not -path "*/node_modules/*" 2>/dev/null \
  | xargs grep -l "'XREADGROUP'\|'XPENDING'\|'XCLAIM'" 2>/dev/null || true)

if [ -n "$REDIS_CONSUMER_FILES" ]; then
  echo "--- REDIS STREAM INTEGRITY ---"
  REDIS_FAIL=0

  while IFS= read -r f; do
    [ -z "$f" ] && continue
    short=$(basename "$f")
    test_file="${f%.ts}.test.ts"

    if [ ! -f "$test_file" ]; then
      echo "  ✗ $short — no test file (all Redis command args are unverified)"
      REDIS_FAIL=$((REDIS_FAIL + 1))
      continue
    fi

    # Per-command assertion check (A):
    # Looks for the command string as a quoted TypeScript literal in the test file.
    # 'COMMAND' (with single quotes) only appears in assertions and call() invocations —
    # comment lines only say "// XPENDING" (unquoted), never "'XPENDING'" (quoted).
    # No comment-filter pipe needed: avoids pipefail interaction with grep's exit codes.
    for cmd in XREADGROUP XPENDING XCLAIM XACK XDEL; do
      if grep -q "'$cmd'" "$f" 2>/dev/null; then
        if grep -q "'$cmd'" "$test_file" 2>/dev/null; then
          echo "  ✓ $short — '$cmd' asserted in test"
        else
          echo "  ✗ $short — '$cmd' used in source but never asserted in test"
          echo "    Fix: add expect(mockRedisCall).toHaveBeenCalledWith('$cmd', <exact args>)"
          REDIS_FAIL=$((REDIS_FAIL + 1))
        fi
      fi
    done

    # XPENDING pagination check (B):
    # A count-limited XPENDING without a loop silently drops messages beyond the first batch.
    # Must loop XPENDING until it returns empty. Summary-form XPENDING (health checks,
    # diagnostics) doesn't need a loop — only range-form replay does.
    # Pass if ANY XPENDING call in the file has a 'while' loop in the preceding 40 lines.
    if grep -q "'XPENDING'" "$f" 2>/dev/null; then
      HAS_PAGINATED_XPENDING=false
      while IFS=: read -r XP_LINE _; do
        WIN_START=$((XP_LINE - 40))
        [ "$WIN_START" -lt 1 ] && WIN_START=1
        if sed -n "${WIN_START},${XP_LINE}p" "$f" 2>/dev/null | grep -qE '^\s*while\b'; then
          HAS_PAGINATED_XPENDING=true
          break
        fi
      done < <(grep -n "'XPENDING'" "$f" 2>/dev/null)

      if [ "$HAS_PAGINATED_XPENDING" = "true" ]; then
        echo "  ✓ $short — XPENDING paginated (while loop precedes call)"
      else
        echo "  ✗ $short — XPENDING not paginated (only first batch replayed)"
        echo "    Fix: loop XPENDING until it returns empty — PEL may have more than count limit"
        REDIS_FAIL=$((REDIS_FAIL + 1))
      fi
    fi

  done <<< "$REDIS_CONSUMER_FILES"

  [ "$REDIS_FAIL" -gt 0 ] && FAIL_COUNT=$((FAIL_COUNT + REDIS_FAIL))
  echo ""
fi

# ===========================================
# SECTION 6: Scheduling Cache Invariants
# ===========================================
# Runs when the target directory is under a scheduling path.
# Every route that mutates appointments (book/cancel/reschedule/approve)
# MUST also call invalidateAvailabilityCache. Missing this silently leaves
# freed/taken slots stale in the cache for up to the TTL window.
#
# This check enforces the invariant for ALL future mutation routes, not just
# the ones that exist today. Adding a new cancel variant and forgetting to
# invalidate? This gate fails. That's the point.
if echo "$TARGET_DIR" | grep -q 'scheduling'; then
  echo "--- SCHEDULING CACHE INVARIANTS ---"
  CACHE_INV_FAIL=0

  MUTATION_ROUTES=$(find "$TARGET_DIR" -name "route.ts" -not -name "*.test.*" \
    -not -path "*/node_modules/*" 2>/dev/null \
    | xargs grep -El "cancelAppointment|rescheduleAppointment|bookAppointment" 2>/dev/null || true)

  if [ -n "$MUTATION_ROUTES" ]; then
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      short=$(echo "$f" | sed 's|.*scheduling/||')
      if grep -q "invalidateAvailabilityCache" "$f" 2>/dev/null; then
        echo "  ✓ $short — invalidates availability cache on mutation"
      else
        echo "  ✗ $short — mutates appointments WITHOUT invalidating availability cache"
        echo "    Fix: import { invalidateAvailabilityCache } from '@/lib/availability-cache'"
        echo "         void invalidateAvailabilityCache(calendarId) after the mutation"
        CACHE_INV_FAIL=$((CACHE_INV_FAIL + 1))
      fi
    done <<< "$MUTATION_ROUTES"
  else
    echo "  No appointment mutation routes found in $TARGET_DIR"
  fi

  [ "$CACHE_INV_FAIL" -gt 0 ] && FAIL_COUNT=$((FAIL_COUNT + CACHE_INV_FAIL))
  echo ""
fi

# ===========================================
# SECTION 7: Lib Utility Test Coverage
# ===========================================
# Runs when the target directory is under src/lib.
# Any lib/*.ts file that exports functions must have a .test.ts.
# No test = no mechanical proof the logic is correct.
#
# Uses scripts/lib-test-debt.txt as an allowlist of pre-existing missing-test debt.
# Files IN the list → ⚠ WARN (acknowledged, fix incrementally, remove when done).
# Files NOT in the list → ✗ FAIL (new files must have tests from day one).
if echo "$TARGET_DIR" | grep -qE 'src/lib'; then
  echo "--- LIB UTILITY TEST COVERAGE ---"
  LIB_COV_FAIL=0
  LIB_COV_WARN=0

  # Locate the debt list relative to the script file, not the caller's cwd
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  DEBT_LIST="$SCRIPT_DIR/lib-test-debt.txt"

  LIB_FILES=$(find "$TARGET_DIR" -maxdepth 1 -name "*.ts" \
    -not -name "*.test.*" -not -name "*.d.ts" \
    -not -path "*/node_modules/*" 2>/dev/null || true)

  if [ -n "$LIB_FILES" ]; then
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      # Only flag files that actually export callable functions
      if grep -qE 'export (async )?function |export const [a-zA-Z]+ = (async )?\(' "$f" 2>/dev/null; then
        test_file="${f%.ts}.test.ts"
        short=$(basename "$f")
        if [ -f "$test_file" ]; then
          EXPECT_COUNT=$(grep -c "expect(" "$test_file" 2>/dev/null || echo 0)
          echo "  ✓ $short ($EXPECT_COUNT assertions)"
        else
          # Check if this file is in the acknowledged debt list
          if [ -f "$DEBT_LIST" ] && grep -qx "$short" "$DEBT_LIST" 2>/dev/null; then
            echo "  ⚠ $short — acknowledged tech debt (remove from lib-test-debt.txt when fixed)"
            LIB_COV_WARN=$((LIB_COV_WARN + 1))
          else
            echo "  ✗ $short — exports functions but has no test file (FAIL — not in debt list)"
            echo "    Fix: add ${short%.ts}.test.ts with at least 3 expect() calls"
            LIB_COV_FAIL=$((LIB_COV_FAIL + 1))
          fi
        fi
      fi
    done <<< "$LIB_FILES"
    if [ "$LIB_COV_WARN" -gt 0 ]; then
      echo "  → $LIB_COV_WARN file(s) in debt list (WARN — fix incrementally, remove from lib-test-debt.txt)"
    fi
  else
    echo "  No lib files found in $TARGET_DIR"
  fi
  [ "$LIB_COV_FAIL" -gt 0 ] && FAIL_COUNT=$((FAIL_COUNT + LIB_COV_FAIL))
  echo ""
fi

# ===========================================
# SECTION 8: @ordinatio/scheduling Package Test Density
# ===========================================
# Runs when the target directory contains the scheduling package.
# Business logic files > 200 lines must have at least 1 assertion per 15 lines.
# This prevents the "24 assertions for 449 lines" problem in crud.ts — where
# each function has 1-2 tests but critical edge cases (concurrent reschedule,
# rescheduledFrom field, rescheduleCount increment) are untested.
#
# Floor: lines ÷ 15, rounded down. A 300-line file needs 20 assertions minimum.
# The ratio is intentionally not too aggressive (1:10 would demand 45 for crud.ts
# and fail on many legitimate files). 1:15 catches genuinely thin coverage.
if echo "$TARGET_DIR" | grep -qE 'ordinatio-scheduling|scheduling'; then
  PKG_SRC="packages/ordinatio-scheduling/src"
  if [ -d "$PKG_SRC" ]; then
    echo "--- SCHEDULING PACKAGE TEST DENSITY ---"
    PKG_DENSITY_FAIL=0

    SOURCE_FILES=$(find "$PKG_SRC" -name "*.ts" -not -name "*.test.*" \
      -not -name "index.ts" -not -name "types.ts" -not -name "errors.ts" \
      -not -path "*/node_modules/*" -not -path "*/__tests__/*" 2>/dev/null || true)

    if [ -n "$SOURCE_FILES" ]; then
      while IFS= read -r f; do
        [ -z "$f" ] && continue
        LINE_COUNT=$(wc -l < "$f" 2>/dev/null | tr -d ' ')
        [ "${LINE_COUNT:-0}" -lt 200 ] && continue
        test_file="${f%.ts}.test.ts"
        short=$(echo "$f" | sed 's|.*/src/||')
        if [ ! -f "$test_file" ]; then
          echo "  ✗ $short ($LINE_COUNT lines) — no test file at all"
          PKG_DENSITY_FAIL=$((PKG_DENSITY_FAIL + 1))
          continue
        fi
        ASSERTIONS=$(grep -c "expect(" "$test_file" 2>/dev/null || echo 0)
        MIN_ASSERTIONS=$((LINE_COUNT / 15))
        if [ "$ASSERTIONS" -lt "$MIN_ASSERTIONS" ]; then
          echo "  ✗ $short — $ASSERTIONS assertions for $LINE_COUNT lines (minimum $MIN_ASSERTIONS, 1 per 15 lines)"
          echo "    Fix: add assertions for edge cases and error paths in ${short%.ts}.test.ts"
          PKG_DENSITY_FAIL=$((PKG_DENSITY_FAIL + 1))
        else
          echo "  ✓ $short — $ASSERTIONS assertions / $LINE_COUNT lines"
        fi
      done <<< "$SOURCE_FILES"
    else
      echo "  No source files found in $PKG_SRC"
    fi

    # Content-aware: notifications/engine.test.ts must exercise the location fallback
    # chain (type.location ?? calendar.location ?? undefined). >= 3 uses of "location"
    # proves the fallback is tested, not just that the word appears in a comment.
    ENGINE_TEST="$PKG_SRC/notifications/engine.test.ts"
    if [ -f "$ENGINE_TEST" ]; then
      LOC_COUNT=$(grep -c "location" "$ENGINE_TEST" 2>/dev/null || echo 0)
      if [ "$LOC_COUNT" -ge 3 ]; then
        echo "  ✓ notifications/engine.test.ts — location fallback chain exercised ($LOC_COUNT uses)"
      else
        echo "  ✗ notifications/engine.test.ts — location fallback NOT covered ($LOC_COUNT uses of 'location', need >= 3)"
        PKG_DENSITY_FAIL=$((PKG_DENSITY_FAIL + 1))
      fi
    fi

    [ "$PKG_DENSITY_FAIL" -gt 0 ] && FAIL_COUNT=$((FAIL_COUNT + PKG_DENSITY_FAIL))
    echo ""
  fi
fi

# ===========================================
# SECTION 9: Scheduling Schema-Implementation Debt
# ===========================================
# Runs when the target directory contains scheduling or database paths.
# Certain schema fields represent features that haven't been implemented yet
# (Outlook sync, iCloud, payments, recurring). Those fields are registered in
# scripts/scheduling-schema-debt.txt as acknowledged debt.
#
# The check: if a field pattern appears in the schema AND is NOT in the debt file,
# it means either (a) the feature was implemented (remove from debt file) or
# (b) someone added a new unimplemented field without registering the debt.
# Both (a) and (b) are caught — (a) correctly, (b) as a failure.
#
# When you implement a feature: remove its entries from scheduling-schema-debt.txt.
# The gate then fails until the corresponding route exists — enforcing completion.
if echo "$TARGET_DIR" | grep -qE 'scheduling|database'; then
  SCHEMA_FILE="packages/database/prisma/schema.prisma"
  SCRIPT_DIR_GS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  SCHEMA_DEBT_FILE="$SCRIPT_DIR_GS/scheduling-schema-debt.txt"

  if [ -f "$SCHEMA_FILE" ] && [ -f "$SCHEMA_DEBT_FILE" ]; then
    echo "--- SCHEDULING SCHEMA DEBT ---"
    SCHEMA_DEBT_FAIL=0

    # Fields to check: known unimplemented features
    # payment fields (paymentId/Status/Amount/Provider/depositAmount) are intentionally
    # omitted — they were implemented in Task #21 (Stripe payment processing).
    # recurringId — IMPLEMENTED (Task #96): removed from debt check
    for field in icloudCalendarUrl tipAmount; do
      if grep -q "$field" "$SCHEMA_FILE" 2>/dev/null; then
        if grep -q "^$field" "$SCHEMA_DEBT_FILE" 2>/dev/null; then
          echo "  ⚠ $field — acknowledged schema debt (implement to remove)"
        else
          echo "  ✗ $field — in schema but NOT in scheduling-schema-debt.txt"
          echo "    This means the field was added without registering debt, OR the feature"
          echo "    was implemented but the debt entry wasn't removed."
          echo "    Fix: either add to scheduling-schema-debt.txt (if still unimplemented)"
          echo "         or verify the implementation route exists and remove the entry."
          SCHEMA_DEBT_FAIL=$((SCHEMA_DEBT_FAIL + 1))
        fi
      fi
    done

    # Payment implementation guard: payment fields are in schema — verify the route exists
    if grep -q 'paymentId' "$SCHEMA_FILE" 2>/dev/null; then
      if [ -f "apps/web/src/app/api/scheduling/payments/intent/route.ts" ] && \
         [ -f "apps/web/src/app/api/webhooks/stripe/route.ts" ]; then
        echo "  ✓ payment fields — Stripe implementation verified (intent + webhook routes present)"
      else
        echo "  ✗ payment fields in schema but Stripe routes missing"
        SCHEMA_DEBT_FAIL=$((SCHEMA_DEBT_FAIL + 1))
      fi
    fi

    # Stripe webhook production readiness — three required handlers + secret guard
    STRIPE_WEBHOOK="apps/web/src/app/api/webhooks/stripe/route.ts"
    if [ -f "$STRIPE_WEBHOOK" ]; then
      if grep -q 'charge\.refunded' "$STRIPE_WEBHOOK" 2>/dev/null; then
        echo "  ✓ Stripe webhook handles charge.refunded"
      else
        echo "  ✗ Stripe webhook missing charge.refunded — refund reconciliation never fires"
        BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
      fi
      if grep -q 'charge\.dispute\.created' "$STRIPE_WEBHOOK" 2>/dev/null; then
        echo "  ✓ Stripe webhook handles charge.dispute.created"
      else
        echo "  ✗ Stripe webhook missing charge.dispute.created — chargebacks are silent"
        BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
      fi
      if grep -q 'STRIPE_WEBHOOK_SECRET' "$STRIPE_WEBHOOK" 2>/dev/null; then
        echo "  ✓ Stripe webhook guards STRIPE_WEBHOOK_SECRET before use"
      else
        echo "  ✗ Stripe webhook uses constructEvent without STRIPE_WEBHOOK_SECRET null-check"
        BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
      fi
    fi

    # Outlook Calendar sync — outlookCalendarId in schema must have routes
    if grep -q 'outlookCalendarId' "$SCHEMA_FILE" 2>/dev/null; then
      OUTLOOK_CONNECT="apps/web/src/app/api/scheduling/calendars/connect-outlook/route.ts"
      OUTLOOK_CALLBACK="apps/web/src/app/api/scheduling/calendars/connect-outlook/callback/route.ts"
      OUTLOOK_DISCONNECT="apps/web/src/app/api/scheduling/admin/calendars/[id]/disconnect-outlook/route.ts"
      if [ -f "$OUTLOOK_CONNECT" ] && [ -f "$OUTLOOK_CALLBACK" ] && [ -f "$OUTLOOK_DISCONNECT" ]; then
        ct=$(grep -c '\bexpect(' "${OUTLOOK_CONNECT%.ts}.test.ts" 2>/dev/null || echo 0)
        cbt=$(grep -c '\bexpect(' "${OUTLOOK_CALLBACK%.ts}.test.ts" 2>/dev/null || echo 0)
        dt=$(grep -c '\bexpect(' "${OUTLOOK_DISCONNECT%.ts}.test.ts" 2>/dev/null || echo 0)
        if [ "$ct" -ge 5 ] && [ "$cbt" -ge 5 ] && [ "$dt" -ge 3 ]; then
          echo "  ✓ Outlook Calendar sync — connect:$ct / callback:$cbt / disconnect:$dt assertions"
        else
          echo "  ✗ Outlook Calendar sync — insufficient tests (connect:$ct/5, callback:$cbt/5, disconnect:$dt/3)"
          SCHEMA_DEBT_FAIL=$((SCHEMA_DEBT_FAIL + 1))
        fi
      else
        echo "  ✗ outlookCalendarId in schema — Outlook sync routes MISSING"
        echo "    Need: connect-outlook/, connect-outlook/callback/, admin/.../disconnect-outlook/"
        SCHEMA_DEBT_FAIL=$((SCHEMA_DEBT_FAIL + 1))
      fi
    fi

    [ "$SCHEMA_DEBT_FAIL" -gt 0 ] && FAIL_COUNT=$((FAIL_COUNT + SCHEMA_DEBT_FAIL))
    echo ""
  fi
fi

# ===========================================
# SECTION 10: Org Isolation
# ===========================================
# Runs when the target directory is under scheduling paths.
# Verifies the two cross-tenant data exposure gaps found in the May 2026 audit:
#
# A) Public availability endpoint: any caller can pass a calendarId from another
#    org and receive slot data (staffing patterns, booking frequency, open windows).
#    The calendar must be verified to exist before slots are returned.
#
# B) Admin availability endpoint: verifyCalendar() only checks id, not organizationId.
#    A staff member from Org-A can call PUT /admin/availability/org-b-calendar-id
#    and overwrite Org-B's schedule. The WHERE clause must include organizationId.
if echo "$TARGET_DIR" | grep -q 'scheduling'; then
  echo "--- ORG ISOLATION ---"
  ORG_ISOLATION_FAIL=0

  # Check A: Public availability endpoint verifies calendar before slot lookup
  AVAIL_ROUTE_FILE="apps/web/src/app/api/scheduling/availability/route.ts"
  if [ -f "$AVAIL_ROUTE_FILE" ]; then
    if grep -qE 'getAvailableSlots|getAvailableDates' "$AVAIL_ROUTE_FILE" 2>/dev/null; then
      if grep -qE 'findUnique|findFirst' "$AVAIL_ROUTE_FILE" 2>/dev/null; then
        echo "  ✓ availability/route.ts — calendar verified before slot lookup"
      else
        echo "  ✗ availability/route.ts — getAvailableSlots called without calendar verification"
        echo "    CROSS-TENANT EXPOSURE: any calendarId can be queried — slot data for all orgs is public"
        echo "    Fix: add prisma.schedulingCalendar.findUnique({ where: { id: calendarId } }) before getAvailableSlots()"
        ORG_ISOLATION_FAIL=$((ORG_ISOLATION_FAIL + 1))
      fi
    fi
  fi

  # Check B: Admin availability routes verify calendar org ownership in WHERE clause
  ADMIN_AVAIL_DIR="apps/web/src/app/api/scheduling/admin/availability"
  if [ -d "$ADMIN_AVAIL_DIR" ]; then
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      short=$(echo "$f" | sed 's|.*/scheduling/||')
      if grep -qE 'verifyCalendar|calendarId' "$f" 2>/dev/null; then
        # verifyCalendar must use organizationId in its WHERE clause, or the route must check after
        if grep -qE 'organizationId.*where|where.*organizationId|verifyCalendar[^)]*organizationId' "$f" 2>/dev/null; then
          echo "  ✓ $short — org ownership verified on calendar access"
        else
          echo "  ✗ $short — calendar accessed without org ownership check"
          echo "    CROSS-TENANT WRITE: staff from Org-A can overwrite Org-B's availability rules"
          echo "    Fix: add organizationId to verifyCalendar() WHERE clause"
          ORG_ISOLATION_FAIL=$((ORG_ISOLATION_FAIL + 1))
        fi
      fi
    done < <(find "$ADMIN_AVAIL_DIR" -name "route.ts" -not -name "*.test.*" 2>/dev/null)
  fi

  [ "$ORG_ISOLATION_FAIL" -gt 0 ] && FAIL_COUNT=$((FAIL_COUNT + ORG_ISOLATION_FAIL))
  echo ""
fi

# ===========================================
# SECTION 11: Business Rule Enforcement
# ===========================================
# Runs when the target directory contains the scheduling package or routes.
# Verifies that type-level policies are enforced after being fetched.
#
# allowReschedule and allowCancel are fetched in SELECT statements inside
# the scheduling package but — as of the May 2026 audit — were never checked.
# A booking type with allowReschedule=false could still be freely rescheduled,
# and allowCancel=false had no effect. This check ensures enforcement is present.
#
# Also checks for hardcoded org-specific values (tenant name, timezone, URL)
# that break multi-tenancy silently. These are caught here as well as in the
# pre-commit hook — the gate confirms the file is clean at ship time.
if echo "$TARGET_DIR" | grep -qE 'scheduling|ordinatio-booking-widget'; then
  echo "--- BUSINESS RULE ENFORCEMENT ---"
  BIZ_RULE_FAIL=0

  CRUD_FILE="packages/ordinatio-scheduling/src/appointments/crud.ts"
  if [ -f "$CRUD_FILE" ]; then
    for policy in allowReschedule allowCancel; do
      if grep -q "${policy}: true" "$CRUD_FILE" 2>/dev/null; then
        if grep -qE "!\s*appointment\.type\.${policy}|${policy}[^)]*===\s*false" "$CRUD_FILE" 2>/dev/null; then
          echo "  ✓ crud.ts — ${policy} enforced after fetch"
        else
          echo "  ✗ crud.ts — ${policy} selected in query but no enforcement if-check found"
          echo "    Type policy is silently bypassed: allowReschedule=false has no effect"
          echo "    Fix: add if (!appointment.type.${policy}) throw schedError('SCHED_306', ...)"
          BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
        fi
      fi
    done
  fi

  # Hardcoded org-specific values in scheduling routes (tenant name, URL, timezone)
  SCHED_ROUTES=$(find apps/web/src/app/api/scheduling -name "route.ts" \
    -not -name "*.test.*" -not -path "*/node_modules/*" 2>/dev/null || true)
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    short=$(echo "$f" | sed 's|.*/scheduling/||')
    if grep -qE "'1701 Bespoke'|\"1701 Bespoke\"" "$f" 2>/dev/null; then
      echo "  ✗ $short — hardcoded tenant name '1701 Bespoke'"
      echo "    Fix: use calendar.staffName or NEXT_PUBLIC_APP_NAME"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
    if grep -qE "\|\| 'America/Detroit'|\|\| \"America/Detroit\"" "$f" 2>/dev/null; then
      echo "  ✗ $short — hardcoded timezone fallback 'America/Detroit'"
      echo "    Fix: use calendar.timezone from the database"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
    if grep -qE "\|\| 'https://[a-z0-9.-]+\.[a-z]{2,}|\|\| \"https://[a-z0-9.-]+\.[a-z]{2,}" "$f" 2>/dev/null; then
      echo "  ✗ $short — hardcoded URL fallback (links point to wrong domain in staging/dev)"
      echo "    Fix: remove fallback, throw if NEXT_PUBLIC_APP_URL is unset"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  done <<< "$SCHED_ROUTES"

  if [ "$BIZ_RULE_FAIL" -eq 0 ]; then
    echo "  ✓ All business rules enforced, no hardcoded org values"
  fi

  # No-show tracking completeness
  NO_SHOW_ROUTE="apps/web/src/app/api/scheduling/appointments/[id]/no-show/route.ts"
  if [ -f "$NO_SHOW_ROUTE" ]; then
    NO_SHOW_TEST="${NO_SHOW_ROUTE%.ts}.test.ts"
    if [ -f "$NO_SHOW_TEST" ]; then
      nst=$(grep -c '\bexpect(' "$NO_SHOW_TEST" 2>/dev/null || echo 0)
      if [ "$nst" -ge 5 ]; then
        echo "  ✓ no-show/route.ts — exists with $nst test assertions"
      else
        echo "  ✗ no-show/route.test.ts — $nst assertions (need >= 5)"
        BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
      fi
    else
      echo "  ✗ no-show/route.test.ts — MISSING"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  else
    echo "  ✗ no-show/route.ts — MISSING (no-show tracking not implemented)"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi
  if grep -q 'outlookCalendarId' apps/web/src/app/dashboard/settings/scheduling/calendars/page.tsx 2>/dev/null; then
    echo "  ✓ calendars page — Outlook Calendar connection UI present"
  else
    echo "  ✗ calendars page — outlookCalendarId not rendered (no Connect Outlook UI)"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi
  if grep -q 'NO_SHOW' apps/web/src/app/dashboard/appointments/appointments-view.tsx 2>/dev/null; then
    echo "  ✓ appointments-view — NO_SHOW status handled in STATUS_STYLES"
  else
    echo "  ✗ appointments-view — NO_SHOW missing from STATUS_STYLES"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi
  # Human-in-the-loop refund: cancel routes must NOT auto-refund.
  # Instead they create a sticky activity requiring staff review.
  # Auto-refund was replaced so staff can choose Refund vs Credit.
  CANCEL_ROUTE="apps/web/src/app/api/scheduling/appointments/[id]/cancel/route.ts"
  if [ -f "$CANCEL_ROUTE" ]; then
    if ! grep -q 'stripe.refunds.create' "$CANCEL_ROUTE" 2>/dev/null; then
      echo "  ✓ cancel/route.ts — no auto-Stripe refund (human-in-the-loop)"
    else
      echo "  ✗ cancel/route.ts — stripe.refunds.create found — auto-refund was re-added (use resolve-refund instead)"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  fi
  MANAGE_ROUTE="apps/web/src/app/api/scheduling/appointments/manage/route.ts"
  if [ -f "$MANAGE_ROUTE" ]; then
    if grep -q 'scheduling.appointment_refund_pending' "$MANAGE_ROUTE" 2>/dev/null; then
      echo "  ✓ manage/route.ts — refund review sticky created on self-service cancel"
    else
      echo "  ✗ manage/route.ts — missing refund_pending sticky — paid clients not notified to staff"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  fi
  # Staff must be notified of new bookings, cancellations, and reschedules.
  # Without queueStaffNotification, staff only learn about appointments by checking the dashboard.
  BOOKING_ROUTE="apps/web/src/app/api/scheduling/appointments/route.ts"
  if [ -f "$BOOKING_ROUTE" ]; then
    if grep -q 'queueStaffNotification' "$BOOKING_ROUTE" 2>/dev/null; then
      echo "  ✓ booking route queues staff notification on confirmation"
    else
      echo "  ✗ booking route missing queueStaffNotification — staff never notified of new bookings"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  fi
  if grep -q 'queueStaffNotification' apps/web/src/app/api/scheduling/appointments/'[id]'/cancel/route.ts 2>/dev/null; then
    echo "  ✓ cancel route queues staff notification"
  else
    echo "  ✗ cancel route missing queueStaffNotification — staff never notified of cancellations"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi
  if grep -q 'queueStaffNotification' apps/web/src/app/api/scheduling/appointments/'[id]'/reschedule/route.ts 2>/dev/null; then
    echo "  ✓ reschedule route queues staff notification"
  else
    echo "  ✗ reschedule route missing queueStaffNotification — staff never notified of reschedules"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # Coupon enforcement: validate route + usedCount increment + storage must ALL be present.
  # A coupon that is validated but never decremented is a free-use coupon forever.
  COUPON_VALIDATE="apps/web/src/app/api/scheduling/coupons/validate/route.ts"
  if [ -f "$COUPON_VALIDATE" ]; then
    vt=$(grep -c '\bexpect(' "${COUPON_VALIDATE%.ts}.test.ts" 2>/dev/null || echo 0)
    if [ "$vt" -ge 5 ]; then
      echo "  ✓ coupons/validate/route.ts — exists with $vt test assertions"
    else
      echo "  ✗ coupons/validate/route.ts — $vt assertions (need >= 5)"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
    if grep -qE 'executeRaw|\$executeRaw|usedCount.*increment|usedCount.*\+.*1' apps/web/src/app/api/scheduling/appointments/route.ts 2>/dev/null; then
      echo "  ✓ appointments/route.ts — coupon usedCount incremented atomically"
    else
      echo "  ✗ appointments/route.ts — coupon usedCount NOT incremented (coupons are free forever)"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  else
    if grep -q 'couponCode' packages/database/prisma/schema.prisma 2>/dev/null; then
      echo "  ✗ couponCode in schema but validate route MISSING"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  fi
  # Calendar sync cancellations must issue Stripe refund and send client notification.
  # A raw db.appointment.update() in the sync service skips both — paid clients lose money.
  CANCEL_SYNC_ROUTE="apps/web/src/app/api/scheduling/appointments/[id]/cancel-sync/route.ts"
  if [ -f "$CANCEL_SYNC_ROUTE" ]; then
    cst=$(grep -c '\bexpect(' "${CANCEL_SYNC_ROUTE%.ts}.test.ts" 2>/dev/null || echo 0)
    if [ "$cst" -ge 7 ]; then
      echo "  ✓ cancel-sync/route.ts — exists with $cst test assertions"
    else
      echo "  ✗ cancel-sync/route.ts — $cst assertions (need >= 7)"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
    if grep -qE 'cancel-sync' apps/worker/src/services/calendar-sync.service.ts 2>/dev/null; then
      echo "  ✓ calendar-sync.service.ts — delegates cancellation to cancel-sync endpoint"
    else
      echo "  ✗ calendar-sync.service.ts — raw db.update() bypass (no Stripe refund on Google sync cancel)"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
    if grep -qE 'cancel-sync' apps/worker/src/services/outlook-calendar-sync.service.ts 2>/dev/null; then
      echo "  ✓ outlook-calendar-sync.service.ts — delegates cancellation to cancel-sync endpoint"
    else
      echo "  ✗ outlook-calendar-sync.service.ts — raw db.update() bypass (no Stripe refund on Outlook sync cancel)"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  else
    echo "  ✗ cancel-sync/route.ts MISSING — sync-initiated cancellations never refund or notify"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi
  # DB-level double-booking constraint must exist.
  # Application-level Serializable transaction is necessary but not sufficient —
  # the constraint is the final safety net that prevents silent double-bookings.
  if [ -f "packages/database/scripts/apply-booking-constraint.ts" ]; then
    if grep -q 'appointment_slot_lock' packages/database/scripts/apply-booking-constraint.ts 2>/dev/null; then
      echo "  ✓ appointment_slot_lock constraint script exists"
    else
      echo "  ✗ apply-booking-constraint.ts exists but no appointment_slot_lock index"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
    if grep -qE 'isGroup.*Boolean|Boolean.*isGroup' packages/database/prisma/schema.prisma 2>/dev/null; then
      echo "  ✓ Appointment.isGroup field exists (group booking constraint exclusion)"
    else
      echo "  ✗ Appointment.isGroup missing — group appointments would violate the constraint"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  else
    echo "  ✗ apply-booking-constraint.ts MISSING — appointment_slot_lock not enforced at DB level"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi
  # Availability endpoint must derive duration from appointmentType, not from the client.
  # Client-controlled duration allows false availability reads (duration=5 always shows open
  # slots; duration=480 always shows none) and opens a double-booking window when the queried
  # duration diverges from the type's actual duration.
  AVAIL_ROUTE="apps/web/src/app/api/scheduling/availability/route.ts"
  if [ -f "$AVAIL_ROUTE" ]; then
    if grep -q "searchParams.get('duration')" "$AVAIL_ROUTE" 2>/dev/null; then
      echo "  ✗ availability/route.ts reads duration from client query params — use typeId instead"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    else
      echo "  ✓ availability/route.ts — duration derived from appointmentType, not client-controlled"
    fi
  fi
  # Rate limiter must be Redis-backed — in-memory Map is per-Vercel-instance,
  # meaning a user hitting N instances gets N×limit requests through unchecked.
  RATE_LIMIT_FILE="apps/web/src/lib/rate-limit.ts"
  if [ -f "$RATE_LIMIT_FILE" ]; then
    if grep -q 'const store = new Map' "$RATE_LIMIT_FILE" 2>/dev/null; then
      echo "  ✗ rate-limit.ts uses in-memory Map — rate limits are per-instance on Vercel"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    else
      echo "  ✓ rate-limit.ts — Redis-backed (global across instances)"
    fi
  fi

  # Human-in-the-loop refund: cancel routes must NOT auto-Stripe — must create sticky instead.
  # Replaced automated fee enforcement (task #47) with staff-decision flow.
  # Staff sees a sticky activity and chooses Issue Refund or Apply Credit.
  STAFF_CANCEL="apps/web/src/app/api/scheduling/appointments/[id]/cancel/route.ts"
  if [ -f "$STAFF_CANCEL" ]; then
    if ! grep -q 'stripe.refunds.create' "$STAFF_CANCEL" 2>/dev/null; then
      echo "  ✓ cancel/route.ts — no auto-Stripe refund (human-in-the-loop)"
    else
      echo "  ✗ cancel/route.ts — stripe.refunds.create found — auto-refund was re-added"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  fi

  MANAGE_ROUTE="apps/web/src/app/api/scheduling/appointments/manage/route.ts"
  if [ -f "$MANAGE_ROUTE" ]; then
    if grep -q 'scheduling.appointment_refund_pending' "$MANAGE_ROUTE" 2>/dev/null; then
      echo "  ✓ manage/route.ts — refund review sticky created on self-service cancel"
    else
      echo "  ✗ manage/route.ts — missing scheduling.appointment_refund_pending sticky"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  fi

  # processPendingNotifications must use row-level claiming (task #48).
  # A naked findMany causes duplicate sends when multiple workers run simultaneously.
  # Two workers both read the same PENDING rows, both send the same email/SMS — client
  # receives duplicates with no error logged and no observable signal.
  NOTIF_ENGINE="packages/ordinatio-scheduling/src/notifications/engine.ts"
  if [ -f "$NOTIF_ENGINE" ]; then
    if grep -q 'FOR UPDATE.*SKIP LOCKED\|\$queryRaw\|processingId' "$NOTIF_ENGINE" 2>/dev/null; then
      echo "  ✓ processPendingNotifications — row-level claiming present (FOR UPDATE SKIP LOCKED)"
    else
      echo "  ✗ processPendingNotifications — naked findMany, no row-level claiming"
      echo "    Duplicate sends guaranteed when multiple worker instances run simultaneously"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  fi

  # Notification archive job must cancel stale PENDING rows (task #66).
  # processPendingNotifications skips PENDING rows with scheduledFor > maxOverdueMs (12h).
  # Without explicit cancellation, those rows accumulate indefinitely — no cleanup path.
  # Anchor: presence of STALE_PENDING_WINDOW_MS named constant (not a string literal).
  ARCHIVE_JOB="apps/worker/src/jobs/notification-archive.job.ts"
  if [ -f "$ARCHIVE_JOB" ]; then
    if grep -q 'STALE_PENDING_WINDOW_MS' "$ARCHIVE_JOB" 2>/dev/null; then
      echo "  ✓ notification-archive.job.ts — stale PENDING coverage present"
    else
      echo "  ✗ notification-archive.job.ts — stale PENDING rows never cancelled"
      echo "    PENDING rows with scheduledFor >12h ago accumulate forever (no cleanup path)"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  fi

  # Per-appointment location must be supported — staff need to override after booking.
  # resolveLocation must live in the scheduling package (not just the web layer) so
  # mapToDetails can call it — single canonical home prevents drift when #63 adds locationType.
  LOCATION_HELPER="apps/web/src/lib/scheduling-location.ts"
  LOCATION_ROUTE="apps/web/src/app/api/scheduling/appointments/[id]/location/route.ts"
  LOCATION_PKG="packages/ordinatio-scheduling/src/location.ts"
  CRUD_TS="packages/ordinatio-scheduling/src/appointments/crud.ts"

  if [ -f "$LOCATION_ROUTE" ] && [ -f "$LOCATION_HELPER" ]; then
    echo "  ✓ per-appointment location — route and web helper present"
  else
    echo "  ✗ per-appointment location — missing route or web helper"
    echo "    Staff cannot change location on individual appointments after booking"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # resolveLocation must live in the package — not just the web layer.
  # If it's only in apps/web, the package's mapToDetails can't use it and WILL drift.
  # When #63 adds locationType semantics, only the package version will be updated.
  if [ -f "$LOCATION_PKG" ] && grep -q 'resolveLocation' "$LOCATION_PKG" 2>/dev/null; then
    echo "  ✓ resolveLocation in scheduling package (single canonical home)"
  else
    echo "  ✗ resolveLocation not in scheduling package — two homes means guaranteed drift in #63"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # mapToDetails in crud.ts must call resolveLocation, not inline the chain.
  if grep -q 'resolveLocation' "$CRUD_TS" 2>/dev/null; then
    echo "  ✓ crud.ts calls resolveLocation (no inline chain)"
  else
    echo "  ✗ crud.ts does not call resolveLocation — location chain is inlined in mapToDetails"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # #63: locationType enum must be in schema — structural signal for booking/notification logic.
  if grep -q 'TRAVEL_TO_CLIENT' packages/database/prisma/schema.prisma 2>/dev/null; then
    echo "  ✓ AppointmentLocationType enum in schema (TRAVEL_TO_CLIENT present)"
  else
    echo "  ✗ AppointmentLocationType not in schema — system cannot distinguish location kinds"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # resolveLocation must handle TRAVEL_TO_CLIENT — chain changes: no type/calendar fallthrough.
  # Without this, home-visit appointments show the studio address in notifications.
  LOCATION_TS="packages/ordinatio-scheduling/src/location.ts"
  if grep -q 'TRAVEL_TO_CLIENT' "$LOCATION_TS" 2>/dev/null; then
    echo "  ✓ resolveLocation handles TRAVEL_TO_CLIENT (no type/calendar fallthrough)"
  else
    echo "  ✗ resolveLocation ignores TRAVEL_TO_CLIENT — wrong location in notifications for travel"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # buildNotificationContext must call resolveLocation — not its own inline 2-tier chain.
  # Without this, per-appointment overrides (#62) and locationType are both silently ignored.
  NOTIF_ENGINE="packages/ordinatio-scheduling/src/notifications/engine.ts"
  if grep -q 'resolveLocation' "$NOTIF_ENGINE" 2>/dev/null; then
    echo "  ✓ notification engine uses resolveLocation (locationType + override respected)"
  else
    echo "  ✗ notification engine inlines location chain — #62 overrides ignored in notifications"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # resolveLocation needs locationType to make TRAVEL_TO_CLIENT decisions.
  # Detect the bad pattern directly: type selects in crud.ts that have location: true
  # but NOT locationType: true on the same line.
  CRUD_TS="packages/ordinatio-scheduling/src/appointments/crud.ts"
  BAD_SELECTS=$(grep 'type: { select: {.*location: true' "$CRUD_TS" 2>/dev/null \
    | grep -v 'locationType' | wc -l | tr -d ' ')
  if [ "$BAD_SELECTS" -eq 0 ]; then
    echo "  ✓ crud.ts: all type selects with location: true also include locationType: true"
  else
    echo "  ✗ crud.ts: ${BAD_SELECTS} type select(s) have location: true without locationType: true"
    echo "    resolveLocation receives incomplete data — TRAVEL_TO_CLIENT never triggers for those callers"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # manage/route.ts calls resolveLocation — its type select must include locationType.
  MANAGE_RT="apps/web/src/app/api/scheduling/appointments/manage/route.ts"
  if grep -q 'locationType.*true' "$MANAGE_RT" 2>/dev/null; then
    echo "  ✓ manage/route.ts: locationType in type select (resolveLocation gets full data)"
  else
    echo "  ✗ manage/route.ts: locationType missing from type select"
    echo "    Self-service page shows studio address for TRAVEL_TO_CLIENT appointments"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # RawAppointment.type must declare locationType so TypeScript enforces the relationship
  # between the Prisma include and the resolveLocation call. Without it, the type system
  # and runtime are out of sync — a developer could remove locationType from the Prisma
  # include and TypeScript would not catch the regression.
  CRUD_TS="packages/ordinatio-scheduling/src/appointments/crud.ts"
  if awk '/interface RawAppointment/,/^}/' "$CRUD_TS" 2>/dev/null | grep -q 'locationType'; then
    echo "  ✓ RawAppointment.type declares locationType (type system matches runtime)"
  else
    echo "  ✗ RawAppointment.type missing locationType — type system and runtime are out of sync"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # appointment-types route must select requiresPayment and deposit.
  # The booking widget uses requiresPayment to gate the payment step in useBookingFlow.
  # If absent, the JSON omits the field, it arrives as undefined (falsy), and paid
  # appointments silently skip payment collection with no error.
  APPT_TYPES_RT="apps/web/src/app/api/scheduling/appointment-types/route.ts"
  if grep -q 'requiresPayment.*true' "$APPT_TYPES_RT" 2>/dev/null; then
    echo "  ✓ appointment-types route selects requiresPayment — widget payment gate receives the value"
  else
    echo "  ✗ appointment-types route missing requiresPayment — paid appointments skip payment collection silently"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # AppointmentLocationType must be exported as a named union — not inlined as 'string'.
  # The named type allows LOCATION_LABELS to be Record<AppointmentLocationType, string>,
  # making the label lookup exhaustive by the compiler rather than by convention.
  APPT_TYPE_LIST="apps/web/src/app/dashboard/settings/scheduling/types/appointment-types-list.tsx"
  if grep -q 'export type AppointmentLocationType' "$APPT_TYPE_LIST" 2>/dev/null; then
    echo "  ✓ AppointmentLocationType exported as named union (single source of truth)"
  else
    echo "  ✗ AppointmentLocationType not exported — plain string loses exhaustiveness enforcement on LOCATION_LABELS"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # AppointmentType.locationType must use AppointmentLocationType, not plain string.
  if awk '/export interface AppointmentType/,/^}/' "$APPT_TYPE_LIST" 2>/dev/null | grep -qE 'locationType:\s*AppointmentLocationType'; then
    echo "  ✓ AppointmentType.locationType typed as AppointmentLocationType (not plain string)"
  else
    echo "  ✗ AppointmentType.locationType is plain string — use the exported AppointmentLocationType union"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # LOCATION_LABELS must be a Record<AppointmentLocationType, ...> — presence alone is not enough.
  # A bare object without the explicit Record type is not exhaustive and will silently accept
  # missing keys. The type annotation is the enforcement mechanism.
  APPT_FORM_TS="apps/web/src/app/dashboard/settings/scheduling/types/appointment-type-form.tsx"
  if grep -q 'Record<AppointmentLocationType' "$APPT_FORM_TS" 2>/dev/null; then
    echo "  ✓ LOCATION_LABELS typed as Record<AppointmentLocationType, string> — exhaustive by compiler"
  else
    echo "  ✗ LOCATION_LABELS missing or untyped — must be Record<AppointmentLocationType, string> to enforce exhaustiveness"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # The type-location label must NOT be sr-only. It changes meaning (Address / Meeting Link /
  # Phone) so hiding it from sighted users while only the placeholder communicates intent
  # is an accessibility and usability regression.
  if grep -E 'htmlFor="type-location"' "$APPT_FORM_TS" 2>/dev/null | grep -q 'sr-only'; then
    echo "  ✗ type-location label is sr-only — the label text changes with locationType so it must be visible"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  else
    echo "  ✓ type-location label is visible (sr-only not on the label line)"
  fi

  # Prisma client must be regenerated after schema changes. The schema defines
  # AppointmentLocationType but if prisma generate has not been run, AppointmentTypeSelect
  # will not include locationType — causing tsc to error on every type select that
  # includes locationType: true.
  if grep -q 'AppointmentLocationType' node_modules/.prisma/client/index.d.ts 2>/dev/null; then
    echo "  ✓ Prisma client generated — AppointmentLocationType in generated types"
  else
    echo "  ✗ Prisma client stale — run pnpm prisma generate (AppointmentLocationType in schema but not in client)"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # buildNotificationContext in engine.ts must declare locationType as AppointmentLocationType,
  # not plain string. resolveLocation expects AppointmentLocationType — a string parameter
  # causes a tsc error inside buildNotificationContext when it calls resolveLocation.
  ENGINE_TS="packages/ordinatio-scheduling/src/notifications/engine.ts"
  if grep -q 'locationType.*AppointmentLocationType' "$ENGINE_TS" 2>/dev/null; then
    echo "  ✓ buildNotificationContext.type.locationType typed as AppointmentLocationType"
  else
    echo "  ✗ buildNotificationContext.type.locationType is plain string — resolveLocation call fails tsc"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # AppointmentTypeInfo must declare locationType as WidgetLocationType (not plain string).
  # The named local union enables a Record<WidgetLocationType, LocationMeta> that is
  # exhaustive by the compiler — same pattern as AppointmentLocationType in the web app.
  WIDGET_TYPES="packages/ordinatio-booking-widget/src/types.ts"
  if awk '/export interface AppointmentTypeInfo/,/^}/' "$WIDGET_TYPES" 2>/dev/null | grep -qE 'locationType:\s*WidgetLocationType'; then
    echo "  ✓ AppointmentTypeInfo.locationType typed as WidgetLocationType (not plain string)"
  else
    echo "  ✗ AppointmentTypeInfo.locationType missing or plain string — use WidgetLocationType for exhaustive LOCATION_META"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # LOCATION_META in the widget must be Record<WidgetLocationType, LocationMeta>.
  # Plain object without the type annotation silently accepts missing keys.
  WIDGET_LOCATION="packages/ordinatio-booking-widget/src/utils/location.ts"
  if grep -q 'Record<WidgetLocationType' "$WIDGET_LOCATION" 2>/dev/null; then
    echo "  ✓ LOCATION_META typed as Record<WidgetLocationType, LocationMeta> — exhaustive by compiler"
  else
    echo "  ✗ LOCATION_META missing or untyped — clients may see wrong label for new locationType values"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # TypeStep must reference locationType — it's the first choice point in the booking flow.
  # Without it clients cannot distinguish IN_PERSON / VIRTUAL / PHONE / TRAVEL before booking.
  TYPE_STEP="packages/ordinatio-booking-widget/src/steps/TypeStep.tsx"
  if grep -q 'locationType' "$TYPE_STEP" 2>/dev/null; then
    echo "  ✓ TypeStep renders locationType — clients see meeting format on type cards"
  else
    echo "  ✗ TypeStep missing locationType — clients cannot see meeting format before booking"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # DetailsStep must show IN_PERSON address (obw-location-detail) in the summary card.
  # TypeStep and ConfirmStep both show it — omitting it from DetailsStep is a UX regression:
  # the client fills in their details without knowing the venue.
  DETAILS_STEP="packages/ordinatio-booking-widget/src/steps/DetailsStep.tsx"
  if grep -q 'obw-location-detail' "$DETAILS_STEP" 2>/dev/null; then
    echo "  ✓ DetailsStep shows IN_PERSON address (obw-location-detail present)"
  else
    echo "  ✗ DetailsStep missing obw-location-detail — IN_PERSON address hidden during review"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # Widget step files must not use inline styles — all obw-* components are styled via
  # CSS classes so white-label customers can override via --obw-* variables and selectors.
  # Exception: TypeStep's backgroundColor swatch is a dynamic runtime API value
  # (a hex color string) that cannot be expressed as a static CSS class.
  WIDGET_STEPS_DIR="packages/ordinatio-booking-widget/src/steps"
  INLINE_VIOLATIONS=$(grep -rn 'style={{' "$WIDGET_STEPS_DIR"/*.tsx 2>/dev/null | grep -v 'backgroundColor' || true)
  if [ -n "$INLINE_VIOLATIONS" ]; then
    echo "  ✗ Widget step file(s) contain inline styles (backgroundColor swatch excepted):"
    echo "$INLINE_VIOLATIONS" | sed 's/^/    /'
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  else
    echo "  ✓ Widget step files use CSS classes not inline styles (backgroundColor swatch excepted)"
  fi

  # appointment-types route must import schedError — highest-traffic public scheduling endpoint.
  # A bare console.warn with no ref ID means production failures are undiagnosable.
  APPT_TYPES_ROUTE="apps/web/src/app/api/scheduling/appointment-types/route.ts"
  if grep -q 'schedError' "$APPT_TYPES_ROUTE" 2>/dev/null; then
    echo "  ✓ appointment-types route uses schedError — Rule 8 enforced on public endpoint"
  else
    echo "  ✗ appointment-types route missing schedError — no ref ID on production failures"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # Widget components and steps must use explicit React type imports, not the React.*
  # global namespace. Targets React.UpperCaseLetter (type names: ElementType, FormEvent,
  # ReactNode etc.) but NOT ReactDOM.* — that is a different module and legitimate to use.
  # Known limitation: grep -v '// ' excludes single-line comments only; block comments
  # are an accepted false-positive risk given no widget file currently uses block comments.
  WIDGET_REACT_NAMESPACE=$(grep -rn 'React\.[A-Z]' \
    "packages/ordinatio-booking-widget/src/components"/*.tsx \
    "packages/ordinatio-booking-widget/src/steps"/*.tsx 2>/dev/null \
    | grep -v 'ReactDOM\.' | grep -v '// ' || true)
  if [ -n "$WIDGET_REACT_NAMESPACE" ]; then
    echo "  ✗ Widget files use React.* namespace types — use explicit import type { X } from 'react':"
    echo "$WIDGET_REACT_NAMESPACE" | sed 's/^/    /'
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  else
    echo "  ✓ Widget components/steps use explicit React type imports — no React.* namespace"
  fi

  # .obw-card--summary:hover must override .obw-card:hover's accent border.
  # The summary card is a read-only review surface; cursor: default signals non-interactive
  # but .obw-card:hover still fires without this override, contradicting that signal.
  WIDGET_CSS="packages/ordinatio-booking-widget/src/styles/widget.css"
  if grep -q '\.obw-card--summary:hover' "$WIDGET_CSS" 2>/dev/null; then
    echo "  ✓ .obw-card--summary:hover suppresses interactive border on read-only summary card"
  else
    echo "  ✗ .obw-card--summary:hover missing — hover highlight fires on non-interactive card"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # ConfirmStep's decorative checkmark SVG must have aria-hidden="true".
  # Without it, screen readers encounter an unlabeled SVG element.
  # LocationBadge correctly uses aria-hidden="true" on its icons — ConfirmStep must match.
  CONFIRM_STEP="packages/ordinatio-booking-widget/src/steps/ConfirmStep.tsx"
  if grep -q 'obw-confirm-icon' "$CONFIRM_STEP" 2>/dev/null && \
     grep -q 'aria-hidden="true"' "$CONFIRM_STEP" 2>/dev/null; then
    echo "  ✓ ConfirmStep decorative SVG has aria-hidden — not announced to screen readers"
  else
    echo "  ✗ ConfirmStep SVG missing aria-hidden — screen readers encounter unlabeled decorative icon"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # ConfirmStep duration must use singular/plural ternary — "1 minutes" is wrong English.
  # Detects the broken form: a JSX expression result immediately followed by bare 'minutes'.
  # NOTE: checking for "'minute'" is wrong — it's a substring of "'minutes'" and matches
  # the unfixed file. This check detects the broken pattern directly instead.
  if grep -qE '\} minutes' "$CONFIRM_STEP" 2>/dev/null; then
    echo "  ✗ ConfirmStep duration always plural — shows '1 minutes' for 1-minute appointments"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  else
    echo "  ✓ ConfirmStep duration handles singular/plural — no bare '} minutes' pattern"
  fi

  # AppointmentTypeInfo.price and deposit must be typed as string | null.
  # Prisma Decimal serializes to a string in JSON (via toJSON()). Typing as number | null
  # is a type lie — TypeStep's raw interpolation only works by silent string coercion.
  WIDGET_TYPES="packages/ordinatio-booking-widget/src/types.ts"
  if awk '/export interface AppointmentTypeInfo/,/^}/' "$WIDGET_TYPES" 2>/dev/null \
     | grep -qE 'price:\s*string \| null'; then
    echo "  ✓ AppointmentTypeInfo.price typed as string | null — matches Prisma Decimal JSON"
  else
    echo "  ✗ AppointmentTypeInfo.price not string | null — type mismatch with Prisma Decimal serialization"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # TypeStep must use formatPrice utility — not raw $${type.price} template interpolation.
  # Prisma Decimal serializes to a string; a formatter handles string|number uniformly and
  # is consistent with PaymentStep's Intl.NumberFormat pattern.
  TYPE_STEP="packages/ordinatio-booking-widget/src/steps/TypeStep.tsx"
  if grep -q 'formatPrice' "$TYPE_STEP" 2>/dev/null; then
    echo "  ✓ TypeStep uses formatPrice utility — consistent currency formatting"
  else
    echo "  ✗ TypeStep missing formatPrice — raw \$\${type.price} relies on silent string coercion"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # PaymentStep coupon validation must not use bare catch — network failures would
  # silently show "Invalid coupon" instead of the real error, lying to the user.
  PAYMENT_STEP="packages/ordinatio-booking-widget/src/steps/PaymentStep.tsx"
  if grep -qE 'catch\s*\{' "$PAYMENT_STEP" 2>/dev/null; then
    echo "  ✗ PaymentStep has bare catch {} — binds no error, logs nothing (Rule 8)"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  else
    echo "  ✓ PaymentStep catch binds error — network failures are diagnosable"
  fi

  # BookingWidget must not use useMemo for themeJSON — the dependency array computed
  # the same value as the factory, doing zero memoization work. A plain const is
  # equivalent: Object.is on strings compares by value, not reference.
  # Note: if a legitimate useMemo is ever added here for a different purpose,
  # update this check to target 'useMemo.*themeJSON' instead of bare 'useMemo'.
  BOOKING_WIDGET="packages/ordinatio-booking-widget/src/BookingWidget.tsx"
  if grep -q 'useMemo' "$BOOKING_WIDGET" 2>/dev/null; then
    echo "  ✗ BookingWidget uses useMemo for themeJSON — wasted computation, use plain const"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  else
    echo "  ✓ BookingWidget uses plain const for themeJSON — no wasted useMemo"
  fi

  # Calendar view: DateStep must use the calendar layout, not the flat button grid.
  DATE_STEP="packages/ordinatio-booking-widget/src/steps/DateStep.tsx"
  if grep -q 'obw-cal-header' "$DATE_STEP" 2>/dev/null; then
    echo "  ✓ DateStep — calendar layout (obw-cal-header present)"
  else
    echo "  ✗ DateStep — missing obw-cal-header; flat button grid must not be used"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi
  if grep -q 'obw-cal-days' "$DATE_STEP" 2>/dev/null; then
    echo "  ✓ DateStep — calendar grid (obw-cal-days present)"
  else
    echo "  ✗ DateStep — missing obw-cal-days; 7-column Sunday-Saturday grid required"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi
  # DateStep must NOT use role="grid" — grid pattern requires role="row" + role="gridcell" children.
  # Without them, NVDA/JAWS cannot navigate the grid. role="group" is the correct role.
  if grep -q 'role="grid"' "$DATE_STEP" 2>/dev/null; then
    echo "  ✗ DateStep uses role=\"grid\" — requires row/gridcell children; use role=\"group\""
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  else
    echo "  ✓ DateStep — days container uses role=\"group\" (correct ARIA, no row/gridcell needed)"
  fi
  # DateStep prev-month guard must use isPrevDisabled.
  # isCurrentMonth alone only blocks the exact current month; it allows navigating into past months
  # if selectedDate initializes the view there or the clock ticks past midnight.
  if grep -q 'isPrevDisabled' "$DATE_STEP" 2>/dev/null; then
    echo "  ✓ DateStep — prev-month guard uses isPrevDisabled (blocks all past months)"
  else
    echo "  ✗ DateStep — prev guard missing isPrevDisabled; isCurrentMonth does not block past months"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # Scheduling source files (non-test) must have ≤1 'as any' cast.
  # The single permitted cast is utils.ts — Prisma's $transaction type limitation.
  SCHED_AS_ANY=$(grep -rn ' as any' \
    "packages/ordinatio-scheduling/src/" \
    --include="*.ts" \
    2>/dev/null \
    | grep -v '\.test\.ts' \
    | grep -v '/__tests__/' \
    | wc -l | tr -d ' ')
  if [ "$SCHED_AS_ANY" -gt 1 ]; then
    echo "  ✗ Scheduling source has $SCHED_AS_ANY 'as any' casts — only utils.ts Prisma workaround permitted"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  else
    echo "  ✓ Scheduling source has ≤1 'as any' cast (utils.ts Prisma transaction workaround only)"
  fi

  # Scheduling source files must also have zero ': any' type annotations.
  # ': any' is the same opt-out as 'as any' — just different syntax.
  SCHED_SRC_COLON_ANY=$(grep -rn ': any\b' \
    "packages/ordinatio-scheduling/src/" \
    --include="*.ts" \
    2>/dev/null \
    | grep -v '\.test\.ts' \
    | grep -v '/__tests__/' \
    | grep -v ': any\[\]' \
    | wc -l | tr -d ' ')
  if [ "$SCHED_SRC_COLON_ANY" -eq 0 ]; then
    echo "  ✓ Scheduling source — zero ': any' type annotations"
  else
    echo "  ✗ Scheduling source — $SCHED_SRC_COLON_ANY ': any' annotation(s) found"
    echo "    Fix: use specific types — param: SomeType, this: object, etc."
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # Scheduling test files (api/scheduling/ and lib/scheduling/) must have
  # zero 'as any' casts AND zero ': any' type annotations.
  SCHED_TEST_AS_ANY=$(grep -rn ' as any' \
    "apps/web/src/app/api/scheduling/" \
    "apps/web/src/lib/scheduling/" \
    "apps/web/src/lib/scheduling-db.test.ts" \
    --include="*.test.ts" \
    2>/dev/null | wc -l | tr -d ' ')
  SCHED_TEST_COLON_ANY=$(grep -rn ': any\b' \
    "apps/web/src/app/api/scheduling/" \
    "apps/web/src/lib/scheduling/" \
    "apps/web/src/lib/scheduling-db.test.ts" \
    --include="*.test.ts" \
    2>/dev/null \
    | grep -v ': any\[\]' \
    | wc -l | tr -d ' ')
  SCHED_TEST_TOTAL=$((SCHED_TEST_AS_ANY + SCHED_TEST_COLON_ANY))
  if [ "$SCHED_TEST_TOTAL" -eq 0 ]; then
    echo "  ✓ Scheduling test files — zero 'as any' casts and ': any' annotations"
  else
    echo "  ✗ Scheduling test files — $SCHED_TEST_TOTAL untyped reference(s) (${SCHED_TEST_AS_ANY} as-any, ${SCHED_TEST_COLON_ANY} colon-any)"
    echo "    Fix: typed importActual / upfront mockPrisma models / vi.stubGlobal / specific inline types"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # apps/web/src/lib/scheduling/ production source files must have zero 'as any'
  # and zero ': any' annotations — handler.ts, provider.ts, errors.ts, etc.
  LIB_SCHED_AS_ANY=$(grep -rn ' as any' \
    "apps/web/src/lib/scheduling/" \
    --include="*.ts" \
    2>/dev/null \
    | grep -v '\.test\.ts' \
    | wc -l | tr -d ' ')
  LIB_SCHED_COLON_ANY=$(grep -rn ': any\b' \
    "apps/web/src/lib/scheduling/" \
    --include="*.ts" \
    2>/dev/null \
    | grep -v '\.test\.ts' \
    | grep -v ': any\[\]' \
    | wc -l | tr -d ' ')
  LIB_SCHED_TOTAL=$((LIB_SCHED_AS_ANY + LIB_SCHED_COLON_ANY))
  if [ "$LIB_SCHED_TOTAL" -eq 0 ]; then
    echo "  ✓ lib/scheduling production source — zero 'as any' / ': any'"
  else
    echo "  ✗ lib/scheduling production source — $LIB_SCHED_TOTAL untyped reference(s) found"
    echo "    Fix: use toActivityDb() bridge for createActivity calls; specific types elsewhere"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # Scheduling route files (apps/web/src/app/api/scheduling/) must have zero
  # 'as any' casts and zero ': any' annotations in production (non-test) files.
  # This covers the gap #61 left: prior checks covered lib/ and the package
  # but NOT the 30+ route files themselves.
  SCHED_ROUTE_AS_ANY=$(grep -rn ' as any\b' \
    "apps/web/src/app/api/scheduling/" \
    --include="*.ts" \
    2>/dev/null \
    | grep -v '\.test\.' \
    | wc -l | tr -d ' ')
  SCHED_ROUTE_COLON_ANY=$(grep -rn ': any\b' \
    "apps/web/src/app/api/scheduling/" \
    --include="*.ts" \
    2>/dev/null \
    | grep -v '\.test\.' \
    | grep -v ': any\[\]' \
    | wc -l | tr -d ' ')
  SCHED_ROUTE_TOTAL=$((SCHED_ROUTE_AS_ANY + SCHED_ROUTE_COLON_ANY))
  if [ "$SCHED_ROUTE_TOTAL" -eq 0 ]; then
    echo "  ✓ Scheduling route files — zero 'as any' / ': any'"
  else
    echo "  ✗ Scheduling route files — $SCHED_ROUTE_TOTAL untyped reference(s) (${SCHED_ROUTE_AS_ANY} as-any, ${SCHED_ROUTE_COLON_ANY} colon-any)"
    echo "    Fix: catch (error: any) → catch (error); db: any → db: SchedulingDb; use scheduling-error-guards helpers"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # scheduling-auth.ts, scheduling-db.ts, scheduling-error-guards.ts are lib siblings
  # (not inside lib/scheduling/ directory) so the LIB_SCHED check above misses them.
  SCHED_LIB_SIBLING_ANY=$(grep -rn ': any\b\| as any\b' \
    "apps/web/src/lib/scheduling-auth.ts" \
    "apps/web/src/lib/scheduling-db.ts" \
    "apps/web/src/lib/scheduling-error-guards.ts" \
    2>/dev/null \
    | grep -v ': any\[\]' \
    | wc -l | tr -d ' ')
  if [ "$SCHED_LIB_SIBLING_ANY" -eq 0 ]; then
    echo "  ✓ scheduling lib sibling files — zero 'as any' / ': any'"
  else
    echo "  ✗ scheduling lib sibling files — $SCHED_LIB_SIBLING_ANY untyped reference(s)"
    echo "    Fix: scheduling-auth.ts: db: any → db: SchedulingDb + toActivityDb() internally"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # @ordinatio/scheduling must type-check clean (zero TS errors in source files).
  if command -v pnpm &>/dev/null && [ -d "packages/ordinatio-scheduling" ]; then
    SCHED_TC_OUTPUT=$(pnpm --filter @ordinatio/scheduling type-check 2>&1 || true)
    SCHED_TC_ERRORS=$(echo "$SCHED_TC_OUTPUT" | grep 'error TS' | wc -l | tr -d ' ')
    if [ "$SCHED_TC_ERRORS" -gt 0 ]; then
      echo "  ✗ @ordinatio/scheduling type-check: $SCHED_TC_ERRORS error(s)"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    else
      echo "  ✓ @ordinatio/scheduling type-check clean"
    fi
  fi

  # Both cancelAppointment AND rescheduleAppointment must call cancelPendingNotifications.
  # cancelAppointment already does (1 occurrence). After the reschedule fix, there must be 2.
  # Stale REMINDER_24H/1H for the old slot must not fire after reschedule.
  RESCHED_CANCEL=$(grep -c 'await cancelPendingNotifications' \
    "packages/ordinatio-scheduling/src/appointments/crud.ts" 2>/dev/null || echo "0")
  if [ "$RESCHED_CANCEL" -lt 2 ]; then
    echo "  ✗ rescheduleAppointment does not call cancelPendingNotifications — stale reminders will fire"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  else
    echo "  ✓ rescheduleAppointment calls cancelPendingNotifications (stale reminders cancelled)"
  fi

  # Both reschedule routes (staff + client self-service) must call scheduleNotifications
  # with excludeTriggers. New reminders must be scheduled for the new slot; CONFIRMATION
  # excluded because the RESCHEDULE notice is the client's new-time confirmation.
  for RESCHED_ROUTE in \
    "apps/web/src/app/api/scheduling/appointments/[id]/reschedule/route.ts" \
    "apps/web/src/app/api/scheduling/appointments/manage/route.ts"; do
    if [ -f "$RESCHED_ROUTE" ]; then
      if grep -q 'rescheduleAppointment' "$RESCHED_ROUTE" 2>/dev/null; then
        if ! grep -q 'scheduleNotifications' "$RESCHED_ROUTE" 2>/dev/null; then
          echo "  ✗ $RESCHED_ROUTE: does not call scheduleNotifications — new slot reminders never scheduled"
          BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
        elif ! grep -q 'excludeTriggers' "$RESCHED_ROUTE" 2>/dev/null; then
          echo "  ✗ $RESCHED_ROUTE: scheduleNotifications missing excludeTriggers — client gets duplicate CONFIRMATION"
          BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
        else
          echo "  ✓ $(basename $(dirname $RESCHED_ROUTE))/$(basename $RESCHED_ROUTE): scheduleNotifications with excludeTriggers"
        fi
      fi
    fi
  done

  # notification-poller.ts must not define a local escapeHtml.
  # renderTemplate pre-escapes all variables — a local re-escape double-escapes every entity.
  POLLER_FILE="apps/worker/src/polling/notification-poller.ts"
  if [ -f "$POLLER_FILE" ]; then
    if grep -q 'const escapeHtml' "$POLLER_FILE" 2>/dev/null; then
      echo "  ✗ notification-poller.ts defines local escapeHtml — double-escaping corrupts email"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    else
      echo "  ✓ notification-poller.ts does not re-escape (renderTemplate pre-escapes)"
    fi
  fi

  # renderTemplate must accept a channel parameter (third argument) so SMS output
  # is not HTML-escaped. Anchor: presence of stripHtmlTags helper which only exists
  # to strip accidental HTML tags from SMS/plain-text output.
  ENGINE_FILE="packages/ordinatio-scheduling/src/notifications/engine.ts"
  if [ -f "$ENGINE_FILE" ]; then
    if ! grep -q 'stripHtmlTags' "$ENGINE_FILE" 2>/dev/null; then
      echo "  ✗ renderTemplate is channel-unaware — SMS messages will contain HTML entities"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    else
      echo "  ✓ renderTemplate is channel-aware (EMAIL: HTML-escape, SMS: plain text)"
    fi
  fi

  # renderTemplate must use SMS-exception condition — escaping must be the safe default.
  # EMAIL-positive pattern (channel === 'EMAIL' ? escapeHtml : raw) means any future channel
  # silently bypasses HTML escaping. SMS-exception flips this: only SMS opts out.
  if [ -f "$ENGINE_FILE" ]; then
    if grep -q "channel === 'EMAIL' ? escapeHtml" "$ENGINE_FILE" 2>/dev/null; then
      echo "  ✗ renderTemplate uses EMAIL-positive condition — unknown channels bypass HTML escaping"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    else
      echo "  ✓ renderTemplate uses SMS-exception pattern — HTML-escaping is the safe default"
    fi
  fi

  # Template creation and update routes must sanitize body with the strict helper.
  # The existing sanitizeHtml from @/lib/sanitize allows <img> and style — too permissive.
  for TMPL_ROUTE in \
    "apps/web/src/app/api/scheduling/admin/templates/route.ts" \
    "apps/web/src/app/api/scheduling/admin/templates/[id]/route.ts"; do
    if [ -f "$TMPL_ROUTE" ] && grep -qE 'body|subject' "$TMPL_ROUTE" 2>/dev/null; then
      if ! grep -q 'sanitizeNotificationBody(' "$TMPL_ROUTE" 2>/dev/null; then
        echo "  ✗ $TMPL_ROUTE: template body stored unsanitized — XSS via admin-created templates"
        BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
      else
        echo "  ✓ $(basename "$(dirname "$TMPL_ROUTE")")/$(basename "$TMPL_ROUTE"): body sanitized"
      fi
    fi
  done

  # Template PUT route must fetch the existing template's channel (select: { channel: true })
  # before sanitizing the body. Without it, SMS templates are sanitized under EMAIL rules.
  TMPL_PUT_ROUTE="apps/web/src/app/api/scheduling/admin/templates/[id]/route.ts"
  if [ -f "$TMPL_PUT_ROUTE" ] && grep -q 'updateNotificationTemplate' "$TMPL_PUT_ROUTE" 2>/dev/null; then
    if ! grep -q "channel: true" "$TMPL_PUT_ROUTE" 2>/dev/null; then
      echo "  ✗ templates/[id]/route.ts: PUT missing channel fetch — SMS templates sanitized as EMAIL"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    else
      echo "  ✓ templates/[id]/route.ts: PUT fetches channel before sanitizing body"
    fi
  fi

  # Booking route must not use console.warn for scheduleNotifications failures.
  # A warn-only catch means staff have zero visibility when reminders fail to schedule —
  # client gets a booking confirmation and then receives no reminders. Silent.
  APPT_ROUTE="apps/web/src/app/api/scheduling/appointments/route.ts"
  if [ -f "$APPT_ROUTE" ] && grep -q 'scheduleNotifications' "$APPT_ROUTE" 2>/dev/null; then
    if grep -q 'console\.warn' "$APPT_ROUTE" 2>/dev/null; then
      echo "  ✗ appointments/route.ts: scheduleNotifications failure uses console.warn — use logSchedulingActivity"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    else
      echo "  ✓ appointments/route.ts: scheduleNotifications failure routed to activity feed"
    fi
  fi

  # Worker must warn at startup when Twilio is not configured.
  # Without it, SMS notifications silently dead-letter after 3 retries (15 min delay).
  WORKER_INDEX="apps/worker/src/index.ts"
  if [ -f "$WORKER_INDEX" ]; then
    if ! grep -q 'TWILIO_ACCOUNT_SID' "$WORKER_INDEX" 2>/dev/null; then
      echo "  ✗ apps/worker/src/index.ts: missing Twilio startup check — misconfigured worker silently dead-letters SMS"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    else
      echo "  ✓ apps/worker/src/index.ts: Twilio startup check present"
    fi
  fi

  # Worker startup must call registerNotificationArchiveJob.
  # Without it, stale PENDING and terminal notification rows accumulate forever.
  # Table grows at ~4 rows/appointment × all appointments — no cap, no cleanup.
  if grep -q 'registerNotificationArchiveJob' "$WORKER_INDEX" 2>/dev/null; then
    echo "  ✓ apps/worker/src/index.ts: registerNotificationArchiveJob called at startup"
  else
    echo "  ✗ apps/worker/src/index.ts: registerNotificationArchiveJob missing — ScheduledNotification table grows unbounded"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # Seed must define EMAIL + SMS for all on-demand notification triggers.
  # queueImmediateNotification is silent when no template matches a channel —
  # no error thrown, no log, client simply receives nothing for that channel.
  SEED_FILE="scripts/seed-scheduling.ts"
  if [ -f "$SEED_FILE" ]; then
    for TRIGGER in RESCHEDULE CANCELLATION; do
      TMPL_COUNT=$(grep -c "trigger: '${TRIGGER}'" "$SEED_FILE" 2>/dev/null || echo 0)
      if [ "$TMPL_COUNT" -lt 2 ]; then
        echo "  ✗ seed-scheduling.ts: only ${TMPL_COUNT} ${TRIGGER} template(s) — silent notification gap for missing channel"
        BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
      else
        echo "  ✓ seed-scheduling.ts: ${TRIGGER} has EMAIL + SMS templates"
      fi
    done
  fi

  # iCal endpoint must return text/calendar — without this the browser won't trigger download
  ICAL_ROUTE="apps/web/src/app/api/scheduling/appointments/ical/route.ts"
  if [ -f "$ICAL_ROUTE" ]; then
    if grep -q 'text/calendar' "$ICAL_ROUTE" 2>/dev/null; then
      echo "  ✓ iCal route sets text/calendar content type"
    else
      echo "  ✗ iCal route missing text/calendar — browser will not trigger .ics download"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
    if grep -q 'Content-Disposition' "$ICAL_ROUTE" 2>/dev/null; then
      echo "  ✓ iCal route sets Content-Disposition: attachment"
    else
      echo "  ✗ iCal route missing Content-Disposition — file will open in browser instead of downloading"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
    if grep -q 'schedError' "$ICAL_ROUTE" 2>/dev/null; then
      echo "  ✓ iCal route catch block uses schedError (Rule 8 compliant)"
    else
      echo "  ✗ iCal route catch block missing schedError — Rule 8 violation, no diagnostic ref in 500 response"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  fi

  # SCHED_600 must exist in error registry
  ERRORS_FILE="packages/ordinatio-scheduling/src/errors.ts"
  if grep -q 'SCHED_600' "$ERRORS_FILE" 2>/dev/null; then
    echo "  ✓ SCHED_600 registered in scheduling error registry"
  else
    echo "  ✗ SCHED_600 missing from error registry — iCal route has no registered error code"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # manage/route.ts must use schedError in all 3 handlers (Rule 8)
  # GET, DELETE, PATCH each have independent catch blocks — each must emit a ref.
  MANAGE_ROUTE="apps/web/src/app/api/scheduling/appointments/manage/route.ts"
  if [ -f "$MANAGE_ROUTE" ]; then
    MANAGE_SCHED_COUNT=$(grep -c 'schedError' "$MANAGE_ROUTE" 2>/dev/null || echo 0)
    if [ "$MANAGE_SCHED_COUNT" -ge 3 ]; then
      echo "  ✓ manage/route.ts — all 3 handlers use schedError (Rule 8 compliant)"
    else
      echo "  ✗ manage/route.ts — needs schedError in all 3 catch blocks (found ${MANAGE_SCHED_COUNT}/3)"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  fi

  # SCHED_601, SCHED_602, SCHED_603, SCHED_604 must exist in error registry
  for CODE in SCHED_601 SCHED_602 SCHED_603 SCHED_604; do
    if grep -q "$CODE" "$ERRORS_FILE" 2>/dev/null; then
      echo "  ✓ $CODE registered in scheduling error registry"
    else
      echo "  ✗ $CODE missing from error registry — manage route handler has no registered error code"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  done

  # AppointmentType must have configurable reminder timing fields (task #98)
  # Hardcoded 24h/1h/followup values in engine.ts are the failure mode — schema fields prove they're replaced.
  SCHEMA_FILE="packages/database/prisma/schema.prisma"
  for FIELD in reminder1MinsBefore reminder2MinsBefore followupMinsAfter; do
    if grep -q "$FIELD" "$SCHEMA_FILE" 2>/dev/null; then
      echo "  ✓ AppointmentType.$FIELD present in schema (per-type reminder timing)"
    else
      echo "  ✗ AppointmentType.$FIELD missing from schema — reminder timing is hardcoded, not configurable per type"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  done

  # scheduleNotifications must read timing from appointment type, not hardcode 24h/1h
  ENGINE_FILE="packages/ordinatio-scheduling/src/notifications/engine.ts"
  if grep -q 'reminder1MinsBefore' "$ENGINE_FILE" 2>/dev/null; then
    echo "  ✓ scheduleNotifications reads reminder1MinsBefore from appointment type (not hardcoded)"
  else
    echo "  ✗ scheduleNotifications still hardcodes REMINDER_24H timing — must read from appointment type"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # Confirmation email template must include {{icalUrl}} so clients can add to calendar from email
  SEED_FILE="scripts/seed-scheduling.ts"
  if grep -q 'icalUrl' "$SEED_FILE" 2>/dev/null; then
    echo "  ✓ Confirmation email seed template includes {{icalUrl}}"
  else
    echo "  ✗ Confirmation email seed template missing {{icalUrl}} — clients can't add to calendar from email"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # Booking route must set DEPOSIT_PAID (not PAID) when deposit is configured (task #99)
  # Setting PAID for a deposit-only charge makes deposits invisible to staff.
  BOOKING_ROUTE_FILE="apps/web/src/app/api/scheduling/appointments/route.ts"
  if [ -f "$BOOKING_ROUTE_FILE" ]; then
    if grep -q 'DEPOSIT_PAID' "$BOOKING_ROUTE_FILE" 2>/dev/null; then
      echo "  ✓ booking route uses DEPOSIT_PAID status for deposit appointments"
    else
      echo "  ✗ booking route always sets PAID — deposit bookings are indistinguishable from fully paid"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  fi

  # Stripe webhook must handle balance payment intents (paymentType: balance in metadata)
  STRIPE_WEBHOOK_FILE="apps/web/src/app/api/webhooks/stripe/route.ts"
  if [ -f "$STRIPE_WEBHOOK_FILE" ]; then
    if grep -q "paymentType.*balance\|balance.*paymentType" "$STRIPE_WEBHOOK_FILE" 2>/dev/null; then
      echo "  ✓ Stripe webhook handles balance payment intents (paymentType: balance)"
    else
      echo "  ✗ Stripe webhook missing balance PI handler — balance confirmations won't update appointment to PAID"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  fi

  # collect-balance route must exist — staff need a path to charge the remaining balance
  COLLECT_ROUTE="apps/web/src/app/api/scheduling/appointments/[id]/collect-balance/route.ts"
  if [ -f "$COLLECT_ROUTE" ]; then
    echo "  ✓ collect-balance route exists"
  else
    echo "  ✗ collect-balance route missing — staff have no API to charge remaining balance"
    BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
  fi

  # SCHED_605 must exist in error registry
  for CODE in SCHED_605; do
    if grep -q "$CODE" "$ERRORS_FILE" 2>/dev/null; then
      echo "  ✓ $CODE registered in scheduling error registry"
    else
      echo "  ✗ $CODE missing from error registry — collect-balance route has no registered error code"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  done

  # manage/route.ts must select and handle balancePaymentId in DELETE handler.
  # Without it in the select, the refund block can never reach it — silent $150 loss.
  MANAGE_ROUTE_FILE="apps/web/src/app/api/scheduling/appointments/manage/route.ts"
  if [ -f "$MANAGE_ROUTE_FILE" ]; then
    if grep -q 'balancePaymentId' "$MANAGE_ROUTE_FILE" 2>/dev/null; then
      echo "  ✓ manage/route.ts — balancePaymentId present (both PIs refunded on cancel)"
    else
      echo "  ✗ manage/route.ts — balancePaymentId missing — balance PI will not be refunded on cancel"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  fi

  # stripe webhook balance handler must use intent.amount, not type.price, for paymentAmount.
  # type.price is the full service price ($200); intent.amount is what was actually charged ($150).
  WEBHOOK_FILE="apps/web/src/app/api/webhooks/stripe/route.ts"
  if [ -f "$WEBHOOK_FILE" ]; then
    if grep -q "paymentType.*balance" "$WEBHOOK_FILE" 2>/dev/null; then
      if grep -q "intent\.amount" "$WEBHOOK_FILE" 2>/dev/null; then
        echo "  ✓ stripe webhook balance handler — uses intent.amount for paymentAmount (correct)"
      else
        echo "  ✗ stripe webhook balance handler — does not use intent.amount — stores wrong paymentAmount"
        BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
      fi
    fi
  fi

  # collect-balance tests must have 429 coverage.
  COLLECT_BAL_TEST="apps/web/src/app/api/scheduling/appointments/[id]/collect-balance/route.test.ts"
  if [ -f "$COLLECT_BAL_TEST" ]; then
    if grep -q '429' "$COLLECT_BAL_TEST" 2>/dev/null; then
      echo "  ✓ collect-balance tests — 429 rate-limit path covered"
    else
      echo "  ✗ collect-balance tests — missing 429 test (rate-limited path untested)"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  fi

  # stripe webhook balance test must assert paymentAmount as balance amount (not full price).
  STRIPE_TEST="apps/web/src/app/api/webhooks/stripe/route.test.ts"
  if [ -f "$STRIPE_TEST" ]; then
    if grep -qE 'paymentAmount.*150|150.*paymentAmount' "$STRIPE_TEST" 2>/dev/null; then
      echo "  ✓ stripe webhook tests — balance paymentAmount asserted as balance paid (not full price)"
    else
      echo "  ✗ stripe webhook tests — balance paymentAmount not asserted with correct value (150, not 200)"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  fi

  # scheduling-auth.ts verifyAppointmentOwnership must select balancePaymentId.
  # Without it, cancel/route.ts can never refund the balance PI — it's always undefined.
  SCHED_AUTH_FILE="apps/web/src/lib/scheduling-auth.ts"
  if [ -f "$SCHED_AUTH_FILE" ]; then
    if grep -q 'verifyAppointmentOwnership' "$SCHED_AUTH_FILE" 2>/dev/null; then
      if grep -q 'balancePaymentId' "$SCHED_AUTH_FILE" 2>/dev/null; then
        echo "  ✓ scheduling-auth.ts — verifyAppointmentOwnership selects balancePaymentId"
      else
        echo "  ✗ scheduling-auth.ts — balancePaymentId absent from verifyAppointmentOwnership select"
        echo "    cancel/route.ts reads appointment.balancePaymentId — always undefined without this"
        BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
      fi
    fi
  fi

  # cancel/route.ts must refund balancePaymentId when set.
  # Admin cancel is the staff-facing counterpart to self-service cancel.
  # Both must refund all PIs — deposit AND balance.
  STAFF_CANCEL_FILE="apps/web/src/app/api/scheduling/appointments/[id]/cancel/route.ts"
  if [ -f "$STAFF_CANCEL_FILE" ]; then
    if grep -q 'balancePaymentId' "$STAFF_CANCEL_FILE" 2>/dev/null; then
      echo "  ✓ cancel/route.ts — balance PI refund present (balancePaymentId referenced)"
    else
      echo "  ✗ cancel/route.ts — balancePaymentId not referenced — balance PI never refunded on admin cancel"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  fi

  # stripe webhook charge.refunded and payment_intent.payment_failed must use OR query.
  # Balance PIs are never found by paymentId alone — both columns must be searched.
  WEBHOOK_FILE="apps/web/src/app/api/webhooks/stripe/route.ts"
  if [ -f "$WEBHOOK_FILE" ]; then
    if grep -q 'OR:' "$WEBHOOK_FILE" 2>/dev/null; then
      echo "  ✓ stripe webhook — OR query present for balance PI lookup (charge.refunded / payment_failed)"
    else
      echo "  ✗ stripe webhook — no OR query — balance PI events never find their appointment"
      echo "    charge.refunded and payment_intent.payment_failed both need OR: [paymentId, balancePaymentId]"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  fi

  # collect-balance/route.ts must guard against duplicate PI when balancePaymentId already set.
  # Stripe's idempotency key only works within 24h. After that, a new PI is silently created.
  COLLECT_BAL_FILE="apps/web/src/app/api/scheduling/appointments/[id]/collect-balance/route.ts"
  if [ -f "$COLLECT_BAL_FILE" ]; then
    if grep -q 'balancePaymentId' "$COLLECT_BAL_FILE" 2>/dev/null; then
      echo "  ✓ collect-balance/route.ts — balancePaymentId guard present (409 on duplicate)"
    else
      echo "  ✗ collect-balance/route.ts — no balancePaymentId guard — duplicate PI after 24h Stripe window"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  fi

  # cancel/route.ts must handle DEPOSIT_PAID in refund condition.
  # When paymentStatus=DEPOSIT_PAID, the deposit PI must be refunded on admin cancel.
  # The condition === 'PAID' silently skips DEPOSIT_PAID — client loses their deposit.
  # manage/route.ts (self-service) handles this correctly; staff paths must too.
  STAFF_CANCEL_FILE="apps/web/src/app/api/scheduling/appointments/[id]/cancel/route.ts"
  if [ -f "$STAFF_CANCEL_FILE" ]; then
    if grep -q 'DEPOSIT_PAID' "$STAFF_CANCEL_FILE" 2>/dev/null; then
      echo "  ✓ cancel/route.ts — DEPOSIT_PAID handled in refund condition"
    else
      echo "  ✗ cancel/route.ts — DEPOSIT_PAID absent — deposit PI never refunded when admin cancels"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  fi

  # cancel-sync/route.ts must handle DEPOSIT_PAID in refund condition.
  # Calendar-initiated cancellations must refund deposit PIs, same as all other cancel paths.
  SYNC_CANCEL_FILE="apps/web/src/app/api/scheduling/appointments/[id]/cancel-sync/route.ts"
  if [ -f "$SYNC_CANCEL_FILE" ]; then
    if grep -q 'DEPOSIT_PAID' "$SYNC_CANCEL_FILE" 2>/dev/null; then
      echo "  ✓ cancel-sync/route.ts — DEPOSIT_PAID handled in refund condition"
    else
      echo "  ✗ cancel-sync/route.ts — DEPOSIT_PAID absent — deposit PI not refunded on calendar-initiated cancel"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  fi

  # cancel-sync/route.ts must refund balancePaymentId when set.
  # A full cancellation must refund all PIs. cancel-sync was written before balancePaymentId existed.
  if [ -f "$SYNC_CANCEL_FILE" ]; then
    if grep -q 'balancePaymentId' "$SYNC_CANCEL_FILE" 2>/dev/null; then
      echo "  ✓ cancel-sync/route.ts — balancePaymentId refund present"
    else
      echo "  ✗ cancel-sync/route.ts — balancePaymentId absent — balance PI never refunded on calendar-initiated cancel"
      BIZ_RULE_FAIL=$((BIZ_RULE_FAIL + 1))
    fi
  fi

  [ "$BIZ_RULE_FAIL" -gt 0 ] && FAIL_COUNT=$((FAIL_COUNT + BIZ_RULE_FAIL))
  echo ""
fi

# ===========================================
# SECTION 11B: 1701 Bespoke Website Content Seed
# ===========================================
# Runs when the target directory contains the CMS package or scripts directory.
# Verifies that the website content seed is complete:
# A) All 5 required pages are defined (missing page = live 404)
# B) No placeholder content (TODO/PLACEHOLDER/FIXME = client sees draft text on live site)
# C) All 14 blog articles are defined (partial catalog means broken Notes index)
if echo "$TARGET_DIR" | grep -qE 'cms|ordinatio-cms|scripts'; then
  echo "--- 1701 BESPOKE WEBSITE SEED ---"
  WEBSITE_FAIL=0
  BESPOKE_SEED="scripts/seed-1701bespoke.ts"
  if [ -f "$BESPOKE_SEED" ]; then
    for PAGE_SLUG in "home" "bespoke" "made-to-measure" "made-to-measure-online" "about"; do
      if grep -q "'${PAGE_SLUG}'" "$BESPOKE_SEED" 2>/dev/null; then
        echo "  ✓ seed-1701bespoke.ts: page '${PAGE_SLUG}' defined"
      else
        echo "  ✗ seed-1701bespoke.ts: missing page '${PAGE_SLUG}'"
        WEBSITE_FAIL=$((WEBSITE_FAIL + 1))
      fi
    done
    if grep -qiE '\bTODO\b|\bPLACEHOLDER\b|\bFIXME\b|lorem ipsum' "$BESPOKE_SEED" 2>/dev/null; then
      echo "  ✗ seed-1701bespoke.ts: placeholder content found — use real copy from xbe67.ch"
      WEBSITE_FAIL=$((WEBSITE_FAIL + 1))
    else
      echo "  ✓ seed-1701bespoke.ts: no placeholder content"
    fi
    ARTICLE_COUNT=$(grep -c "notes/" "$BESPOKE_SEED" 2>/dev/null || echo 0)
    if [ "$ARTICLE_COUNT" -lt 14 ]; then
      echo "  ✗ seed-1701bespoke.ts: only ${ARTICLE_COUNT}/14 blog articles defined"
      WEBSITE_FAIL=$((WEBSITE_FAIL + 1))
    else
      echo "  ✓ seed-1701bespoke.ts: all 14 blog articles defined"
    fi
  else
    echo "  ✗ seed-1701bespoke.ts: file not found — website has no content"
    WEBSITE_FAIL=$((WEBSITE_FAIL + 1))
  fi
  [ "$WEBSITE_FAIL" -gt 0 ] && FAIL_COUNT=$((FAIL_COUNT + WEBSITE_FAIL))
  echo ""
fi

# ===========================================
# SECTION 12: Theme Integration & Analytics
# ===========================================
# Runs when the target directory contains scheduling or booking paths.
# Verifies:
# A) Public booking pages wrap with SchedulingThemeProvider (client brands apply)
# B) Public booking pages use brand tokens, not hardcoded gray Tailwind classes
# C) The analytics route exists (Phase 1B complete)
#
# Without SchedulingThemeProvider a calendar's theme JSON is fetched but silently
# ignored — the page always looks the same regardless of the business's brand.
if echo "$TARGET_DIR" | grep -qE 'scheduling|book|appt'; then
  echo "--- THEME INTEGRATION ---"
  THEME_FAIL=0

  for page_path in \
    "apps/web/src/app/book/[slug]/page.tsx" \
    "apps/web/src/app/appt/[token]/page.tsx"; do
    if [ -f "$page_path" ]; then
      short=$(echo "$page_path" | sed 's|apps/web/src/app/||')
      if grep -q 'SchedulingThemeProvider' "$page_path" 2>/dev/null; then
        echo "  ✓ $short — SchedulingThemeProvider present"
      else
        echo "  ✗ $short — SchedulingThemeProvider missing (client themes will not apply)"
        echo "    Fix: wrap with <SchedulingThemeProvider theme={calendarTheme}>"
        THEME_FAIL=$((THEME_FAIL + 1))
      fi
      if grep -qE 'bg-gray-[0-9]|text-gray-[0-9]' "$page_path" 2>/dev/null; then
        echo "  ✗ $short — hardcoded gray classes present (use bg-brand-bg, text-brand-text)"
        THEME_FAIL=$((THEME_FAIL + 1))
      else
        echo "  ✓ $short — no hardcoded gray classes"
      fi
    fi
  done

  ANALYTICS_ROUTE="apps/web/src/app/api/scheduling/analytics/route.ts"
  if [ -f "$ANALYTICS_ROUTE" ]; then
    echo "  ✓ analytics/route.ts — Phase 1B analytics route exists"
  else
    echo "  ⚠ analytics/route.ts — missing (Phase 1B not yet complete)"
    # WARN only — analytics is Phase 1B, not blocking Phase 1A gate
  fi

  # Chart component test coverage
  CHART_FAIL=0
  while IFS= read -r comp; do
    short=$(basename "$comp")
    test_file="${comp%.tsx}.test.tsx"
    if [ -f "$test_file" ]; then
      count=$(grep -c '\bit(' "$test_file" 2>/dev/null || echo 0)
      echo "  ✓ $short — $count tests"
    else
      echo "  ✗ $short — no test file (data transformation untested)"
      CHART_FAIL=$((CHART_FAIL + 1))
    fi
  done < <(find apps/web/src/components/scheduling/analytics -name '*.tsx' ! -name '*.test.tsx' 2>/dev/null)

  APPT_TEST="apps/web/src/app/appt/[token]/page.test.tsx"
  if [ -f "$APPT_TEST" ]; then
    count=$(grep -c '\bit(' "$APPT_TEST" 2>/dev/null || echo 0)
    echo "  ✓ appt/[token]/page.tsx — $count tests"
  else
    echo "  ✗ appt/[token]/page.tsx — no test file (cancel + reschedule flows untested)"
    CHART_FAIL=$((CHART_FAIL + 1))
  fi

  FORM_TEST="apps/web/src/app/dashboard/settings/scheduling/types/appointment-type-form.test.tsx"
  if [ -f "$FORM_TEST" ]; then
    form_count=$(grep -c '\bit(' "$FORM_TEST" 2>/dev/null || echo 0)
    echo "  ✓ appointment-type-form.tsx — $form_count tests"
  else
    echo "  ✗ appointment-type-form.tsx — no test file (intake form builder untested)"
    CHART_FAIL=$((CHART_FAIL + 1))
  fi

  DIALOG_TEST="apps/web/src/app/dashboard/appointments/appointment-approval-dialog.test.tsx"
  if [ -f "$DIALOG_TEST" ]; then
    dialog_count=$(grep -c '^\s*it(' "$DIALOG_TEST" 2>/dev/null || echo 0)
    echo "  ✓ appointment-approval-dialog.tsx — $dialog_count tests"
    if [ "$dialog_count" -lt 8 ]; then
      ERRORS+="appointment-approval-dialog.test.tsx has only $dialog_count tests — expected 8+\n\n"
      CHART_FAIL=$((CHART_FAIL + 1))
    fi
  else
    echo "  ✗ appointment-approval-dialog.tsx — no test file (approval/denial flow untested)"
    CHART_FAIL=$((CHART_FAIL + 1))
  fi

  for SETTINGS_KEY in "calendars" "booking" "packages" "policies"; do
    PAGE_TEST="apps/web/src/app/dashboard/settings/scheduling/${SETTINGS_KEY}/page.test.tsx"
    if [ -f "$PAGE_TEST" ]; then
      page_count=$(grep -c '\bit(' "$PAGE_TEST" 2>/dev/null || echo 0)
      echo "  ✓ scheduling/${SETTINGS_KEY}/page.tsx — $page_count tests"
    else
      echo "  ✗ scheduling/${SETTINGS_KEY}/page.tsx — no test file"
      CHART_FAIL=$((CHART_FAIL + 1))
    fi
  done

  # Analytics dashboard page test — required with >= 7 assertions
  ANALYTICS_PAGE_TEST="apps/web/src/app/dashboard/scheduling/analytics/page.test.tsx"
  if [ -f "$ANALYTICS_PAGE_TEST" ]; then
    ana_count=$(grep -c '\bit(' "$ANALYTICS_PAGE_TEST" 2>/dev/null || echo 0)
    if [ "$ana_count" -ge 7 ]; then
      echo "  ✓ scheduling/analytics/page.test.tsx — $ana_count tests"
    else
      echo "  ✗ scheduling/analytics/page.test.tsx — $ana_count tests (need >= 7)"
      CHART_FAIL=$((CHART_FAIL + 1))
    fi
  else
    echo "  ✗ scheduling/analytics/page.test.tsx — MISSING (required, need >= 7)"
    CHART_FAIL=$((CHART_FAIL + 1))
  fi
  # Analytics route must reference BOOKING_ANALYTICS feature flag
  if grep -q 'BOOKING_ANALYTICS' apps/web/src/app/api/scheduling/analytics/route.ts 2>/dev/null; then
    echo "  ✓ analytics/route.ts — BOOKING_ANALYTICS feature flag gated"
  else
    echo "  ✗ analytics/route.ts — missing BOOKING_ANALYTICS feature flag"
    CHART_FAIL=$((CHART_FAIL + 1))
  fi

  # Embed settings page test — required with >= 7 assertions
  EMBED_PAGE_TEST="apps/web/src/app/dashboard/settings/scheduling/embed/page.test.tsx"
  if [ -f "$EMBED_PAGE_TEST" ]; then
    embed_count=$(grep -c '\bit(' "$EMBED_PAGE_TEST" 2>/dev/null || echo 0)
    if [ "$embed_count" -ge 7 ]; then
      echo "  ✓ scheduling/embed/page.test.tsx — $embed_count tests"
    else
      echo "  ✗ scheduling/embed/page.test.tsx — $embed_count tests (need >= 7)"
      CHART_FAIL=$((CHART_FAIL + 1))
    fi
  else
    echo "  ✗ scheduling/embed/page.test.tsx — MISSING (required, need >= 7)"
    CHART_FAIL=$((CHART_FAIL + 1))
  fi
  # Widget standalone bundle — embed.ts entry + IIFE build configured
  if [ -f "packages/ordinatio-booking-widget/src/embed.ts" ]; then
    echo "  ✓ booking-widget/src/embed.ts — standalone init function exists"
    EMBED_UNIT_TEST="packages/ordinatio-booking-widget/__tests__/embed.test.ts"
    if [ -f "$EMBED_UNIT_TEST" ]; then
      embed_unit_count=$(grep -c '\bexpect(' "$EMBED_UNIT_TEST" 2>/dev/null || echo 0)
      if [ "$embed_unit_count" -ge 4 ]; then
        echo "  ✓ booking-widget/__tests__/embed.test.ts — $embed_unit_count assertions (init/destroy behavior)"
      else
        echo "  ✗ booking-widget/__tests__/embed.test.ts — $embed_unit_count assertions (need >= 4)"
        CHART_FAIL=$((CHART_FAIL + 1))
      fi
    else
      echo "  ✗ booking-widget/__tests__/embed.test.ts — MISSING (init/destroy behavior untested)"
      CHART_FAIL=$((CHART_FAIL + 1))
    fi
  else
    echo "  ✗ booking-widget/src/embed.ts — MISSING (standalone bundle entry required)"
    CHART_FAIL=$((CHART_FAIL + 1))
  fi
  if grep -q "'iife'\|\"iife\"" packages/ordinatio-booking-widget/tsup.config.ts 2>/dev/null; then
    echo "  ✓ booking-widget/tsup.config.ts — IIFE build format configured"
  else
    echo "  ✗ booking-widget/tsup.config.ts — missing IIFE build format"
    CHART_FAIL=$((CHART_FAIL + 1))
  fi

  # Booking route intake validation guard
  if grep -q 'intakeForm' apps/web/src/app/api/scheduling/appointments/route.ts 2>/dev/null; then
    echo "  ✓ booking route — intakeForm in appointmentType select (required-field guard)"
  else
    echo "  ✗ booking route — intakeForm not in select (required fields unvalidated)"
    CHART_FAIL=$((CHART_FAIL + 1))
  fi

  # Stripe payment routes
  for PAYMENT_FILE in \
    "apps/web/src/app/api/scheduling/payments/intent/route.ts" \
    "apps/web/src/app/api/webhooks/stripe/route.ts"; do
    TEST_FILE="${PAYMENT_FILE%.ts}.test.ts"
    if [ -f "$PAYMENT_FILE" ]; then
      if [ -f "$TEST_FILE" ]; then
        test_count=$(grep -c '\bit(' "$TEST_FILE" 2>/dev/null || echo 0)
        echo "  ✓ $(basename $(dirname $PAYMENT_FILE))/ — $test_count tests"
      else
        echo "  ✗ $(basename $(dirname $PAYMENT_FILE))/ — no test file"
        CHART_FAIL=$((CHART_FAIL + 1))
      fi
    fi
  done

  # Stripe webhook must cover success + failure scenarios
  if [ -f "apps/web/src/app/api/webhooks/stripe/route.test.ts" ]; then
    if grep -q 'payment_intent.succeeded\|payment_intent.payment_failed' \
       apps/web/src/app/api/webhooks/stripe/route.test.ts 2>/dev/null; then
      echo "  ✓ stripe webhook — success + failure event scenarios covered"
    else
      echo "  ✗ stripe webhook — missing success/failure event scenarios"
      CHART_FAIL=$((CHART_FAIL + 1))
    fi
  fi

  [ "$CHART_FAIL" -gt 0 ] && FAIL_COUNT=$((FAIL_COUNT + CHART_FAIL))

  [ "$THEME_FAIL" -gt 0 ] && FAIL_COUNT=$((FAIL_COUNT + THEME_FAIL))
  echo ""
fi

# ===========================================
# SECTION 13a: Email Activity Visibility Check
# ===========================================
# Any new email.* activity action must declare visibility: 'admin' | 'public'.
# This prevents silently exposing admin-only data to all users.
# ===========================================
ACTIVITY_CONFIG_FILE="packages/ordinatio-activities/src/activity-display-config.ts"
ACTIVITY_TYPES_FILE="packages/ordinatio-activities/src/types.ts"
if [ -f "$ACTIVITY_CONFIG_FILE" ] && [ -f "$ACTIVITY_TYPES_FILE" ]; then
  echo "--- EMAIL ACTIVITY VISIBILITY ---"
  VISIBILITY_FAIL=0
  # Check 1: ActivityDisplayConfig interface must include visibility field
  if grep -q "visibility:" "$ACTIVITY_TYPES_FILE"; then
    echo "  ✓ ActivityDisplayConfig declares visibility field"
  else
    echo "  ✗ ActivityDisplayConfig missing visibility field — add 'visibility: admin | public'"
    VISIBILITY_FAIL=$((VISIBILITY_FAIL + 1))
  fi
  # Check 2: ADMIN_ACTIVITY_ACTIONS must be derived, not hardcoded
  if grep -q "filter.*visibility\|visibility.*filter" "$ACTIVITY_CONFIG_FILE" \
     || grep -q "filter.*visibility\|visibility.*filter" "packages/ordinatio-activities/src/activities.ts" 2>/dev/null; then
    echo "  ✓ ADMIN_ACTIVITY_ACTIONS derived from visibility field (not hardcoded)"
  else
    echo "  ✗ ADMIN_ACTIVITY_ACTIONS appears to be hardcoded — derive from display config"
    VISIBILITY_FAIL=$((VISIBILITY_FAIL + 1))
  fi
  # Check 3: Every ACTIVITY_CONFIG entry must have a visibility value
  config_entries=$(grep -c "requiresResolution:" "$ACTIVITY_CONFIG_FILE" 2>/dev/null || echo 0)
  visibility_entries=$(grep -c "visibility:" "$ACTIVITY_CONFIG_FILE" 2>/dev/null || echo 0)
  if [ "$config_entries" -gt 0 ] && [ "$config_entries" -eq "$visibility_entries" ]; then
    echo "  ✓ all $config_entries activity config entries have visibility field"
  else
    echo "  ✗ config entries ($config_entries) ≠ visibility entries ($visibility_entries) — some actions missing visibility"
    VISIBILITY_FAIL=$((VISIBILITY_FAIL + 1))
  fi

  # Check 4: $transaction must be OPTIONAL in ActivityDb — ? suffix required.
  # Without the ?, Prisma.TransactionClient cannot satisfy ActivityDb and every
  # createActivity(toActivityDb(tx), ...) call inside a transaction crashes at runtime.
  if grep -q '\$transaction?:' "$ACTIVITY_TYPES_FILE"; then
    echo "  ✓ ActivityDb.\$transaction is optional (? suffix present)"
  else
    echo "  ✗ ActivityDb.\$transaction is NOT optional — add ? to prevent in-transaction crash"
    echo "    Fix: change '\$transaction:' to '\$transaction?:' in ActivityDb interface"
    VISIBILITY_FAIL=$((VISIBILITY_FAIL + 1))
  fi

  # Check 5: externalRef must appear in BOTH ActivityDb interface AND CreateActivityInput.
  # TypeScript allows extra properties in arg position — the gap is silent without this check.
  # Before fix: count=1 (only in CreateActivityInput). After fix: count>=2 (also in ActivityDb).
  INTERFACE_EXTERNALREF_COUNT=$(grep -c 'externalRef' "$ACTIVITY_TYPES_FILE" 2>/dev/null || echo 0)
  if [ "$INTERFACE_EXTERNALREF_COUNT" -ge 2 ]; then
    echo "  ✓ externalRef appears in ActivityDb interface (count: $INTERFACE_EXTERNALREF_COUNT)"
  else
    echo "  ✗ externalRef only in CreateActivityInput, missing from ActivityDb.create.data (count: $INTERFACE_EXTERNALREF_COUNT)"
    echo "    Fix: add externalRef?: string | null to ActivityDb.activityLog.create.data in types.ts"
    VISIBILITY_FAIL=$((VISIBILITY_FAIL + 1))
  fi

  # Check 6: No { __proto__: object literals in activities test files.
  # These set the prototype chain, not an own property. Tests using them pass vacuously
  # because deepClean()/Object.entries() never sees the key. Use JSON.parse() instead.
  PROTO_LITERAL_COUNT=$(grep -rn '{ __proto__:' \
    "packages/ordinatio-activities/src/__tests__/" \
    2>/dev/null | wc -l | tr -d ' ')
  if [ "$PROTO_LITERAL_COUNT" -eq 0 ]; then
    echo "  ✓ No vacuous { __proto__: } object literals in activity test files"
  else
    echo "  ✗ $PROTO_LITERAL_COUNT vacuous { __proto__: } literal(s) in activity test files"
    echo "    Fix: use JSON.parse('{\"__proto__\":...}') to create an actual own property"
    VISIBILITY_FAIL=$((VISIBILITY_FAIL + 1))
  fi

  [ "$VISIBILITY_FAIL" -gt 0 ] && FAIL_COUNT=$((FAIL_COUNT + VISIBILITY_FAIL))
  echo ""
fi

# ===========================================
# SECTION 13: Mutation Audit
# ===========================================
# Runs the mutation quality audit for any @ordinatio/* package touched
# by this shipping gate invocation. Conditional on the mutation report
# existing — does not force a mutation run if one hasn't been done.
#
# To trigger this check: run `pnpm mutation:ci` in the package first.
# The audit reads the cached .stryker-tmp/reports/mutation.json.
# ===========================================
ORDINATIO_PKGS=$(find packages/ordinatio-* -maxdepth 0 -type d 2>/dev/null || true)
if [ -n "$ORDINATIO_PKGS" ]; then
  echo "--- MUTATION AUDIT ---"
  MUTATION_CHECKED=0
  for PKG_DIR in $ORDINATIO_PKGS; do
    REPORT="$PKG_DIR/.stryker-tmp/reports/mutation.json"
    if [ -f "$REPORT" ]; then
      MUTATION_CHECKED=$((MUTATION_CHECKED + 1))
      echo "  Running audit for $PKG_DIR..."
      if npx tsx scripts/mutation-audit.ts "$PKG_DIR" 2>&1 | grep -q "AUDIT PASSED"; then
        echo "  ✓ $PKG_DIR mutation audit passed"
      else
        echo "  ✗ $PKG_DIR mutation audit FAILED"
        echo "    Run: cd $PKG_DIR && pnpm mutation:ci && pnpm mutation:audit"
        FAIL_COUNT=$((FAIL_COUNT + 1))
      fi
    fi
  done
  if [ "$MUTATION_CHECKED" -eq 0 ]; then
    echo "  (no mutation reports found — run pnpm mutation:ci in the package first)"
  fi
  echo ""
fi

# ===========================================
# LAYER 12: CALENDAR COMPONENT COVERAGE
# ===========================================
# Enforces that every dashboard scheduling calendar component >100 lines has
# a co-located test file with ≥5 expect() calls. Also checks that components
# using Date.now()/new Date() have useFakeTimers in their test files, so
# time-sensitive UI never breaks as the clock advances.
# ===========================================
CALENDAR_DIR="apps/web/src/app/dashboard/scheduling/calendar"
if echo "$TARGET_DIR" | grep -q 'scheduling' && [ -d "$CALENDAR_DIR" ]; then
  echo "--- LAYER 12: CALENDAR COMPONENT COVERAGE ---"
  L12_FAIL=0

  # Check 1: every non-page, non-test .tsx >100 lines has a test file with ≥5 expect() calls
  for f in $(find "$CALENDAR_DIR" -name "*.tsx" \
      ! -name "page.tsx" ! -name "*.test.tsx" 2>/dev/null); do
    lines=$(wc -l < "$f")
    if [ "$lines" -gt 100 ]; then
      testfile="${f%.tsx}.test.tsx"
      if [ ! -f "$testfile" ]; then
        echo "  ✗ Missing test: $(basename $testfile) ($(basename $f) is $lines lines)"
        L12_FAIL=1
      else
        count=$(grep -c 'expect(' "$testfile" 2>/dev/null || echo 0)
        if [ "$count" -lt 5 ]; then
          echo "  ✗ Insufficient tests: $(basename $testfile) has $count expect() calls (need ≥5)"
          L12_FAIL=1
        else
          echo "  ✓ $(basename $testfile) ($count assertions)"
        fi
      fi
    fi
  done

  # Check 2: components using Date.now()/new Date() must have useFakeTimers in their tests
  for f in $(find "$CALENDAR_DIR" -name "*.tsx" ! -name "*.test.tsx" 2>/dev/null); do
    if grep -qE 'Date\.now\(\)|new Date\(\)' "$f"; then
      testfile="${f%.tsx}.test.tsx"
      if [ -f "$testfile" ] && ! grep -q 'useFakeTimers' "$testfile"; then
        echo "  ✗ $(basename $testfile): component uses Date.now()/new Date() but test has no useFakeTimers()"
        L12_FAIL=1
      fi
    fi
  done

  if [ "$L12_FAIL" -eq 1 ]; then
    echo "  GATE FAILED: Calendar component coverage insufficient"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    echo "  ✓ Calendar component coverage OK"
  fi
  echo ""
fi

# ===========================================
# LAYER 12b: OLD CALENDAR VIEW COVERAGE
# ===========================================
# calendar-view.tsx is a 1500-line component with a critical month-view click
# bug fixed in e72694a. This gate permanently prevents future omission of tests.
# ===========================================
CVIEW="apps/web/src/app/dashboard/appointments/calendar-view.tsx"
CVIEW_TEST="apps/web/src/app/dashboard/appointments/calendar-view.test.tsx"
if [ -f "$CVIEW" ]; then
  echo "--- LAYER 12b: OLD CALENDAR VIEW COVERAGE ---"
  L12B_FAIL=0
  if [ ! -f "$CVIEW_TEST" ]; then
    echo "  ✗ Missing: calendar-view.test.tsx (calendar-view.tsx has no tests)"
    L12B_FAIL=1
  else
    count=$(grep -c 'expect(' "$CVIEW_TEST" 2>/dev/null || echo 0)
    if [ "$count" -lt 8 ]; then
      echo "  ✗ Insufficient: calendar-view.test.tsx has $count expect() calls (need ≥8)"
      L12B_FAIL=1
    else
      echo "  ✓ calendar-view.test.tsx ($count assertions)"
    fi
    if ! grep -q 'month' "$CVIEW_TEST"; then
      echo "  ✗ calendar-view.test.tsx does not cover month view behavior"
      L12B_FAIL=1
    fi
  fi
  if [ "$L12B_FAIL" -eq 1 ]; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
  echo ""
fi

# LAYER 12c: NEW CALENDAR DRAG COVERAGE
ADMIN_CAL="apps/web/src/app/dashboard/scheduling/calendar/admin-calendar-view.tsx"
if [ -f "$ADMIN_CAL" ]; then
  echo "--- LAYER 12c: NEW CALENDAR DRAG COVERAGE ---"
  L12C_FAIL=0
  if ! grep -q 'handleDragStart\|onDragStart\|draggingApptId' "$ADMIN_CAL"; then
    echo "  ✗ AdminCalendarView has no drag implementation"
    L12C_FAIL=1
  else
    echo "  ✓ AdminCalendarView has drag wiring"
  fi
  if ! grep -q 'reschedule' "$ADMIN_CAL"; then
    echo "  ✗ AdminCalendarView does not call reschedule API"
    L12C_FAIL=1
  else
    echo "  ✓ AdminCalendarView calls reschedule API"
  fi
  if [ "$L12C_FAIL" -eq 1 ]; then FAIL_COUNT=$((FAIL_COUNT + 1)); fi
  echo ""
fi

# LAYER 12d: ROUND-ROBIN ENGINE COVERAGE
RRENGINE="packages/ordinatio-scheduling/src/round-robin/engine.ts"
if [ -f "$RRENGINE" ]; then
  echo "--- LAYER 12d: ROUND-ROBIN ENGINE COVERAGE ---"
  L12D_FAIL=0
  RRTEST="packages/ordinatio-scheduling/src/round-robin/engine.test.ts"

  if [ ! -f "$RRTEST" ]; then
    echo "  ✗ No test file for round-robin engine"
    L12D_FAIL=1
  else
    RRASSERT=$(grep -c 'expect(' "$RRTEST" 2>/dev/null || echo 0)
    if [ "$RRASSERT" -lt 20 ]; then
      echo "  ✗ Round-robin engine has $RRASSERT assertions (need ≥20)"
      L12D_FAIL=1
    else
      echo "  ✓ Round-robin engine tested ($RRASSERT assertions)"
    fi

    if ! grep -q 'mockImplementation' "$RRTEST"; then
      echo "  ✗ Round-robin tests missing stateful mock (acid test requires stateful upsert)"
      L12D_FAIL=1
    else
      echo "  ✓ Stateful mock present in engine tests"
    fi

    WIDGET_TEST="packages/ordinatio-booking-widget/__tests__/BookingWidget.team.test.tsx"
    if [ -f "$WIDGET_TEST" ]; then
      if ! grep -q 'not.toHaveProperty\|not.*calendarId' "$WIDGET_TEST"; then
        echo "  ✗ Widget team tests missing calendarId-absence assertion"
        L12D_FAIL=1
      else
        echo "  ✓ Widget verifies calendarId absent from team-mode payload"
      fi
    fi
  fi

  if ! grep -q 'selectCalendarForBooking' "$RRENGINE"; then
    echo "  ✗ Round-robin engine missing selectCalendarForBooking"
    L12D_FAIL=1
  else
    echo "  ✓ selectCalendarForBooking implemented"
  fi

  if ! grep -q 'selectCalendarForBooking' packages/ordinatio-scheduling/src/appointments/crud.ts; then
    echo "  ✗ bookAppointment() does not call selectCalendarForBooking"
    L12D_FAIL=1
  else
    echo "  ✓ bookAppointment() calls selectCalendarForBooking"
  fi

  RRERRORS=$(grep -c 'SCHED_70[012]' packages/ordinatio-scheduling/src/errors.ts 2>/dev/null || echo 0)
  if [ "$RRERRORS" -lt 3 ]; then
    echo "  ✗ SCHED_700/701/702 error codes not all registered (found $RRERRORS of 3)"
    L12D_FAIL=1
  else
    echo "  ✓ Round-robin error codes registered (SCHED_700/701/702)"
  fi

  if ! grep -q 'assignmentStrategy' packages/database/prisma/schema.prisma; then
    echo "  ✗ AppointmentType.assignmentStrategy not in schema"
    L12D_FAIL=1
  else
    echo "  ✓ assignmentStrategy in Prisma schema"
  fi

  if ! grep -q 'RoundRobinState' packages/database/prisma/schema.prisma; then
    echo "  ✗ RoundRobinState model not in schema"
    L12D_FAIL=1
  else
    echo "  ✓ RoundRobinState model in schema"
  fi

  if [ ! -d "apps/web/src/app/book/t" ]; then
    echo "  ✗ /book/t/[typeSlug] route not created"
    L12D_FAIL=1
  else
    echo "  ✓ Team booking page route exists"
  fi

  # Fix #1: LOAD_BALANCED must filter to upcoming appointments in a rolling window
  AVENGINE="packages/ordinatio-scheduling/src/round-robin/engine.ts"
  if ! grep -q 'startTime' "$AVENGINE" 2>/dev/null || ! grep -q 'windowEnd\|lte' "$AVENGINE" 2>/dev/null; then
    echo "  ✗ LOAD_BALANCED groupBy missing rolling time window (gte now + lte +30d) — veterans penalized or far-future bookings bias pool"
    L12D_FAIL=1
  else
    echo "  ✓ LOAD_BALANCED filters to 30-day rolling window (startTime gte now, lte +30d)"
  fi

  # #130: LOAD_BALANCED must exclude CANCELLED appointments from load count
  if ! grep -q "status.*not.*CANCELLED\|CANCELLED.*not" "$AVENGINE" 2>/dev/null; then
    echo "  ✗ LOAD_BALANCED groupBy missing status filter — cancelled appointments inflate load counts"
    L12D_FAIL=1
  else
    echo "  ✓ LOAD_BALANCED groupBy excludes CANCELLED appointments"
  fi

  # Fix #2: getTeamAvailableSlots must use Promise.allSettled for partial-failure resilience
  TEAMAV="packages/ordinatio-scheduling/src/availability/engine.ts"
  if ! grep -q 'Promise.allSettled' "$TEAMAV" 2>/dev/null; then
    echo "  ✗ getTeamAvailableSlots uses Promise.all — one calendar outage kills all availability"
    L12D_FAIL=1
  else
    echo "  ✓ getTeamAvailableSlots uses Promise.allSettled (partial failure resilient)"
  fi

  # Fix #2: injectable _getSlots seam must exist for testability
  if ! grep -q '_getSlots' "$TEAMAV" 2>/dev/null; then
    echo "  ✗ getTeamAvailableSlots missing _getSlots injectable seam (same-file ESM untestable)"
    L12D_FAIL=1
  else
    echo "  ✓ _getSlots injectable seam present in getTeamAvailableSlots"
  fi

  # Issue 3: public type route must NEVER expose organizationId to unauthenticated callers
  if grep -q 'organizationId' apps/web/src/app/api/scheduling/type/route.ts 2>/dev/null; then
    echo "  ✗ Public type route leaks organizationId — remove from select AND response allowlist"
    L12D_FAIL=1
  else
    echo "  ✓ Public type route does not expose organizationId"
  fi

  # Issue 6: no lying casts in production availability engine
  AVENG="packages/ordinatio-scheduling/src/availability/engine.ts"
  if grep -q 'as unknown as' "$AVENG" 2>/dev/null; then
    echo "  ✗ Lying casts in availability/engine.ts — use explicit Prisma select clauses"
    L12D_FAIL=1
  else
    echo "  ✓ No lying casts in availability/engine.ts"
  fi

  # Issue 7: IDOR guard SCHED_102 must be tested
  if ! grep -q 'SCHED_102' packages/ordinatio-scheduling/src/appointments/crud.test.ts 2>/dev/null; then
    echo "  ✗ IDOR guard SCHED_102 not tested — explicit calendarId rejection path untested"
    L12D_FAIL=1
  else
    echo "  ✓ IDOR guard SCHED_102 tested in crud.test.ts"
  fi

  # Issue 4: assignmentStrategy must be a Prisma enum for DB-level constraint
  if ! grep -q '^enum AssignmentStrategy' packages/database/prisma/schema.prisma 2>/dev/null; then
    echo "  ✗ assignmentStrategy is raw String in schema — must be a Prisma enum for DB-level constraint"
    L12D_FAIL=1
  else
    echo "  ✓ AssignmentStrategy is a Prisma enum (DB-level constraint enforced)"
  fi

  # Issue 5: admin types route must expose roundRobinState for rotation debugging
  if ! grep -q 'roundRobinState' apps/web/src/app/api/scheduling/admin/types/route.ts 2>/dev/null; then
    echo "  ✗ Admin types GET missing roundRobinState — admins cannot debug rotation state"
    L12D_FAIL=1
  else
    echo "  ✓ Admin types GET includes roundRobinState"
  fi

  # Issue A: TxClient branded type must enforce tx-only invariant at compile time
  if ! grep -q 'TxClient' packages/ordinatio-scheduling/src/types.ts 2>/dev/null; then
    echo "  ✗ TxClient branded type missing — selectCalendarForBooking tx invariant is documentation-only"
    L12D_FAIL=1
  else
    echo "  ✓ TxClient branded type enforces tx-only invariant at compile time"
  fi

  if ! grep -q 'TxClient' packages/ordinatio-scheduling/src/round-robin/engine.ts 2>/dev/null; then
    echo "  ✗ selectCalendarForBooking signature does not use TxClient"
    L12D_FAIL=1
  else
    echo "  ✓ selectCalendarForBooking uses TxClient in signature"
  fi

  # Issue B: LOAD_BALANCED tiebreak test must not use a weak negative assertion
  RRTESTFILE="packages/ordinatio-scheduling/src/round-robin/engine.test.ts"
  if grep -q "not\.toBe.*'cal-a'" "$RRTESTFILE" 2>/dev/null; then
    echo "  ✗ LOAD_BALANCED tiebreak uses weak .not.toBe('cal-a') — must assert exact expected calendar"
    L12D_FAIL=1
  else
    echo "  ✓ LOAD_BALANCED tiebreak uses exact assertion"
  fi

  # Issue C: P2034 serialization retry path must be tested
  if ! grep -q 'P2034' packages/ordinatio-scheduling/src/appointments/crud.test.ts 2>/dev/null; then
    echo "  ✗ P2034 serialization retry path untested in crud.test.ts"
    L12D_FAIL=1
  else
    echo "  ✓ P2034 retry path tested"
  fi

  # #129: team booking E2E seam tested with real engine (not mocked)
  if [ ! -f "packages/ordinatio-scheduling/src/appointments/crud.integration.test.ts" ]; then
    echo "  ✗ Team booking E2E integration test missing (crud.integration.test.ts)"
    L12D_FAIL=1
  else
    echo "  ✓ Team booking E2E integration test present"
  fi

  # #131: preferredCalendarId in BookAppointmentInput (advisory staff preference)
  if ! grep -q 'preferredCalendarId' packages/ordinatio-scheduling/src/types.ts 2>/dev/null; then
    echo "  ✗ BookAppointmentInput missing preferredCalendarId — staff preference not supported"
    L12D_FAIL=1
  else
    echo "  ✓ BookAppointmentInput has preferredCalendarId"
  fi

  # #131: booking schema must accept preferredCalendarId at API boundary
  if ! grep -q 'preferredCalendarId' apps/web/src/app/api/scheduling/appointments/route.ts 2>/dev/null; then
    echo "  ✗ BookingSchema missing preferredCalendarId — preference lost at API boundary"
    L12D_FAIL=1
  else
    echo "  ✓ BookingSchema accepts preferredCalendarId"
  fi

  # #131: appointment-types public route must expose staffName for StaffPickerRow
  if ! grep -q 'staffName' apps/web/src/app/api/scheduling/appointment-types/route.ts 2>/dev/null; then
    echo "  ✗ appointment-types route missing staffName on calendars — StaffPickerRow has no data"
    L12D_FAIL=1
  else
    echo "  ✓ appointment-types route exposes staffName on calendars"
  fi

  # #131-audit Gap 1: StaffPickerRow must be wired into BookingFlowInner
  if ! grep -q 'StaffPickerRow' packages/ordinatio-booking-widget/src/BookingFlowInner.tsx 2>/dev/null; then
    echo "  ✗ StaffPickerRow not imported/rendered in BookingFlowInner — team staff picker is entirely broken"
    L12D_FAIL=1
  else
    echo "  ✓ StaffPickerRow wired into BookingFlowInner"
  fi

  # #131-audit Gap 2: getType route must expose calendars as an object key (not just in a comment)
  if ! grep -q 'calendars:' apps/web/src/app/api/scheduling/type/route.ts 2>/dev/null; then
    echo "  ✗ getType route missing calendars — state.selectedType.calendars always undefined in team mode"
    L12D_FAIL=1
  else
    echo "  ✓ getType route exposes calendars for team staff picker"
  fi

  # #131-audit Gap 2 (test coverage): getType route test file must exist
  if [ ! -f "apps/web/src/app/api/scheduling/type/route.test.ts" ]; then
    echo "  ✗ getType route missing test file — calendar exposure for team staff picker unverified"
    L12D_FAIL=1
  else
    echo "  ✓ getType route test file present"
  fi

  # #131-audit Gap 3: createBooking must accept preferredCalendarId at the type level
  if ! grep -q 'preferredCalendarId' packages/ordinatio-booking-widget/src/api/client.ts 2>/dev/null; then
    echo "  ✗ createBooking missing preferredCalendarId — preference is a runtime type lie"
    L12D_FAIL=1
  else
    echo "  ✓ createBooking type accepts preferredCalendarId"
  fi

  # #131-audit Gap 4: appointment-types route must return assignmentStrategy
  if ! grep -q 'assignmentStrategy' apps/web/src/app/api/scheduling/appointment-types/route.ts 2>/dev/null; then
    echo "  ✗ appointment-types route missing assignmentStrategy — widget cannot conditionally render staff picker"
    L12D_FAIL=1
  else
    echo "  ✓ appointment-types route exposes assignmentStrategy"
  fi

  # #131-audit Gap 5: team test must verify preferredCalendarId reaches the booking payload
  if ! grep -q 'preferredCalendarId' packages/ordinatio-booking-widget/__tests__/BookingWidget.team.test.tsx 2>/dev/null; then
    echo "  ✗ BookingWidget.team.test.tsx has no test for preferredCalendarId in booking payload"
    L12D_FAIL=1
  else
    echo "  ✓ BookingWidget.team.test.tsx verifies preferredCalendarId in payload"
  fi

  # #131-audit Gap 7: appointment-types route must filter pool calendars by strategy
  if ! grep -q "'NONE'" apps/web/src/app/api/scheduling/appointment-types/route.ts 2>/dev/null; then
    echo "  ✗ appointment-types exposes pool calendar IDs for all strategies — round-robin bypass risk"
    L12D_FAIL=1
  else
    echo "  ✓ appointment-types gates calendar ID exposure by assignment strategy"
  fi

  # #131-audit Gap 7 (test coverage): route test must verify ROUND_ROBIN types stripped
  if ! grep -q 'ROUND_ROBIN\|pool membership\|stripped' apps/web/src/app/api/scheduling/appointment-types/route.test.ts 2>/dev/null; then
    echo "  ✗ appointment-types route test missing ROUND_ROBIN calendar stripping test"
    L12D_FAIL=1
  else
    echo "  ✓ appointment-types route test verifies ROUND_ROBIN calendar stripping"
  fi

  # #131-audit Gap 8: StaffPickerRow container must have ARIA group role
  if ! grep -q 'role="group"' packages/ordinatio-booking-widget/src/components/StaffPickerRow.tsx 2>/dev/null; then
    echo "  ✗ StaffPickerRow missing role=\"group\" — screen readers cannot group the picker chips"
    L12D_FAIL=1
  else
    echo "  ✓ StaffPickerRow has accessibility role=\"group\""
  fi

  # #132 Layer 1: AppointmentWithDetails must declare staffName (awk scopes to that interface block)
  if ! awk '/interface AppointmentWithDetails/,/^}/' packages/ordinatio-scheduling/src/types.ts 2>/dev/null | grep -q 'staffName'; then
    echo "  ✗ AppointmentWithDetails missing staffName — POST response spread cannot carry staff person's name"
    L12D_FAIL=1
  else
    echo "  ✓ AppointmentWithDetails.staffName declared"
  fi

  # #132 Layer 2: bookAppointment Prisma select must fetch staffName from the DB
  if ! grep -q 'staffName: true' packages/ordinatio-scheduling/src/appointments/crud.ts 2>/dev/null; then
    echo "  ✗ bookAppointment Prisma select missing staffName: true — DB never returns staff person's name"
    L12D_FAIL=1
  else
    echo "  ✓ bookAppointment Prisma select includes staffName: true"
  fi

  # #132 Layer 3: appointments GET route must select and expose staffName
  if ! grep -q 'staffName' apps/web/src/app/api/scheduling/appointments/route.ts 2>/dev/null; then
    echo "  ✗ appointments GET route missing staffName — admin view shows calendar display name not staff person"
    L12D_FAIL=1
  else
    echo "  ✓ appointments GET route exposes staffName"
  fi

  # #132 Layer 4: BookedAppointment widget type must declare staffName (awk scopes to that interface block)
  if ! awk '/interface BookedAppointment/,/^}/' packages/ordinatio-booking-widget/src/types.ts 2>/dev/null | grep -q 'staffName'; then
    echo "  ✗ BookedAppointment type missing staffName — ConfirmStep can only receive calendarName"
    L12D_FAIL=1
  else
    echo "  ✓ BookedAppointment.staffName declared in widget types"
  fi

  # #132 Layer 5: BookingFlowInner must pass bookedAppointment.staffName to ConfirmStep
  if ! grep -q 'bookedAppointment\.staffName' packages/ordinatio-booking-widget/src/BookingFlowInner.tsx 2>/dev/null; then
    echo "  ✗ BookingFlowInner passes calendarName as assignedStaffName — shows 'Alice's Calendar' not 'Alice Smith'"
    L12D_FAIL=1
  else
    echo "  ✓ BookingFlowInner uses bookedAppointment.staffName (with calendarName fallback)"
  fi

  # #133: appointment-types crud must validate calendarIds against org — prevents cross-org calendar links
  if ! grep -q 'validateCalendarOrg' packages/ordinatio-scheduling/src/appointment-types/crud.ts 2>/dev/null; then
    echo "  ✗ appointment-types crud missing validateCalendarOrg — cross-org calendar links not blocked at creation or update"
    L12D_FAIL=1
  else
    echo "  ✓ appointment-types crud validates calendarIds against org"
  fi

  # #133 audit: validateCalendarOrg must deduplicate — duplicate IDs cause false SCHED_203 (SQL IN dedupes but .length doesn't)
  if ! grep -q 'new Set(calendarIds)' packages/ordinatio-scheduling/src/appointment-types/crud.ts 2>/dev/null; then
    echo "  ✗ #133 audit: validateCalendarOrg missing new Set(calendarIds) — duplicate IDs → count < length → false SCHED_203"
    L12D_FAIL=1
  else
    echo "  ✓ #133 audit: validateCalendarOrg deduplicates before count comparison"
  fi

  # #134: assignmentStrategy downgrade must be blocked when active appointments exist
  if ! grep -q 'SCHED_204' packages/ordinatio-scheduling/src/appointment-types/crud.ts 2>/dev/null; then
    echo "  ✗ appointment-types crud missing SCHED_204 — ROUND_ROBIN/LOAD_BALANCED→NONE downgrade not guarded against active appointments"
    L12D_FAIL=1
  else
    echo "  ✓ appointment-types crud guards assignmentStrategy downgrade with SCHED_204"
  fi

  # #135: ROUND_ROBIN/LOAD_BALANCED type must require a non-empty calendar pool
  if ! grep -q 'SCHED_205' packages/ordinatio-scheduling/src/appointment-types/crud.ts 2>/dev/null; then
    echo "  ✗ appointment-types crud missing SCHED_205 — team-strategy types can be saved with zero calendars causing silent booking failures"
    L12D_FAIL=1
  else
    echo "  ✓ appointment-types crud validates non-empty calendar pool for team strategies (SCHED_205)"
  fi

  # #137: admin must be able to reset RoundRobinState via DELETE route
  if [ ! -f "apps/web/src/app/api/scheduling/admin/types/[id]/round-robin-state/route.ts" ]; then
    echo "  ✗ round-robin-state DELETE route missing — admin cannot reset rotation state after a member leaves"
    L12D_FAIL=1
  else
    echo "  ✓ round-robin-state DELETE route exists"
  fi

  # #138: LOAD_BALANCED groupBy must use a rolling time window (lte bound) — not just gte now
  if ! grep -q 'lte' packages/ordinatio-scheduling/src/round-robin/engine.ts 2>/dev/null; then
    echo "  ✗ LOAD_BALANCED groupBy missing upper time bound — appointments years away inflate load counts unfairly"
    L12D_FAIL=1
  else
    echo "  ✓ LOAD_BALANCED groupBy uses rolling time window (gte + lte)"
  fi

  # #139: availability checks must be batched (Promise.all) not serial — N calendars → N concurrent checks
  if ! grep -q 'Promise.all.*isSlotAvailable\|isSlotAvailable.*Promise.all\|availabilities.*Promise.all\|Promise.all.*availab' packages/ordinatio-scheduling/src/round-robin/engine.ts 2>/dev/null; then
    echo "  ✗ round-robin engine checks availability serially — large pools add latency proportional to pool size"
    L12D_FAIL=1
  else
    echo "  ✓ round-robin engine batches availability checks with Promise.all"
  fi

  # Audit Gap 1: schedErrorStatus helper must exist — routes use it to map SCHED codes to HTTP statuses
  if ! grep -q 'schedErrorStatus' apps/web/src/lib/scheduling-error-guards.ts 2>/dev/null; then
    echo "  ✗ Gap 1: schedErrorStatus missing in scheduling-error-guards.ts — SCHED_203/204/205 return 500"
    L12D_FAIL=1
  else
    echo "  ✓ Gap 1: schedErrorStatus helper present"
  fi

  # Audit Gap 1b: POST /admin/types must use schedErrorStatus
  if ! grep -q 'schedErrorStatus' apps/web/src/app/api/scheduling/admin/types/route.ts 2>/dev/null; then
    echo "  ✗ Gap 1b: POST /admin/types does not call schedErrorStatus — SCHED_203/205 → 500"
    L12D_FAIL=1
  else
    echo "  ✓ Gap 1b: POST /admin/types uses schedErrorStatus"
  fi

  # Audit Gap 1c: PUT /admin/types/[id] must use schedErrorStatus
  if ! grep -q 'schedErrorStatus' "apps/web/src/app/api/scheduling/admin/types/[id]/route.ts" 2>/dev/null; then
    echo "  ✗ Gap 1c: PUT /admin/types/[id] does not call schedErrorStatus — SCHED_203/204/205 → 500"
    L12D_FAIL=1
  else
    echo "  ✓ Gap 1c: PUT /admin/types/[id] uses schedErrorStatus"
  fi

  # Audit Gap 2: requireCalendarPool must use effective strategy (input ?? existing)
  if ! grep -q 'input\.assignmentStrategy ?? existing\.assignmentStrategy' packages/ordinatio-scheduling/src/appointment-types/crud.ts 2>/dev/null; then
    echo "  ✗ Gap 2: requireCalendarPool only sees input.assignmentStrategy — ROUND_ROBIN types bypass pool guard on partial update"
    L12D_FAIL=1
  else
    echo "  ✓ Gap 2: requireCalendarPool uses effective strategy (input ?? existing)"
  fi

  # Audit Gap 3: no bare catch in appointment-type-form.tsx (Rule 8 violation)
  if grep -q 'catch {' apps/web/src/app/dashboard/settings/scheduling/types/appointment-type-form.tsx 2>/dev/null; then
    echo "  ✗ Gap 3: bare catch {} in appointment-type-form.tsx — reset rotation errors silently swallowed"
    L12D_FAIL=1
  else
    echo "  ✓ Gap 3: no bare catch in appointment-type-form.tsx"
  fi

  # Audit Gap 4: round-robin-state route must have a test file
  if [ ! -f "apps/web/src/app/api/scheduling/admin/types/[id]/round-robin-state/route.test.ts" ]; then
    echo "  ✗ Gap 4: round-robin-state/route.test.ts missing — DELETE endpoint has zero coverage"
    L12D_FAIL=1
  else
    echo "  ✓ Gap 4: round-robin-state route test file exists"
  fi

  # #29 audit Gap #4: LOAD_BALANCED first-booking-ever behavior must be documented in engine.test.ts
  if ! grep -q 'first booking ever' packages/ordinatio-scheduling/src/round-robin/engine.test.ts 2>/dev/null; then
    echo "  ✗ #29 audit Gap #4: engine.test.ts missing 'first booking ever' test — undocumented tiebreak behavior"
    L12D_FAIL=1
  else
    echo "  ✓ #29 audit Gap #4: LOAD_BALANCED first-booking-ever behavior documented in engine.test.ts"
  fi

  # #29 audit Gap #6: admin GET must have explicit cross-org test (org-999 sentinel)
  if ! grep -q 'org-999' apps/web/src/app/api/scheduling/admin/types/route.test.ts 2>/dev/null; then
    echo "  ✗ #29 audit Gap #6: route.test.ts missing cross-org test — org scoping not proven by tests"
    L12D_FAIL=1
  else
    echo "  ✓ #29 audit Gap #6: admin GET cross-org scoping verified in route.test.ts"
  fi

  # #29 audit Gap #5: stale lastCalendarId cleanup — crud.ts must clear pointer when calendar removed from pool
  if ! grep -q 'roundRobinState\.updateMany' packages/ordinatio-scheduling/src/appointment-types/crud.ts 2>/dev/null; then
    echo "  ✗ #29 audit Gap #5: crud.ts missing roundRobinState.updateMany — stale lastCalendarId not cleaned on pool change"
    L12D_FAIL=1
  else
    echo "  ✓ #29 audit Gap #5: crud.ts cleans stale lastCalendarId on pool change"
  fi

  # #29 audit Gap #3: reset rotation must require two-step confirmation — pendingReset state
  if ! grep -q 'pendingReset' apps/web/src/app/dashboard/settings/scheduling/types/appointment-type-form.tsx 2>/dev/null; then
    echo "  ✗ #29 audit Gap #3: appointment-type-form.tsx missing pendingReset — destructive reset fires immediately"
    L12D_FAIL=1
  else
    echo "  ✓ #29 audit Gap #3: reset rotation requires two-step confirmation"
  fi

  # #29 audit Gap #1: team booking empty state must be distinguishable from normal closed day
  if ! grep -q 'isTeamType' packages/ordinatio-booking-widget/src/steps/TimeStep.tsx 2>/dev/null; then
    echo "  ✗ #29 audit Gap #1: TimeStep.tsx missing isTeamType — team-fully-booked identical to closed day"
    L12D_FAIL=1
  else
    echo "  ✓ #29 audit Gap #1: TimeStep shows differentiated team-fully-booked message"
  fi

  # #29 audit Gap #2: manual staff reassignment route must exist
  if [ ! -f "apps/web/src/app/api/scheduling/appointments/[id]/reassign/route.ts" ]; then
    echo "  ✗ #29 audit Gap #2: reassign/route.ts missing — no way to manually reassign after booking"
    L12D_FAIL=1
  else
    echo "  ✓ #29 audit Gap #2: staff reassignment route exists"
  fi

  if [ "$L12D_FAIL" -eq 1 ]; then FAIL_COUNT=$((FAIL_COUNT + 1)); fi
  echo ""
fi

# ===========================================
# LAYER 13: COMPOSE POPOUT PAGE COVERAGE
# ===========================================
# The compose/popout page has no nav or auth wrapping — if it ships untested,
# regressions (expired draft handling, wrong mode rendering) are invisible.
# ===========================================
echo "--- LAYER 13: COMPOSE POPOUT PAGE COVERAGE ---"
POPOUT_PAGE="apps/web/src/app/compose/popout/page.tsx"
if [ -f "$POPOUT_PAGE" ]; then
  POPOUT_TEST="apps/web/src/app/compose/popout/page.test.tsx"
  if [ ! -f "$POPOUT_TEST" ]; then
    echo "  ✗ compose/popout/page.tsx exists but has no co-located test"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    count=$(grep -c 'expect(' "$POPOUT_TEST" 2>/dev/null || echo 0)
    if [ "$count" -lt 5 ]; then
      echo "  ✗ page.test.tsx has $count expect() calls (need >= 5)"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  fi
fi

# compose/layout.tsx must exist — prevents dashboard sidebar from appearing in popout window
COMPOSE_LAYOUT="apps/web/src/app/compose/layout.tsx"
if [ ! -f "$COMPOSE_LAYOUT" ]; then
  echo "  ✗ compose/layout.tsx missing — dashboard sidebar renders inside popout window"
  FAIL_COUNT=$((FAIL_COUNT + 1))
else
  echo "  ✓ compose/layout.tsx exists (popout window has bare layout)"
fi

# readDraft must appear only inside useState initializer in popout page
if [ -f "$POPOUT_PAGE" ] && grep -q "readDraft(" "$POPOUT_PAGE" 2>/dev/null; then
  RENDER_VIOLATION=$(grep -n "readDraft(" "$POPOUT_PAGE" 2>/dev/null \
    | grep -E "^[[:space:]]*[0-9]+:[[:space:]]*(const|let|var) " \
    | grep -v "useState\|import" \
    | wc -l | tr -d ' ')
  if [ "$RENDER_VIOLATION" != "0" ]; then
    echo "  ✗ readDraft() called outside useState initializer in popout page — render side-effect bug"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
fi
echo ""

# ===========================================
# FINAL VERDICT
# ===========================================
echo "=== RESULT ==="
if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "GATE FAILED: $FAIL_COUNT check(s) failed. Fix before shipping."
  echo "=== END REPORT ==="
  exit 1
fi

echo "GATE PASSED: All checks green."
echo "=== END REPORT ==="
exit 0
