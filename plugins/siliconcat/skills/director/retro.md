# Retro

Read this when the user asks for a retro or a rules review, when a mission closes, or when `req lint` says `DIRECTOR.md` is over budget. A retro learns from what happened in sessions and proposes changes to the environment: role files, `DIRECTOR.md`, scripts, hooks, data access. Nothing changes until the user says yes.

## Scope

- Default: this session (`$CLAUDE_CODE_SESSION_ID`) and its workers: subagents, and Herdr workers (`director/workers.tsv`).
- A mission or a theme the user names: the sessions its requests ran in (`--mission NAME`, `--theme TEXT`).
- Everything since the last retro (`--since-last`), or since a date (`--since DATE`).

Record the retro as a request: `req new --retro` (add `--mission NAME` for a mission close) with the user's words. The last closed retro request marks "since last", so close it when the user has answered, with the changes made as its outcome.

## Method

1. Run `~/.local/share/director/bin/director-retro` with the scope. It prints a bounded digest per session: the user's messages (corrections live there), tool calls by name, failed calls, denials, Stop hook blocks, turns and wall time. Then the requests, rework, threads two requests share, the reports' `Next time:` lines and `req stats`. `director-retro --help` lists the flags.
2. Open a transcript only where the digest points: the path is in the digest. `grep` or `jq` for the moment, never read the whole file.
3. Classify candidates (below). A candidate needs evidence: the session and what happened there. A hunch with none is dropped.
4. Present at most five, most severe first. Each: the category, the change in one line, where it would live (a role file, `DIRECTOR.md`, a local script, the user's config, a team PR), and the evidence. Say what you would not change and why when the user is likely to ask.
5. Change only what the user accepts. Edit rules, don't append (`SKILL.md` section 7). In shared repos a change is a team PR, made only when the user asks.

For a deep dive on one session, `/mattpocock-skills:retro` reads it in full.

## Categories

- **Navigation**: the session took long to find a file or fact. A pointer in the role file or the repo's `AGENTS.md` fixes it.
- **Automated checks**: a mistake a linter, type check, test or hook would have caught. Read the repo's own check command and CI first: a check that exists but is unwired or broken is the finding. A repo with no check at all is one too.
- **Coding standards**: a reviewer or verifier missed something. A mechanical violation (a banned API, an import shape, a file location) gets a deterministic check; the reviewer's rules keep the judgement calls.
- **Steering size**: `CLAUDE.md`, `AGENTS.md`, `DIRECTOR.md` or a role file that is large. Move what is a standard to the reviewer, what is mechanical to a check.
- **Tool economy**: an expensive call (a huge read, a repeated query, a verbose tool) that a narrower one would replace.
- **No-ops**: a steering line that changes nothing in the transcripts. Drop it.
- **Information access**: a fact the worker lacked: logs, a test database, a browser, read access to a service.
- **Checker misses**: a verifier passed work that later failed (a user correction, red CI, a revert). The fix goes into that verifier's role file, and the case is replayed against it until it catches it. Tune the one verifier rather than adding reviewers.
- **Role file edits**: the user corrected the same thing twice, briefs to one role repeat the same background, or its `Next time:` lines repeat (`SKILL.md` section 7). The smallest edit to that role file.
- **A rule that should be a check**: a `DIRECTOR.md` rule a script or hook could enforce, or one the transcripts show was broken. The check goes in, the rule comes out.
- **Work that should have been a mission**: a second request on the same ticket or thread (the digest's shared threads). Propose the mission with its goal and constraints.

## Rules and roles review

Rules harden and start limiting the system. At a mission close, at a rules review and when `DIRECTOR.md` is over budget:

1. List every rule across `DIRECTOR.md` and the role files; propose which to drop, merge, or turn into a real check.
2. Review the roles with evidence: `director-audit` on the sessions, `req stats` for which roles needed rework, and `grep workers: director/requests/closed/*.md` for which were used. Propose which background to move into a role file, which role to split by area, and which unused roles can go.
3. Put these among the candidates; the limit of five holds.
