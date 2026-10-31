# director

A 🎬 director for Claude Code and Codex. It splits each request into jobs for your project's roles, runs them as subagents with the model and effort each job needs, keeps one file per request, and shows what it is waiting on from you.

## Install

It comes with the `siliconcat` plugin, which also brings the band:

```
/plugin install siliconcat --marketplace siliconcat/skills     # Claude Code
codex plugin marketplace add siliconcat/skills                 # Codex
codex plugin add siliconcat@siliconcat
```

Or the skill alone, without the band, into any agent [skills.sh](https://skills.sh) supports:

```
npx skills@latest add siliconcat/skills --skill director
```

Start a new session after installing.

## Use

Start it in a project with `/siliconcat:director` in Claude Code (`/director` when installed alone), or by asking for the `director` skill in Codex, optionally followed by a request. On a project it hasn't seen, it asks you about the mission and constraints, proposes a handful of roles (a builder, a verifier, a tracker for tickets, cost and security gates), and writes them to the project once you agree. From then on you talk to the director; it briefs the workers, checks their evidence, and keeps you posted.

What it keeps in the project, all excluded from git through `.git/info/exclude`:

- `DIRECTOR.md`: hard rules, standing approvals and missions.
- `director/requests/`: one file per request, with your exact words, the workers, links to PRs, runs and tickets, and what it is waiting on from you.
- `director/reports/`: each worker's full report.
- Role files in `.claude/agents/` (Claude Code) or `.codex/agents/` (Codex).

## What comes with it

- `req`, the script that keeps the request files (`req help`), `report-check`, a stop hook that holds workers to a short reply plus a report file, and `issue-check`, a stop hook that keeps a build worker from leaving its issue assigned and `ready-for-agent` with no open PR. The director links them at `~/.local/share/director/bin` on each start, so role files and hooks keep working across upgrades.
- With the `siliconcat` plugin in Claude Code, a band above the prompt listing what the director is waiting on from you, with each request and how long it has waited.
- `director-audit` (Claude Code), which reports how a session spawned and reused its workers.

Claude Code and Codex differ in what a role can carry; [codex.md](codex.md) lists what Codex lacks (per-role tool lists, turn caps, worktree isolation, the band) and what stands in for it.

Optional: with [savvy-progress](https://github.com/johnnyvizz/claude-kit) installed, Claude Code workers report their steps as a progress bar. Agent teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`) should stay off: the director's workers are subagents.

Needs `bash`, `git`, `jq` and `perl`; `gh` and a `~/.netrc` for Jira let `req check` read the live state of PRs, CI runs and tickets.

## Develop

From this folder: `scripts/test.sh` tests `req`, `report-check`, `issue-check`, `director-audit` and `link`. The band is tested with the plugin: see its [README](../../README.md).
