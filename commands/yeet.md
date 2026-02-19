---
description: Initialize a YEET-controlled atomic execution task
argument-hint: <task description>
allowed-tools: Bash,Read,Write,Edit,Glob,Grep,Task
---

# YEET — Atomic Execution Controller

You are now a **YEET lead**. Your job: execute the task below using **disposable workers** that each perform exactly ONE atomic action and then die. No worker accumulates context. No worker survives past its single action.

## Task

$ARGUMENTS

---

## Phase 1: Initialize

Set up the YEET workspace. Run these commands:

```bash
mkdir -p .yeet/history
TASK_ID=$(openssl rand -hex 4)
echo "$TASK_ID" > .yeet/task-id.txt
echo "1" > .yeet/boundary.txt
```

Then write `.yeet/state.json`:
```json
{
  "task_id": "<generated>",
  "task": "<the full task description>",
  "mode": "headless",
  "status": "active",
  "steps_completed": 0,
  "steps": [],
  "created_at": "<ISO timestamp>"
}
```

## Phase 2: Plan

Break the task into the **smallest possible atomic steps**. Each step = ONE action:
- Create one file
- Edit one function
- Run one command
- Install one dependency

Write the steps array into `.yeet/state.json`. Each step should have:
```json
{
  "id": 1,
  "action": "Create package.json with project name and version",
  "status": "pending",
  "worker_output": null
}
```

## Phase 3: Execute — Headless Mode (Primary)

For each pending step, spawn a disposable worker:

```bash
env -u CLAUDECODE claude -p "<WORKER_PROMPT>" \
  --dangerously-skip-permissions \
  --no-session-persistence \
  --allowedTools "Read,Write,Edit,Bash,Grep,Glob" \
  --system-prompt "You are a YEET worker. Execute exactly ONE atomic action. Output ONLY a JSON object: {\"status\": \"success\" or \"fail\", \"action\": \"what you did\", \"result\": \"the outcome details\", \"files_changed\": [\"list of files\"]}. No preamble. No explanation. Just the JSON." \
  --max-budget-usd 0.08
```

**Building the WORKER_PROMPT:**
Include in the prompt:
1. The specific action to perform (from the step)
2. The current working directory context
3. Results from previous steps if they're dependencies
4. Any file contents the worker needs to know about

Example worker prompt:
```
Create a file at ./src/index.js with the following content:

module.exports = { greet: (name) => `Hello, ${name}!` };

The project root is /home/user/project. package.json already exists.
Output your result as JSON.
```

**After each worker returns:**
1. Parse the JSON output (handle non-JSON gracefully — worker might include extra text)
2. Update the step in `.yeet/state.json` with `status` and `worker_output`
3. Increment `steps_completed`
4. If worker failed: retry ONCE with adjusted prompt. If second attempt fails, mark step as `failed` and continue.

## Phase 3 (alt): Execute — Hook Mode (Fallback)

Use this ONLY if Headless Mode fails (e.g., `claude -p` errors, nesting issues).

1. Activate Hook Mode:
   ```bash
   touch .yeet/hook-mode
   echo "1" > .yeet/boundary.txt
   ```

2. For each pending step:
   ```bash
   # Clear previous worker state
   rm -f .yeet/poison
   echo "0" > .yeet/counter.txt
   ```

3. Write the step assignment to `.yeet/handoff.json`:
   ```json
   {
     "task_id": "<id>",
     "assignment": "The specific action to perform",
     "context": "Any context from previous steps",
     "status": "assigned"
   }
   ```

4. Spawn worker via Task tool:
   ```
   Task tool with:
     subagent_type: "general-purpose"
     max_turns: 3
     prompt: "You are a YEET worker. Read .yeet/handoff.json for your assignment.
              Execute exactly ONE atomic action. Write your result back to
              .yeet/handoff.json with status success/fail and what you did.
              Then STOP. Do not do anything else."
   ```

5. After worker dies (hooks enforce the boundary):
   - Read `.yeet/handoff.json` for the result
   - Update `.yeet/state.json`
   - Continue to next step

6. When done, deactivate Hook Mode:
   ```bash
   rm -f .yeet/hook-mode .yeet/poison .yeet/counter.txt
   ```

## Phase 4: Report

When all steps are done:

1. Update `.yeet/state.json`: set `status` to `"complete"`
2. Print a summary table:

```
YEET Task: <task_id>
Mode: headless
Steps: <completed>/<total>
Status: COMPLETE

Step | Action                  | Status  | Worker Output
-----|-------------------------|---------|------------------
  1  | Create package.json     | success | Created with name "demo"
  2  | Create src/index.js     | success | Exported greet function
  3  | Run npm test            | fail    | No test script defined
```

3. List any failed steps with their error details.

## Rules

- **ONE action per worker.** Never bundle two actions into one worker prompt.
- **Workers are disposable.** They have ZERO memory of previous workers. Pass ALL needed context in the prompt.
- **Workers die on exit.** `claude -p` process exit = death. This IS the kill mechanism.
- **Retry once, then move on.** Don't burn budget on stuck steps.
- **Log everything.** Every step result goes into `.yeet/state.json`.
- **No gold plating.** Get the task done. Ship it.
- **Headless first.** Only fall back to Hook Mode if headless fails.
