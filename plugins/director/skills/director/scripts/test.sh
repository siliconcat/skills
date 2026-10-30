#!/usr/bin/env bash
# Self-test for req and director-audit, in a throwaway git repo.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d); trap 'rm -rf "${T:?}"' EXIT
cd "$T"; git init -q .
req() { "$HERE/req" "$@"; }
fail() { echo "FAIL: $*"; exit 1; }
has() { grep -qF -- "$2" "$1" || fail "$1 lacks: $2"; }

mkdir -p .claude/agents
printf -- '---\nname: builder\n---\n\nEmoji: 🔨\n' > .claude/agents/builder.md
printf -- '---\nname: verifier\n---\n\nEmoji: 🔨\n' > .claude/agents/verifier.md
printf '# Director\n' > DIRECTOR.md
mkdir -p .codex/agents
printf 'name = "verifier"\n' > .codex/agents/verifier.toml
printf '{ "hooks": {} }\n' > .codex/hooks.json

req init > /dev/null
git check-ignore -q DIRECTOR.md || fail "DIRECTOR.md not excluded"
git check-ignore -q .claude/agents/builder.md || fail "role file not excluded"
git check-ignore -q .codex/agents/verifier.toml || fail "Codex role file not excluded"
git check-ignore -q .codex/hooks.json || fail "Codex hooks not excluded"
[[ $(git status --porcelain) == "" ]] || fail "init left untracked files: $(git status --porcelain)"
req init > /dev/null
[[ $(grep -c '^/DIRECTOR.md$' .git/info/exclude) == 1 ]] || fail "init not idempotent"

id=$(printf 'Create a card for the "lang" bug & link $HOME\nsecond line' | req new --mission names)
[[ $id == R-0001 ]] || fail "first id was $id"
f=director/requests/open/R-0001.md
has "$f" 'Create a card for the "lang" bug & link $HOME'
has "$f" 'mission: names'
[[ $(echo two | req new) == R-0002 ]] || fail "second id"

printf 'also PT\nand ES' | req add R-0001 > /dev/null
has "$f" "- $(date +%F): also PT"
has "$f" '  and ES'
req worker R-0001 tracker builder > /dev/null
req worker R-0001 tracker > /dev/null
has "$f" 'workers: [tracker, builder]'
req receipt R-0001 https://example.com/a https://example.com/a > /dev/null
[[ $(grep -c '^- https://example.com/a$' "$f") == 1 ]] || fail "receipt duplicated"
awk '/^## Receipts$/{r=1} END{exit !r}' "$f" || fail "receipts section lost"

req status R-0001 in-flight > /dev/null
has "$f" 'status: in-flight'
out=$(req status R-0001 done "x" 2>&1 || true)
grep -q "live workers: tracker builder" <<< "$out" || fail "done with live workers accepted: $out"
[[ -f $f ]] || fail "refused close still moved the request"
req worker R-0001 --retire nobody 2>/dev/null && fail "retired a non-worker"
req worker R-0002 builder > /dev/null
req worker R-0001 --retire tracker builder | grep -q 'builder is still live on R-0002' || fail "retire missed builder live elsewhere"
has "$f" 'retired: [tracker, builder]'
# requests written before retired: existed get the key added
perl -ni -e 'print unless /^retired:/' director/requests/open/R-0002.md
req worker R-0002 --retire builder > /dev/null
has director/requests/open/R-0002.md 'retired: [builder]'
req status R-0001 done "Card PROJ-1 created" > /dev/null
[[ -f director/requests/closed/R-0001.md && ! -f $f ]] || fail "done did not move to closed"
has director/requests/closed/R-0001.md "$(date +%F): Card PROJ-1 created"
req status R-0001 open > /dev/null
[[ -f $f ]] || fail "reopen did not move back"
req status R-0001 bogus 2>/dev/null && fail "bad status accepted"
echo x | req add R-9999 2>/dev/null && fail "missing id accepted"
req new < /dev/null 2>/dev/null && fail "empty request accepted"

[[ $(req open | wc -l) -eq 2 ]] || fail "open should list 2"
req check R-0001 | grep -q 'not checked' || fail "check of plain url"

