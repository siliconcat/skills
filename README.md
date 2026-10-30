# Silicon Cat AI plugins

Plugins for [Claude Code](https://claude.com/claude-code) and [Codex](https://developers.openai.com/codex), by Silicon Cat Technologies. MIT licensed.

| Plugin | What it does |
| --- | --- |
| [director](plugins/director) | Turns a session into a 🎬 director: it splits each request into jobs for your project's roles, runs them as subagents with the model and effort each job needs, keeps one file per request, and shows what it is waiting on from you. |

## Install

Claude Code:

```
/plugin marketplace add siliconcat/ai-plugins
/plugin install director@siliconcat-ai-plugins
```

Codex:

```
codex plugin marketplace add siliconcat/ai-plugins
codex plugin add director@siliconcat-ai-plugins
```

Start a new session after installing.

## director

Start it in a project with `/director:director` in Claude Code, or by asking for the `director` skill in Codex, optionally followed by a request. On a project it hasn't seen, it asks you about the mission and constraints, proposes a handful of roles (a builder, a verifier, a tracker for tickets, cost and security gates), and writes them to the project once you agree. From then on you talk to the director; it briefs the workers, checks their evidence, and keeps you posted.

What it keeps in the project, all excluded from git through `.git/info/exclude`:

- `DIRECTOR.md`: hard rules, standing approvals and missions.
- `director/requests/`: one file per request, with your exact words, the workers, links to PRs, runs and tickets, and what it is waiting on from you.
- `director/reports/`: each worker's full report.
- Role files in `.claude/agents/` (Claude Code) or `.codex/agents/` (Codex).

What comes with it:

- `req`, the script that keeps the request files (`req help`), and `report-check`, a stop hook that holds workers to a short reply plus a report file. The director links them at `~/.local/share/director/bin` on each start, so role files and hooks keep working across upgrades.
- In Claude Code, a band above the prompt listing what the director is waiting on from you, with each request and how long it has waited.
- `director-audit` (Claude Code), which reports how a session spawned and reused its workers.

Claude Code and Codex differ in what a role can carry; [codex.md](plugins/director/skills/director/codex.md) lists what Codex lacks (per-role tool lists, turn caps, worktree isolation, the band) and what stands in for it.

Optional: with [savvy-progress](https://github.com/johnnyvizz/claude-kit) installed, Claude Code workers report their steps as a progress bar. Agent teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`) should stay off: the director's workers are subagents.

Needs `bash`, `git`, `jq` and `perl`; `gh` and a `~/.netrc` for Jira let `req check` read the live state of PRs, CI runs and tickets.

## Develop

```
plugins/director/skills/director/scripts/test.sh   # req, report-check, director-audit, link
claude plugin test plugins/director                # the band
claude plugin validate .                           # the marketplace
```
