# Silicon Cat AI plugins

Plugins for [Claude Code](https://claude.com/claude-code) and [Codex](https://developers.openai.com/codex), by Silicon Cat Technologies. MIT licensed.

| Plugin | What it does |
| --- | --- |
| [director](plugins/director) | Turns a session into a 🎬 director: it splits each request into jobs for your project's roles, runs them as subagents with the model and effort each job needs, keeps one file per request, and shows what it is waiting on from you. |

## Install

Claude Code:

```
/plugin marketplace add siliconcat/ai-plugins
/plugin install <plugin>@siliconcat-ai-plugins
```

Codex:

```
codex plugin marketplace add siliconcat/ai-plugins
codex plugin add <plugin>@siliconcat-ai-plugins
```

Start a new session after installing. Each plugin's README says how to use it.

## Develop

Each plugin lives in `plugins/<name>/`, with `.claude-plugin/plugin.json` for Claude Code and `.codex-plugin/plugin.json` for Codex, and is listed in both marketplace files: `.claude-plugin/marketplace.json` and `.agents/plugins/marketplace.json`. `claude plugin validate .` checks the marketplace.
