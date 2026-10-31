# Running the director in Codex

Read this first when you run in Codex. `SKILL.md` is written in Claude Code's terms; this file maps them and says what Codex lacks. Where the two disagree, this file wins.

## Roles

A role is a custom agent: one TOML file per role in the project's `.codex/agents/` (a role file in Claude Code is `.claude/agents/<name>.md`). Write roles from the template in `bootstrap.md`, translated:

```toml
name = "verifier"
description = "<one line: what this role does and when the director uses it>"
model_reasoning_effort = "medium"   # low | medium | high, the default for this role
# model = "<a model id>"            # only to pin one; otherwise the session's default
developer_instructions = """
Emoji: ✅
<the role's body and the template's Rules, as in bootstrap.md>
"""
```

What a Codex role cannot carry, and what stands in for it:

- **No `tools:` list.** Every subagent inherits the session's sandbox and approvals. A read-only role says so in its instructions ("read-only: no edits, no writes to any system"), and the verifier checks it was respected.
- **No `maxTurns`.** The three-identical-failures rule in the template is the only stop; watch long runs in your status lines.
- **No `isolation: worktree`.** Every role that touches git makes its own worktree, as the template's builder and verifier rules say.
- **No per-role hooks.** The report check goes in the project's `.codex/hooks.json` (below).

## Workers

- Spawn a worker by asking for a subagent of the role's agent type, with your brief as its task. Name it in `req` as `SKILL.md` section 3 says (`builder-nat-keepalive`); Codex's own thread name doesn't matter.
- Subagents run in parallel up to `agents.max_concurrent_threads_per_session`; keep to the cap of four anyway.
- The **same thread** reuse in `SKILL.md` applies only while the worker is still running: steer it with the next step. Once a Codex subagent has finished, the next job goes to a fresh worker, briefed with pointers to the finished one's report.
- Retiring is closing its thread, then `req worker R-NNNN --retire <name>`.
- Model and effort per job: section 4's table, read as cheapest, default and strongest model for the first three rows and the strongest with high effort for the last. Effort maps to `model_reasoning_effort`.

## The report check

Codex's `SubagentStop` hook passes the same fields as Claude Code's (`last_assistant_message`, `stop_hook_active`, `cwd`), so `report-check` works unchanged; `issue-check` and `skill-check` read the transcript path the same way and can be listed for builder roles in the same way. When you write the roles, add to the project's `.codex/hooks.json`, listing the roles that write a report:

```json
{
  "hooks": {
    "SubagentStop": [
      {
        "matcher": "^(builder|verifier)$",
        "hooks": [{ "type": "command", "command": "~/.local/share/director/bin/report-check" }]
      }
    ]
  }
}
```

Project hooks run only once the user trusts the project's `.codex/` layer: say so when you propose it.

## What Codex has no equivalent for

- **The band.** When `req asks` lists anything, start each status message with it ("Waiting on you: R-0005 · approve merging #96"), so the user always sees what you need from them.
- **Agent teams** and `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`: ignore those lines.
- **savvy-progress:** workers skip the progress-steps rule.
- **`director-audit`** reads Claude Code transcripts: skip `SKILL.md` section 1 step 5, and its use at mission close.
- **`req lint`'s role checks and `req prune`** look at `.claude/agents/` and `.claude/worktrees/`: in Codex, check role files against the template yourself, and remove worktrees your workers left once their PRs are pushed.
