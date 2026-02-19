# YEET

Ralph loops until done. **YEET loops once and dies on purpose.**

YEET is a Claude Code plugin that implements forced single-action atomic execution with external lifecycle control. Instead of letting agents run until context death, YEET kills them intentionally after exactly one atomic task and respawns them fresh.

Zero context bloat. Infinite task chains. Every worker is born clean and dies young.

## How It Works

```
Lead Agent (you)
  │
  ├─ Breaks task into atomic steps
  │
  ├─ Step 1: Spawn worker ──→ Worker does ONE thing ──→ Dies ──→ Output captured
  ├─ Step 2: Spawn worker ──→ Worker does ONE thing ──→ Dies ──→ Output captured
  ├─ Step 3: Spawn worker ──→ Worker does ONE thing ──→ Dies ──→ Output captured
  │   ...
  └─ All steps done ──→ Report results
```

Each worker is a disposable `claude -p` subprocess. It executes one action, returns a JSON result, and the process exits. The lead reads the result, spawns the next worker with fresh context, and repeats. The process exit IS the kill mechanism — no hooks, no signals, no hacks.

## Two Modes

### Headless Mode (Primary)

Workers are `claude -p` subprocesses. Process lifecycle IS the boundary. When the process exits, the worker is dead.

```
Lead ──bash──→ claude -p "create index.js" ──→ exits ──→ result captured
Lead ──bash──→ claude -p "create test.js"  ──→ exits ──→ result captured
```

**Use when:** You want the simplest, most reliable atomic execution. This is the default.

**Kill mechanism:** Process exit. The `claude -p` command finishes and the OS reclaims everything. No context survives.

**Safety valves:**
- `--max-budget-usd 0.50` caps cost per worker
- `--no-session-persistence` prevents disk state accumulation
- `--allowedTools` restricts what the worker can touch

### Hook Mode (Fallback)

Workers are Agent Teams subagents. PostToolUse and PreToolUse hooks enforce the atomic boundary.

```
Lead ──Task──→ Sub does ONE thing
                  │
                  ├─ PostToolUse fires ──→ counter hits boundary
                  │   ├─ Writes handoff.json (atomic: tmp → sync → rename)
                  │   ├─ Archives to .yeet/history/
                  │   └─ Drops .yeet/poison sentinel
                  │
                  ├─ Sub tries another tool call
                  │   └─ PreToolUse fires ──→ sees poison ──→ EXIT 2 ──→ DENIED
                  │
                  └─ max_turns exhausted ──→ Sub dies ──→ Lead reads handoff
```

**Use when:** You need Agent Teams features (team messaging, shared task lists) or `claude -p` isn't available.

**Kill mechanism:** PreToolUse exit code 2 blocks ALL tool calls after the boundary. The agent literally cannot do anything. Combined with `max_turns: 3` on the Task spawn, the agent starves and dies.

**Guard rails:**
- Hooks are completely dormant unless `.yeet/hook-mode` exists in cwd
- YEET-internal file operations (reading/writing `.yeet/` files) don't count toward the boundary
- Handoff writes are atomic (tmp → sync → rename) to prevent corruption
- Boundary limit is configurable via `.yeet/boundary.txt` (default: 1 action)

## Installation

```bash
# From your Claude Code session:
/plugin install <path-to-yeet-directory>

# Or if published to a marketplace:
/plugin install yeet
```

## Usage

```
/yeet Create a Node.js project with three files: index.js that exports
a greet function, test.js that imports and calls greet, and package.json
with name "yeet-demo"
```

YEET will:
1. Break the task into 3 atomic steps
2. Spawn Worker 1 → creates `package.json` → dies
3. Spawn Worker 2 → creates `index.js` → dies
4. Spawn Worker 3 → creates `test.js` → dies
5. Report results

Each worker has zero knowledge of the others. The lead passes only the context each worker needs via its prompt.

## State Directory

```
.yeet/
├── state.json      # Task state: steps, results, status
├── task-id.txt     # 8-char hex task identifier
├── boundary.txt    # Actions per worker (default: 1)
├── handoff.json    # Latest handoff data (Hook Mode)
├── counter.txt     # Tool call counter (Hook Mode)
├── poison          # Kill sentinel (Hook Mode) — existence = blocked
├── hook-mode       # Sentinel: activates Hook Mode hooks
└── history/        # Archived handoffs (audit trail)
    ├── 001.json
    ├── 002.json
    └── ...
```

## Architecture Decisions

**Why `claude -p` over Agent Teams for the primary mode?**

Process lifecycle is the cleanest kill mechanism available. When `claude -p` exits, the OS reclaims everything — memory, file handles, context. There's nothing to corrupt, nothing to leak, nothing to clean up. The nesting check is bypassed with `env -u CLAUDECODE`.

**Why Hook Mode as fallback?**

Agent Teams have features headless workers don't: team messaging, shared task lists, persistent sessions. If your workflow needs those, Hook Mode gives you atomic execution within that architecture. The trade-off is more moving parts (counter files, poison sentinels, handoff archives).

**Why exit code 2 instead of SIGTERM?**

We explored `kill -TERM $PPID` from hooks — it works (confirmed: `$PPID` from a hook IS the Claude Code process) but it's messy. The parent Task tool sees an abnormal exit, state can corrupt if the handoff isn't fully flushed. PreToolUse exit 2 is the clean version: formally blocks all tools, agent starves deterministically, Task tool gets a normal return.

**Why not just `max_turns: 1`?**

One API turn can include multiple parallel tool calls. A single turn could do 3-4 things simultaneously, defeating the "one action" guarantee. The hook counter catches individual tool calls, not turns.

## License

MIT
