# Bootstrap, migration and templates

Read this when a project has no `DIRECTOR.md` or no roles, when `req lint` reports an old-style ledger, or when you check role files against the role template.

## Bootstrap a project

1. Ask the user, in one round: the mission (goal, how we know it worked), the constraints (cost, risk, what must not break), what needs their yes every time, and which repos and environments are in scope.
2. Look at the project just enough to propose roles: three to six, each with a clear responsibility, read-only unless it builds, a default model and an emoji. Include the default roles below that fit.
3. After the user says yes, write the role files and `DIRECTOR.md` from the templates below, run `req init`, then greet as in `SKILL.md` section 1.

A role carries knowledge, not just guardrails: where its area's code and docs live, how to build, test and release there, and the traps briefs would otherwise repeat. Split a role by area (repo, language, deploy path) when its jobs need different knowledge, never by task; one `builder` for a code repo and its deploy repo means every fresh worker relearns both.

### Default roles

- **verifier**, always: separate from whoever builds.
- **tracker** (haiku), when the project tracks work in Jira or similar: tickets, comments, transitions, and queue intake (`queue.md`).
- **budgeter** (sonnet, read-only), unless the project spends nothing (no cloud, paid APIs, model calls or licences): a gate that estimates the monthly cost change of a proposal or diff from the current bill and the provider's pricing, names what it assumed, and flags anything over the threshold the hard rules set as its trigger.
- **auditor** (opus, read-only), unless the project has no attack surface: a security gate for changes that touch auth, secrets, permissions (IAM, roles, policies), network exposure, personal data or new dependencies. It returns each finding with file:line, how it could be exploited and its severity, and works from code and read-only checks, never attacks on live systems.

## Migrate an old-style ledger

Migrate it once:

- open work becomes requests through `req new` (the user's words where the ledger has them);
- rules and standing approvals stay, deduplicated, with contradictions resolved by asking the user;
- lessons about a role move to its role file;
- findings the team needs go to their tickets;
- everything finished is dropped: git and the tickets keep it.

Show the user the new `DIRECTOR.md` and the list of moves before replacing the old one.

## Role file template

`.claude/agents/<name>.md`:

```markdown
---
name: <name>
description: <one line: what this role does and when the director uses it>
tools: <Read, Grep, Glob, Bash, mcp__savvy-progress__step ... — Edit/Write only for roles that build; Agent only for a manager or department director>
maxTurns: <a cap that a normal job of this role stays well under, so a stuck worker stops and returns partial work>
isolation: worktree          # builders working in this repo
hooks:                       # every role that writes a report
  Stop:
    - hooks:
        - type: command
          command: ~/.local/share/director/bin/report-check
        - type: command          # builders only: keeps an issue from being left claimed with no PR
          command: ~/.local/share/director/bin/issue-check
          timeout: 60
model: <haiku|sonnet|opus>
---

Emoji: <one emoji, unique among the project's roles; 🎬 is the director's>

<Who this role is, what it is responsible for, what it knows about its area, its guardrails,
and what its report contains.>

Rules:
- Write the full report to the file the brief names (or a scratchpad file; with a Bash heredoc if you have no Write tool, which a read-only role may still do) and reply with its path plus at most 15 lines.
- Report your plan as 3-8 steps with `mcp__savvy-progress__step` (`total`, `done: 0`) and update it as each step finishes.
- If the same error comes back three times, stop and report what you tried.
- End the report with "Next time:" and one line on what would have made this job faster (a missing fact, tool or access).
<builders and verifiers:>
- Work in your own git worktree, never in the shared checkout, and verify through the repo's own scripts. Verifiers: make it detached on the PR head in your scratchpad (`git worktree add --detach <dir> <sha>`) and remove it (`git worktree remove --force <dir>`) before you reply.
- Stage explicit paths (`git add <path>...`), so only your change goes in.
```

## `DIRECTOR.md` template

Under 100 lines:

```markdown
# Director

## Hard rules
- <rule> (<date>)
<gates and their triggers; what always needs the user's explicit yes>

## Standing approvals
- <what the director may do without asking> — scope: ... — until: <date or "the user revokes it"> (<date given>)

## Missions
- <name> (<ticket>): goal ... · done when ... · constraints ... · next: ...
```
