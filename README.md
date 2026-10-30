# Silicon Cat skills

Skills for [Claude Code](https://claude.com/claude-code), [Codex](https://developers.openai.com/codex) and other agents, by Silicon Cat Technologies. MIT licensed.

| Skill | What it does |
| --- | --- |
| [director](plugins/siliconcat/skills/director/README.md) | Turns a session into a 🎬 director: it splits each request into jobs for your project's roles, runs them as subagents with the model and effort each job needs, keeps one file per request, and shows what it is waiting on from you. |

## Install

All the skills, as the [`siliconcat` plugin](plugins/siliconcat/README.md) (they show as `siliconcat:<skill>`, and the plugin adds the director's band in Claude Code):

```
/plugin install siliconcat --marketplace siliconcat/skills     # Claude Code
codex plugin marketplace add siliconcat/skills                 # Codex
codex plugin add siliconcat@siliconcat
```

Or the skills you pick, through [skills.sh](https://skills.sh), into any agent it supports:

```
npx skills@latest add siliconcat/skills
```

Pick one route per agent: both would give you every skill twice. Start a new session after installing.

## Develop

The plugin lives in `plugins/siliconcat/`, with `.claude-plugin/plugin.json` for Claude Code and `.codex-plugin/plugin.json` for Codex, listed in both marketplace files: `.claude-plugin/marketplace.json` and `.agents/plugins/marketplace.json`. Each skill is a folder in `plugins/siliconcat/skills/`. `claude plugin validate .` checks the marketplace.
