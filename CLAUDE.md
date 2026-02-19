# CLAUDE.md — YEET Plugin

> Forced single-action atomic execution for Claude Code

## What This Is

A Claude Code plugin that kills subagents after exactly one atomic task and respawns them fresh. Two modes: Headless (`claude -p` workers) and Hook Mode (PreToolUse blocking).

## Project Layout

```
yeet/
├── .claude-plugin/plugin.json    # Plugin manifest
├── hooks/
│   ├── hooks.json                # Hook event declarations
│   ├── post-tool-use.sh          # Counter + handoff + poison (Hook Mode)
│   ├── pre-tool-use.sh           # Poison check + block (Hook Mode)
│   └── session-start.sh          # Handoff injection (Hook Mode)
├── commands/
│   └── yeet.md                   # /yeet slash command (lead orchestration)
├── CLAUDE.md                     # This file
└── README.md                     # Full documentation
```

## On Session Start

1. Read this file
2. Read `README.md` for architecture context
3. Check `commands/yeet.md` for the orchestration logic

## Status

v0.1.0 — POC. Both modes implemented, not yet battle-tested.

## Parked Work

- Demo script that proves the mechanic end-to-end
- Plugin marketplace publishing
- SIGTERM kill mode (explored, deferred — see README architecture decisions)

## Update Recipients

