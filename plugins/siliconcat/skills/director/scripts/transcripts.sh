# Sourced by director-audit and director-retro: where Claude Code keeps session transcripts.
#   ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/<cwd, non-alphanumerics as ->/<session-id>.jsonl
#   subagents of a session: <project dir>/<session-id>/subagents/agent-*.jsonl

projects_root() { echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"; }

# project dir of a working directory
project_dir() { echo "$(projects_root)/$(printf '%s' "$1" | sed 's/[^A-Za-z0-9-]/-/g')"; }

# the nth newest session transcript of a working directory (1 = newest)
nth_session() { ls -t -- "$(project_dir "$1")"/*.jsonl 2>/dev/null | sed -n "${2:-1}p" || true; }

# transcript of a session id, in whichever project folder it ran (a --repo worker runs in another one)
session_file() {
  local f
  for f in "$(projects_root)"/*/"$1.jsonl"; do [[ -f $f ]] && { echo "$f"; return; }; done
  return 1
}

# transcripts of the subagents a session spawned
subagent_files() { ls -- "${1%.jsonl}"/subagents/agent-*.jsonl 2>/dev/null || true; }
