#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# YEET PostToolUse Hook — Atomic Boundary Enforcer
# ─────────────────────────────────────────────────────────────────────────────
#
# Fires after every tool call. Increments a counter. When the counter hits
# the atomic boundary, writes a structured handoff file and drops a poison
# flag so PreToolUse blocks all subsequent tool calls.
#
# ONLY ACTIVE when .yeet/hook-mode exists in cwd. This makes the entire
# hook a no-op for Headless Mode sessions and non-YEET sessions. The guard
# check is the first thing that runs — zero overhead when inactive.
#
# Flow:
#   Tool executes → PostToolUse fires → counter++ → boundary check
#   If boundary hit:
#     1. Write handoff.json (atomic: tmp → sync → rename)
#     2. Archive to .yeet/history/
#     3. Drop .yeet/poison sentinel
#     4. Reset counter for next worker
#     5. Inject systemMessage telling agent to stop
#   PreToolUse sees poison → blocks everything → agent starves → dies
#
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Read hook input from stdin ───────────────────────────────────────────────
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
TOOL_INPUT=$(echo "$INPUT" | jq -c '.tool_input // {}' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null)

YEET_DIR="${CWD}/.yeet"

# ── Guard: only active in Hook Mode ─────────────────────────────────────────
# If .yeet/hook-mode doesn't exist, this hook is completely dormant.
# Headless Mode and non-YEET sessions skip immediately.
if [ ! -f "${YEET_DIR}/hook-mode" ]; then
  exit 0
fi

# ── Skip overhead operations ────────────────────────────────────────────────
# YEET-internal file operations (reading/writing .yeet/ files) are
# orchestration overhead — they don't count toward the atomic boundary.
# Without this filter, the agent would hit the boundary just by reading
# its own handoff file.
case "$TOOL_NAME" in
  Read|Glob|Grep)
    FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // .path // .pattern // ""' 2>/dev/null)
    if echo "$FILE_PATH" | grep -q '\.yeet'; then
      exit 0
    fi
    ;;
  Write)
    FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // ""' 2>/dev/null)
    if echo "$FILE_PATH" | grep -q '\.yeet'; then
      exit 0
    fi
    ;;
esac

# ── Increment counter ───────────────────────────────────────────────────────
COUNTER_FILE="${YEET_DIR}/counter.txt"
COUNTER=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
COUNTER=$((COUNTER + 1))
echo "$COUNTER" > "$COUNTER_FILE"

# ── Read boundary limit ─────────────────────────────────────────────────────
# Default boundary is 1 (one action per worker). Can be tuned per-task
# by writing a different number to .yeet/boundary.txt.
BOUNDARY=$(cat "${YEET_DIR}/boundary.txt" 2>/dev/null || echo "1")

# ── Check if boundary hit ───────────────────────────────────────────────────
if [ "$COUNTER" -ge "$BOUNDARY" ]; then

  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  TASK_ID=$(cat "${YEET_DIR}/task-id.txt" 2>/dev/null || echo "unknown")

  # Build handoff JSON with everything the next worker needs to know:
  # - What tool was just called (last_tool + last_tool_input)
  # - When the boundary hit (timestamp)
  # - Which session produced this (session_id)
  HANDOFF=$(jq -n \
    --arg task_id "$TASK_ID" \
    --arg tool_name "$TOOL_NAME" \
    --argjson tool_input "$TOOL_INPUT" \
    --arg timestamp "$TIMESTAMP" \
    --arg session_id "$SESSION_ID" \
    '{
      task_id: $task_id,
      last_tool: $tool_name,
      last_tool_input: $tool_input,
      timestamp: $timestamp,
      session_id: $session_id,
      boundary_hit: true,
      status: "handoff"
    }')

  # Atomic write: tmp file → sync → rename. This guarantees the handoff
  # is fully on disk before the poison flag is set. A half-written handoff
  # is worse than no handoff.
  echo "$HANDOFF" > "${YEET_DIR}/handoff.json.tmp"
  sync
  mv "${YEET_DIR}/handoff.json.tmp" "${YEET_DIR}/handoff.json"

  # Archive to history for audit trail
  mkdir -p "${YEET_DIR}/history"
  HISTORY_COUNT=$(ls "${YEET_DIR}/history/" 2>/dev/null | wc -l)
  NEXT=$((HISTORY_COUNT + 1))
  cp "${YEET_DIR}/handoff.json" "${YEET_DIR}/history/$(printf '%03d' "$NEXT").json"

  # ── DROP THE POISON ────────────────────────────────────────────────────
  # This sentinel file is what actually kills the agent. PreToolUse checks
  # for it and blocks ALL subsequent tool calls. The agent literally cannot
  # do anything after this point.
  touch "${YEET_DIR}/poison"

  # Reset counter for the next worker cycle
  echo "0" > "$COUNTER_FILE"

  # Inject system message — belt AND suspenders. The poison blocks tools,
  # but this message tells the agent WHY and instructs it to stop cleanly.
  echo '{"systemMessage": "YEET BOUNDARY REACHED. Your atomic action is complete. Handoff has been written to .yeet/handoff.json. All subsequent tool calls will be BLOCKED. Summarize what you accomplished and stop immediately."}'
  exit 0
fi

# Not at boundary — silent pass
exit 0