out=$(req lint || true)
grep -q 'shares 🔨' <<< "$out" || fail "lint missed duplicate emoji: $out"
grep -q 'builder.md has no model:' <<< "$out" || fail "lint missed missing model: $out"
grep -q 'builder.md has no tools: line' <<< "$out" || fail "lint missed missing tools: $out"
printf -- '---\nname: builder\nmodel: haiku\ntools: Read, Bash, Agent\n---\n\nEmoji: 🔨\n' > .claude/agents/builder.md
out=$(req lint || true)
grep -q 'builder.md has no model:' <<< "$out" && fail "lint flagged a role that has model: $out"
grep -q 'builder.md has no tools:' <<< "$out" && fail "lint flagged a role that has tools: $out"
grep -q 'note: builder.md can spawn' <<< "$out" || fail "lint missed Agent in tools: $out"
grep -q "builder.md has no maxTurns:" <<< "$out" || fail "lint missed maxTurns: $out"
grep -q "builder.md has no report-check" <<< "$out" || fail "lint missed report hook: $out"
printf -- "---\nname: builder\nmodel: haiku\ntools: Read, mcp__savvy-progress__step\nmaxTurns: 80\nhooks:\n  Stop:\n    - hooks:\n        - type: command\n          command: report-check\n---\n\nEmoji: 🔨\n- End the report with \"Next time:\" and one line.\n" > .claude/agents/builder.md
out=$(req lint || true)
grep "builder.md" <<< "$out" | grep -qv "shares" && fail "lint flagged a role that matches the template: $out"
for i in $(seq 1 101); do echo "line" >> DIRECTOR.md; done
if req lint > /dev/null; then fail "lint should exit non-zero on warnings"; fi
out=$(req lint || true)
grep -q 'budget 100' <<< "$out" || fail "lint missed ledger size: $out"

grep -q 'live workers' <<< "$out" && fail "lint flagged live workers too early: $out"
id=$(echo forced | req new); req worker "$id" builder > /dev/null
req status "$id" done --force "closed anyway" > /dev/null || fail "--force did not close"
has "director/requests/closed/$id.md" "$(date +%F): closed anyway"
printf -- '---\nid: R-0098\nstatus: done\nworkers: [old]\n---\n' > director/requests/closed/R-0098.md
id2=$(echo stale | req new); req worker "$id2" investigator > /dev/null
touch -t 202601010000 "director/requests/open/$id2.md"
out=$(req lint || true)
grep -q "$id is closed with live workers: builder" <<< "$out" || fail "lint missed forced close: $out"
grep -q 'R-0098' <<< "$out" && fail "lint flagged a pre-retirement closed request: $out"
grep -q "$id2 untouched for over a day with live workers: investigator" <<< "$out" || fail "lint missed stale live workers: $out"

req rework "$id" builder-2 "verify failed: missing test" > /dev/null
req rework "$id" builder "user: wrong branch" > /dev/null
req rework "$id" builder-nat-keepalive "verify failed" > /dev/null
has "director/requests/closed/$id.md" "rework (builder-2): verify failed: missing test"
out=$(req stats)
grep -q 'without rework: [0-9]*, rework rounds: 3' <<< "$out" || fail "stats totals: $out"
grep -qE '^  builder +3$' <<< "$out" || fail "stats by role: $out"

# asks: what the director waits on from the user
aid=$(echo "asks test - [ ] not an ask" | req new)
req ask "$aid" "approve merging #96" > /dev/null
out=$(req asks)
grep -qE "^$aid	[0-9T:Z-]+	approve merging #96\$" <<< "$out" || fail "asks output: $out"
perl -pi -e 's/^- \[ \] \d{4}-\S+/- [ ] 2020-01-01T00:00Z:/' "director/requests/open/$aid.md"
out=$(req lint 2>/dev/null || true)
grep -q "$aid has waited on the user since 2020-01-01T00:00Z: approve merging #96" <<< "$out" || fail "lint missed an old ask: $out"
req ask "$aid" --done > /dev/null
[[ -z $(req asks) ]] || fail "ask still open after --done"
req ask "$aid" "second ask" > /dev/null
req status "$aid" dropped "test" > /dev/null
[[ -z $(req asks) ]] || fail "closing left an ask open"
grep -q "^asks test - \[ \] not an ask\$" "director/requests/closed/$aid.md" || fail "closing touched request text"

[[ ! -d director/requests/.lock ]] || fail "lock left behind"

# report-check stop hook
rc() { jq -n --arg m "$1" --arg c "$T" --argjson a "${2:-false}" '{last_assistant_message: $m, cwd: $c, stop_hook_active: $a}' | "$HERE/report-check"; }
mkdir -p director/reports; echo report > director/reports/R-0001-builder.md
[[ -z $(rc $'Done.\nFull report: director/reports/R-0001-builder.md') ]] || fail "report-check blocked a good reply"
rc 'Done, all good.' | grep -q '"block"' || fail "report-check let a reply without a report file through"
rc "$(printf 'line %s\n' $(seq 1 20); echo director/reports/R-0001-builder.md)" | grep -q 'is 21 lines' || fail "report-check let a long reply through"
mkdir -p dags; echo x > dags/a_dag.py
out=$(rc "$(printf 'line %s\n' $(seq 1 20); echo 'deleted dags/a_dag.py'; echo director/reports/R-0001-builder.md)")
grep -q 'in director/reports/R-0001-builder.md' <<< "$out" || fail "report-check named a source file as the report: $out"
rc "$(printf 'line %s\n' $(seq 1 20); echo 'deleted dags/a_dag.py')" | grep -q 'a_dag.py' && fail "report-check called a source file the report"
[[ -z $(rc 'Done, all good.' true) ]] || fail "report-check blocked twice in a row"
[[ -z $(echo '{}' | "$HERE/report-check") ]] || fail "report-check blocked on missing input"

