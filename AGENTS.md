# Working in this repo

Every commit that changes anything under `plugins/` bumps the version, or `claude plugin update` keeps the installed copy as it was. The version appears four times and they stay equal: `.claude-plugin/marketplace.json` (twice), `plugins/siliconcat/.claude-plugin/plugin.json` and `plugins/siliconcat/.codex-plugin/plugin.json`. Bump the patch for fixes and wording, the minor for new behaviour.

```bash
V=<new version> perl -pi -e 's/"version": "[^"]+"/"version": "$ENV{V}"/' .claude-plugin/marketplace.json plugins/siliconcat/.claude-plugin/plugin.json plugins/siliconcat/.codex-plugin/plugin.json
```
