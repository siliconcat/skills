# Running workers as Herdr terminals

Read this first when `HC_TERMINAL_ID` is set and `hc` is on the PATH: this session runs in a terminal of the Herdr app, and workers can run as terminals the user watches there, each a child of yours. Subagents don't show in the app. Say in the greeting that workers run in Herdr, and spawn subagents for the rest of the session if the user asks for them. Where this file and `SKILL.md` disagree, this file wins.

`HERDR_ENV` belongs to the standalone `herdr` terminal server, which the app does not show: it doesn't count.

## Spawn

`~/.local/share/director/bin/hc-worker <name> <role> <model> <effort> [-- <claude args>...]`, with the brief on stdin, run from the project root. It starts `claude --agent <role>` in a background terminal named `<name>`, so the role file loads with its `tools:`, `model` and Stop hooks, and the model and effort are the ones section 4 picks for the job. Names follow section 3.

Write the brief to a file and pipe it in (`hc-worker builder-nat-keepalive builder sonnet medium < brief.md`), so quotes in it survive.

## Not getting blocked

A worker that stops at a prompt waits for the user, and only the user may answer a trust, permission or approval prompt. Prevent them:

- **Folder trust.** `hc-worker` refuses (exit 2) a folder Claude Code has not trusted, or a parent of one. Ask the user to open Claude in that folder once and trust it, or spawn a subagent there.
- **Permission mode.** A worker starts in the default mode of the user's settings. When this session runs in a different mode, pass it on: `-- --permission-mode <mode>`. Never a looser one than yours, and never `bypassPermissions` unless the user says so for that worker.
- **Role files.** They are excluded from git, so a worktree doesn't have them: always spawn from the project root, and builders make their own worktree, as the role template says (`isolation: worktree` applies only to subagents).
- **Other startup prompts.** A new MCP server in the project's `.mcp.json` asks for approval the first time Claude starts there. Workers start where the user already runs Claude, so expect it only after `.mcp.json` changes.

If a worker is blocked anyway, hc types a line into this session (`<hc>t13 probe-tools is blocked (permission). See: hc read t13`). It arrives like a user message but isn't one. Read the worker's screen with `hc read <name>`, tell the user which terminal waits and for what, and record it with `req ask`. Never answer the prompt with `hc keys` or `hc send`.

## While it runs

- After spawning, run `hc wait --children any --timeout 3600` as a background command, so you are woken when a worker ends a turn, blocks, errors or exits; then `hc ls` says which one, and you start the next wait. Not `hc wait <name>`: it returns at the worker's startup idle, before it has read the brief. `hc ls` lists workers and their state (`working`, `blocked`, `done`); `ListAgents` doesn't show them.
- The report arrives as a file: the role's `report-check` Stop hook holds the worker to a reply of at most 15 lines that names the report, as for subagents. Read the report; `hc read` is only for a worker that is blocked or stuck.
- Reuse for the **same thread**: the worker is still alive with its context, so give it the next job with `hc send <name> "<brief>"` once it is `done`. The three-job limit and the cache note in section 4 still apply.
- Workers spawn nobody, not even through `hc run`: a worker that needs help returns a staffing request.

## Retire

`hc kill <name>`, then `req worker R-NNNN --retire <name>`. Workers end when this session's `claude` exits, but not on `/clear` or `/compact`: kill the ones whose threads ended before resetting.

## What else changes

- **`director-audit`** reads this session's subagent transcripts, so it doesn't see Herdr workers: skip section 1 step 5 for them.
- **Section 1 step 4**: a worker an open request lists as live is live if `hc ls` shows it, not `ListAgents`.