# director-audit on a synthetic transcript
cat > s.jsonl <<'EOF'
{"type":"user","cwd":"CWD","message":{"content":"hi"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":"general-purpose","name":"gdpr-card","description":"Create card"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":"builder","name":"builder","description":"Build A"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"SendMessage","input":{"to":"builder","message":"next step"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":"builder","name":"builder","description":"Build B"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":"builder","description":"Build C"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":"builder","name":"builder-nat-keepalive","description":"Build D"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":"verifier","name":"verifier","description":"V1","prompt":"R-0001: check `deploy/prod/values.yaml` and `Emoji: 🔨`"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":"verifier","name":"verifier-2","description":"V2","prompt":"R-0002: again `deploy/prod/values.yaml`, `Emoji: 🔨`, `only-once-here`"}}]}}
EOF
perl -pi -e "s#CWD#$T#" s.jsonl
a=$("$HERE/director-audit" s.jsonl)
grep -q 'name reused: builder (2 spawns)' <<< "$a" || fail "audit missed reuse: $a"
grep -q 'not a project role: general-purpose' <<< "$a" || fail "audit missed general-purpose: $a"
grep -q 'job-style name ×1: gdpr-card' <<< "$a" || fail "audit missed job name: $a"
grep -q "builder-nat-keepalive" <<< "$(grep job-style <<< "$a")" && fail "audit flagged a role-plus-topic name: $a"
grep -q 'unnamed: 1' <<< "$a" || fail "audit missed unnamed: $a"
grep -q 'follow-ups to existing workers: 1' <<< "$a" || fail "audit missed follow-ups: $a"
grep -q "repeated in briefs to verifier across requests (move to its role file): deploy/prod/values.yaml$" <<< "$a" || fail "audit missed repeated background: $a"

# req prune: only clean, pushed, idle agent worktrees go
P=$T/prune; git init -q --bare "$P/origin.git"; git init -q "$P/repo"; cd "$P/repo"
g() { git -c user.email=t@t -c user.name=t "$@"; }
g commit -q --allow-empty -m base; git remote add origin "$P/origin.git"; git push -q origin HEAD:main 2>/dev/null; git fetch -q origin
mkdir -p .claude/worktrees director/requests/open
for n in pushed dirty unpushed recent; do git worktree add -q -b "worktree-agent-$n" ".claude/worktrees/agent-$n" origin/main 2>/dev/null; done
echo x > .claude/worktrees/agent-dirty/f
(cd .claude/worktrees/agent-unpushed && g commit -q --allow-empty -m local)
for n in pushed dirty unpushed; do find ".claude/worktrees/agent-$n" -exec touch -h -t 202601010000 {} +; done
out=$(req prune)
[[ ! -d .claude/worktrees/agent-pushed ]] || fail "prune kept a clean pushed worktree: $out"
git show-ref -q refs/heads/worktree-agent-pushed && fail "prune left the branch of a removed worktree"
for n in dirty unpushed recent; do [[ -d .claude/worktrees/agent-$n ]] || fail "prune removed $n: $out"; done
grep -q 'pruned 1 agent worktrees, kept 3' <<< "$out" || fail "prune summary: $out"

# squash-merged worktrees, and worktrees in other repos listed in director/repos
cd "$T"; N=$(mktemp -d); trap 'rm -rf "${T:?}" "${N:?}"' EXIT; mkdir -p "$N/director/requests/open"; touch "$N/DIRECTOR.md"; cd "$N"
slug="${N//\//-}"
R=$T/other; git init -q --bare "$R-origin.git"; git init -q "$R"; cd "$R"
echo a > a; echo b > b; g add a b; g commit -q -m base; git remote add origin "$R-origin.git"; git push -q origin HEAD:main 2>/dev/null; git fetch -q origin
git remote set-head origin main >/dev/null
printf '%s\n' '# comment' '' "$R" > "$N/director/repos"
mine=$T/scratch/$slug/wt; other=$T/scratch/-some-other-project/wt; mkdir -p "$mine" "$other"
for n in squash stale dirty; do git worktree add -q -b "t-$n" "$mine/$n" origin/main 2>/dev/null; done
git worktree add -q -b t-foreign "$other/foreign" origin/main 2>/dev/null
for n in squash stale dirty; do (cd "$mine/$n" && echo "$n" > "f-$n" && g add . && g commit -q -m "$n"); done
(cd "$other/foreign" && echo x > a && g commit -qam foreign)
# main squash-merges both, then changes the file of "stale" again
echo squash > f-squash; echo stale > f-stale; g add f-squash f-stale; g commit -q -m "squash merge"
echo later > f-stale; g commit -qam "later change"; git push -q origin HEAD:main; git fetch -q origin
echo dirt > "$mine/dirty/zzz"
find "$mine" "$other" -exec touch -h -t 202601010000 {} +; echo dirt > "$mine/dirty/zzz"
cd "$N"; out=$(req prune)
[[ ! -d $mine/squash ]] || fail "squash-merged worktree kept: $out"
for d in "$mine/stale" "$mine/dirty" "$other/foreign"; do [[ -d $d ]] || fail "prune removed $d: $out"; done
grep -q "foreign" <<< "$out" && fail "prune looked at a foreign worktree: $out"
grep -q "pruned 1 agent worktrees, kept 2" <<< "$out" || fail "other-repo prune summary: $out"
git -C "$R" show-ref -q refs/heads/t-squash || fail "prune deleted a branch in a listed repo"
rm -f director/repos; out=$(req prune)
[[ $out == "not a git repo and no director/repos" ]] || fail "no-repos message: $out"

# non-ASCII and renamed files, apostrophe repo path, patch-id landing
cd "$R"
echo m > mm; g add mm; g commit -q -m m2; git push -q origin HEAD:main; git fetch -q origin
for n in uni ren pid pidx; do git worktree add -q -b "t-$n" "$mine/$n" origin/main 2>/dev/null; done
(cd "$mine/uni" && echo u > "Málaga.txt" && g add . && g commit -q -m uni)
(cd "$mine/ren" && git mv b b2 && g commit -qm ren)
for n in pid pidx; do (cd "$mine/$n" && echo p > "p-$n" && g add . && g commit -q -m "$n"); done
echo b > b2; g add b2; g commit -q -m "b2 only"
echo p > p-pid; g add p-pid; g commit -q -m "squash pid"; echo later > p-pid; g commit -qam "later pid"
echo different > p-pidx; g add p-pidx; g commit -q -m "other pidx"; echo later > p-pidx; g commit -qam "later pidx"
git push -q origin HEAD:main; git fetch -q origin
find "$mine" -exec touch -h -t 202601010000 {} +
RA="$T/it's #1 repo"; git clone -q "$R" "$RA"; git -C "$RA" worktree add -q -b t-apos "$mine/apos" origin/main; find "$mine/apos" -exec touch -h -t 202601010000 {} +
printf '%s\n' "$R" "$RA" > "$N/director/repos"
cd "$N"; out=$(req prune)
for n in uni ren pidx; do [[ -d $mine/$n ]] || fail "prune removed $n: $out"; done
[[ ! -d $mine/pid ]] || fail "patch-id landed worktree kept: $out"
[[ ! -d $mine/apos ]] || fail "apostrophe repo not pruned: $out"

# patch-id must not ignore whitespace: same line at another indent is not the same change
cd "$R"; printf 'p:\n  a: 1\n' > y.yaml; g add y.yaml; g commit -q -m y; git push -q origin HEAD:main; git fetch -q origin
git worktree add -q -b t-ws "$mine/ws" origin/main; (cd "$mine/ws" && printf 'p:\n  a: 1\nb: 2\n' > y.yaml && g commit -qam ws)
printf 'p:\n  a: 1\n  b: 2\n' > y.yaml; g commit -qam nested; echo z > z; g add z; g commit -q -m z; echo zz > z; g commit -qam zz; git push -q origin HEAD:main; git fetch -q origin
find "$mine/ws" -exec touch -h -t 202601010000 {} +
cd "$N"; out=$(req prune); [[ -d $mine/ws ]] || fail "whitespace-only patch-id match removed: $out"


# link: the fixed path points at these scripts, and a real folder there is left alone
B=$T/share/bin
DIRECTOR_BIN=$B "$HERE/link" > /dev/null || fail "link failed"
[[ $(readlink "$B") == "$HERE" ]] || fail "link points at $(readlink "$B")"
DIRECTOR_BIN=$B "$HERE/link" > /dev/null || fail "link not idempotent"
rm "$B" && mkdir -p "$B"
DIRECTOR_BIN=$B "$HERE/link" > /dev/null 2>&1 && fail "link replaced a real folder"

echo "all tests passed"
