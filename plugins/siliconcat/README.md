# siliconcat

Silicon Cat Technologies' skills for Claude Code and Codex, in one plugin. Its skills show with the `siliconcat:` prefix, so their names never clash with another plugin's.

| Skill | What it does |
| --- | --- |
| [director](skills/director/README.md) | Turns a session into a 🎬 director: it splits each request into jobs for your project's roles, runs them as subagents, keeps one file per request, and shows what it is waiting on from you. |

The plugin also brings, in Claude Code, the director's band: a row above the prompt listing what the director is waiting on from you. It shows nothing outside a director project.

## Install

Claude Code:

```
/plugin install siliconcat --marketplace siliconcat/skills
```

Codex:

```
codex plugin marketplace add siliconcat/skills
codex plugin add siliconcat@siliconcat
```

Or one skill alone, without the band, into any agent [skills.sh](https://skills.sh) supports: `npx skills@latest add siliconcat/skills --skill <name>`. Pick one route per agent: both would give you every skill twice.

Start a new session after installing.

## Develop

From this folder:

```
skills/director/scripts/test.sh   # req, report-check, director-audit, link
claude plugin test .              # the band
claude plugin validate .          # the plugin
```
