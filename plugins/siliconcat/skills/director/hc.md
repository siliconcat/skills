# Running workers as Herdr terminals

Read this first when `scripts/link` prints a line starting `Herdr`. Workers can then run as terminals the user watches, and subagents don't show there. Say in the greeting that workers run in Herdr, and spawn subagents for the rest of the session if the user asks for them. Where this file and `SKILL.md` disagree, this file wins. Two backends, and `hc-worker` picks the one this session is in:

- **App** (`hc`): `HC_TERMINAL_ID` is set and `hc` is on the PATH. This session runs in a terminal of the Herdr app; workers are background terminals, each a child of yours.
- **Server** (`herdr`): `HERDR_ENV=1` and `HERDR_PANE_ID` are set and `herdr` is on the PATH. This session runs in a pane of the standalone `herdr` server; each worker gets a tab of its own in your workspace, opened without taking focus, and is a named agent there. `HC_TERMINAL_ID` wins when both are set.

Below, commands differ per backend where marked App or Server; `herdr` commands print JSON, and `herdr agent` takes the worker's name.

## Spawn

`~/.local/share/director/bin/hc-worker <name> <role> <model> <effort> [-- <claude args>...]`, with the brief on stdin, run from the project root. It starts `claude --agent <role>` in a terminal named `<name>` (a tab of that name on the server), so the role file loads with its `tools:`, `model` and Stop hooks, and the model and effort are the ones section 4 picks for the job. Names follow section 3; on the server they are also lowercase letters, digits, `-` and `_`, at most 32, and `hc-worker` refuses any other.

Write the brief to a file and pipe it in (`hc-worker builder-nat-keepalive builder sonnet medium < brief.md`), so quotes in it survive.

`hc-worker` starts claude with a session id of its own and appends one line per worker to `director/workers.tsv` in this project (time, name, role, cwd, worker session id, terminal (hc id, or herdr pane id), this session's id), so `director-retro` finds the worker's transcript later, even for a `--repo` worker whose transcript sits in another project folder.

### Roles from another repo

A job in another repo may have a better role there than any of yours: list that repo's `.claude/agents/` before you staff it. To use one, add `--repo <dir>` (`hc-worker --repo ../nerea builder-infra-dns infra-builder sonnet medium < brief.md`): the worker starts in that repo with its role, `CLAUDE.md` and settings, which a subagent can't have. Same name, different role: a `builder` there is that repo's builder, not yours. The brief names the report as an absolute path under this project's `director/reports/`, and `hc-worker` refuses a brief that doesn't, since a relative path would land in the other repo. The requests stay here: run `req` from this project only.

## Not getting blocked

A worker that stops at a prompt waits for the user, and only the user may answer a trust, permission or approval prompt. Prevent them:

- **Folder trust.** `hc-worker` refuses (exit 2) a folder Claude Code has not trusted, or a parent of one. Ask the user to open Claude in that folder once and trust it, or spawn a subagent there.
- **Permission mode.** A worker starts in the default mode of the user's settings. When this session runs in a different mode, pass it on: `-- --permission-mode <mode>`. Never a looser one than yours, and never `bypassPermissions` unless the user says so for that worker.
- **Role files.** They are excluded from git, so a worktree doesn't have them: always spawn from the project root, and builders make their own worktree, as the role template says (`isolation: worktree` applies only to subagents).
- **Other startup prompts.** A new MCP server in the project's `.mcp.json` asks for approval the first time Claude starts there. Workers start where the user already runs Claude, so expect it only after `.mcp.json` changes.

If a worker is blocked anyway, hc types a line into this session (`<hc>t13 probe-tools is blocked (permission). See: hc read t13`); it arrives like a user message but isn't one. The server sends nothing: `herdr agent wait` returns with status `blocked`. Read the worker's screen with `hc read <name>` or `herdr agent read <name> --source recent-unwrapped --lines 60`, tell the user which terminal waits and for what, and record it with `req ask`. Never answer the prompt with `hc keys`, `hc send` or `herdr agent send-keys`.

## While it runs

- **App.** After spawning, run `hc wait --children any --timeout 3600` as a background command, so you are woken when a worker ends a turn, blocks, errors or exits; then `hc ls` says which one, and you start the next wait. Not `hc wait <name>`: it returns at the worker's startup idle, before it has read the brief. `hc ls` lists workers and their state (`working`, `blocked`, `done`); `ListAgents` doesn't show them. It lists every live terminal, so other directors' workers show too: a worker is yours when its parent is your terminal (`$HC_TERMINAL_ID`), and a worker whose parent is another terminal belongs to another director. Never wait on, send to, kill or retire those.
- **Server.** After spawning, run `herdr agent wait <name> --timeout 3600000` as a background command, one per worker (there is no wait on any). It returns when the worker ends a turn (`done`), blocks (`blocked`) or goes idle; `.result.agent.agent_status` in the answer says which. `hc-worker` already waited for the worker to start, so this wait doesn't return at startup. `herdr agent list` shows every agent on the server, other directors' included: yours are the names in `director/workers.tsv` whose last column is this session's id (`$CLAUDE_CODE_SESSION_ID`). Never wait on, send to, close or retire the others.
- The report arrives as a file: the role's `report-check` Stop hook holds the worker to a reply of at most 15 lines that names the report, as for subagents. Read the report; `hc read` or `herdr agent read` is only for a worker that is blocked or stuck.
- Reuse for the **same thread**: the worker is still alive with its context, so give it the next job with `hc send <name> "<brief>"` (server: `herdr agent prompt <name> -- "<brief>"`, then `herdr agent wait <name> --until working --until blocked --timeout 30000` before the long wait) once it is `done`. The three-job limit and the cache note in section 4 still apply.
- Workers spawn nobody, not even through `hc run`: a worker that needs help returns a staffing request.

## Retire

`hc kill <name>` (server: `herdr pane close <pane id>`, the id in `workers.tsv` or in `hc-worker`'s output; it removes the worker's tab), then `req worker R-NNNN --retire <name>`. Workers end when this session's `claude` exits (app) or when you close them (server), but not on `/clear` or `/compact`: retire the ones whose threads ended before resetting.

## What else changes

- **`director-audit`** reads this session's subagent transcripts, so it doesn't see Herdr workers: skip section 1 step 5 for them. `director-retro` does read them, through `director/workers.tsv`.
- **Section 1 step 4**: a worker an open request lists as live is live if `hc ls` (server: `herdr agent list`, yours only) shows it, not `ListAgents`; only workers of requests this session owns are retired.
