#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# YEET PreToolUse Hook — Poison File Enforcer
# ─────────────────────────────────────────────────────────────────────────────
#
# Checks for the .yeet/poison sentinel file. If present, BLOCKS all tool
# calls. This is the actual kill mechanism in Hook Mode — the agent cannot
# execute any tools after the atomic boundary is hit.
#
# The flow:
#   1. PostToolUse hits boundary → writes handoff → drops .yeet/poison
#   2. Agent tries to call another tool
#   3. THIS hook fires → sees poison → exit 2 → tool call DENIED
#   4. Agent tries again → denied again → can't do anything
#   5. max_turns exhausted → session terminates cleanly
#
# Exit code 2 = PreToolUse denial (same as security-guidance plugin).
# The JSON output provides both the formal deny decision and a human-
# readable systemMessage explaining what happened.
#
# ONLY ACTIVE when .yeet/hook-mode exists in cwd.
#
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null)
YEET_DIR="${CWD}/.yeet"

# ── Guard: only active in Hook Mode ─────────────────────────────────────────
if [ ! -f "${YEET_DIR}/hook-mode" ]; then
  exit 0
fi

# ── Check poison flag ───────────────────────────────────────────────────────
if [ -f "${YEET_DIR}/poison" ]; then
  # Two-layer denial:
  # 1. JSON permissionDecision: "deny" — Claude Code's formal tool blocking
  # 2. Exit code 2 — OS-level signal that this is a hard block
  #
  # The systemMessage explains why. The agent sees this and understands
  # it's been killed by YEET, not encountering a random error.
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny"
  },
  "systemMessage": "YEET: Atomic boundary was reached. All tool calls are BLOCKED. Your handoff was already written to .yeet/handoff.json. You must stop now — summarize your work and exit."
}
EOF
  exit 2
fi

# No poison — allow the tool call
exit 0
