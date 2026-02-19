#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# YEET SessionStart Hook — Handoff Injector
# ─────────────────────────────────────────────────────────────────────────────
#
# When a new session starts in a directory with .yeet/handoff.json, this
# hook injects the handoff contents into the agent's context. This is how
# Hook Mode workers receive context from the previous worker.
#
# In Headless Mode, this hook is informational only — the lead agent reads
# handoff files directly via tool calls.
#
# The handoff is marked as consumed (renamed to .consumed) to prevent
# duplicate injection if the session restarts.
#
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null)

YEET_DIR="${CWD}/.yeet"
HANDOFF_FILE="${YEET_DIR}/handoff.json"

# ── Check for pending handoff ───────────────────────────────────────────────
if [ ! -f "$HANDOFF_FILE" ]; then
  exit 0
fi

# Read handoff contents
HANDOFF_CONTENT=$(cat "$HANDOFF_FILE" 2>/dev/null || echo "{}")

# Only inject if the handoff has actual content and is in "handoff" status
STATUS=$(echo "$HANDOFF_CONTENT" | jq -r '.status // ""' 2>/dev/null)
if [ "$STATUS" != "handoff" ]; then
  exit 0
fi

# Mark as consumed so it doesn't re-inject on session restart
mv "$HANDOFF_FILE" "${HANDOFF_FILE}.consumed"

# Build the context injection message
# This tells the agent what the previous worker did and what to do next
TASK_ID=$(echo "$HANDOFF_CONTENT" | jq -r '.task_id // "unknown"' 2>/dev/null)
LAST_TOOL=$(echo "$HANDOFF_CONTENT" | jq -r '.last_tool // "unknown"' 2>/dev/null)
TIMESTAMP=$(echo "$HANDOFF_CONTENT" | jq -r '.timestamp // "unknown"' 2>/dev/null)

# Escape for JSON embedding
ESCAPED_CONTENT=$(echo "$HANDOFF_CONTENT" | jq -Rs '.')

# Inject into context via additionalContext
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "YEET HANDOFF RECEIVED — You are a YEET worker for task ${TASK_ID}. The previous worker completed an action at ${TIMESTAMP} using ${LAST_TOOL}. Full handoff data: ${HANDOFF_CONTENT}. Read .yeet/state.json for your current assignment. Execute exactly ONE atomic action, then stop."
  }
}
EOF

exit 0
