#!/usr/bin/env bash
# Self-test for req, director-audit, director-retro, the hooks and hc-worker, in a throwaway git repo.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
unset CLAUDE_CODE_SESSION_ID
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
grep -qE "^$aid	[0-9T:Z-]+	approve merging #96	open\$" <<< "$out" || fail "asks output: $out"
perl -pi -e 's/^- \[ \] \d{4}-\S+/- [ ] 2020-01-01T00:00Z:/' "director/requests/open/$aid.md"
out=$(req lint 2>/dev/null || true)
grep -q "$aid has waited on the user since 2020-01-01T00:00Z: approve merging #96\$" <<< "$out" || fail "lint missed an old ask: $out"
req ask "$aid" --done > /dev/null
[[ -z $(req asks) ]] || fail "ask still open after --done"
printf -- '- [ ] 2020-01-01T00:00Z: an old line\n' >> "director/requests/open/$aid.md"
grep -qE "^$aid	2020-01-01T00:00Z	an old line	open\$" <<< "$(req asks)" || fail "an old ask line does not read as open"
req ask "$aid" "merge #97?" --yes-no > /dev/null
out=$(req asks)
grep -qE "^$aid	[0-9T:Z-]+	merge #97\?	yes-no\$" <<< "$out" || fail "yes-no ask output: $out"
req ask "$aid" --yes-no "flag first" > /dev/null
grep -qE "^$aid	[0-9T:Z-]+	flag first	yes-no\$" <<< "$(req asks)" || fail "--yes-no before the text was not read as the flag"
before=$(req asks | wc -l)
req ask "$aid" "typo" --yes_no > /dev/null 2>&1 && fail "an unknown flag after the text was accepted"
req ask "$aid" --bogus > /dev/null 2>&1 && fail "an unknown flag as the text was accepted"
req ask "$aid" "two" "texts" > /dev/null 2>&1 && fail "two texts were accepted"
[[ $(req asks | wc -l) == "$before" ]] || fail "a refused ask was stored"
long=$(printf 'x%.0s' $(seq 101))
req ask "$aid" "$long" --yes-no > /dev/null 2>&1 && fail "a yes-no ask over 100 characters was accepted"
req ask "$aid" "${long:1}" --yes-no > /dev/null 2>&1 || fail "a 100 character yes-no ask was refused"
req ask "$aid" "$long$long" > /dev/null 2>&1 || fail "a long open ask was refused"
req ask "$aid" "second ask" > /dev/null
[[ $(req asks | grep -c "	open\$") == 3 ]] || fail "a plain ask is not open-ended"
req status "$aid" dropped "test" > /dev/null
[[ -z $(req asks) ]] || fail "closing left an ask open"
grep -q "^asks test - \[ \] not an ask\$" "director/requests/closed/$aid.md" || fail "closing touched request text"

[[ ! -d director/requests/.lock ]] || fail "lock left behind"

# owners: req new records the session that made the request; req open says whose it is; req adopt takes one over
oid=$(echo "no session" | req new); of=director/requests/open/$oid.md
grep -q '^owner:' "$of" && fail "req new recorded an owner with no session id"
[[ $(req open | grep "^$oid" | grep -c unowned) == 1 ]] || fail "open did not mark a request with no owner as unowned: $(req open)"
oid=$(echo "mine" | CLAUDE_CODE_SESSION_ID=sess-aaaaaaaa-1 req new); of=director/requests/open/$oid.md
has "$of" 'owner: sess-aaaaaaaa-1'
[[ $(sed -n '2,8p' "$of" | grep -c '^---$') == 0 ]] || fail "owner line landed outside the front matter"
[[ $(CLAUDE_CODE_SESSION_ID=sess-aaaaaaaa-1 req open | grep "^$oid" | grep -c ' mine ') == 1 ]] || fail "open did not mark the owner's request as mine"
[[ $(CLAUDE_CODE_SESSION_ID=sess-bbbbbbbb-2 req open | grep "^$oid" | grep -c 'other:sess-aaa') == 1 ]] || fail "open did not mark another session's request as other"
[[ $(req check "$oid" | head -1 | grep -c 'other:sess-aaa') == 1 ]] || fail "check does not show the owner"
req adopt "$oid" 2>/dev/null && fail "adopt worked with no session id"
out=$(CLAUDE_CODE_SESSION_ID=sess-bbbbbbbb-2 req adopt "$oid") || fail "adopt failed"
grep -q "adopted (was sess-aaaaaaaa-1)" <<< "$out" || fail "adopt output: $out"
has "$of" 'owner: sess-bbbbbbbb-2'
[[ $(grep -c '^owner:' "$of") == 1 ]] || fail "adopt duplicated the owner line"
# a request made before owners existed is adoptable, and stays in its sections
perl -ni -e 'print unless /^owner:/' "$of"
out=$(CLAUDE_CODE_SESSION_ID=sess-cccccccc-3 req adopt "$oid"); grep -q "was unowned" <<< "$out" || fail "adopt of an old request: $out"
has "$of" 'owner: sess-cccccccc-3'
awk '/^## Receipts$/{r=1} END{exit !r}' "$of" || fail "adopt damaged the request"
req status "$oid" dropped "test" > /dev/null
CLAUDE_CODE_SESSION_ID=sess-dddddddd-4 req adopt "$oid" 2>/dev/null && fail "adopt took over a closed request"
CLAUDE_CODE_SESSION_ID=sess-dddddddd-4 req adopt R-9999 2>/dev/null && fail "adopt took a missing request"
rid=$(echo "retro" | req new --retro --mission m9); has "director/requests/open/$rid.md" 'kind: retro'; has "director/requests/open/$rid.md" 'mission: m9'
echo x | req new --bogus 2>/dev/null && fail "req new accepted an unknown flag"
req status "$rid" dropped "test" > /dev/null

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
# report-check in a linked worktree: the report must be in the main checkout
git init -q wtmain && git -C wtmain -c user.name=t -c user.email=t@t commit -q --allow-empty -m i && git -C wtmain worktree add -q "$T/wtlinked" -b wt
WT=$(cd wtlinked && pwd -P); MAIN=$(cd wtmain && pwd -P)
mkdir -p wtlinked/director/reports; echo r > wtlinked/director/reports/X.md
wtrc() { jq -n --arg m "$1" --arg c "$WT" '{last_assistant_message: $m, cwd: $c}' | "$HERE/report-check"; }
out=$(wtrc 'Report: director/reports/X.md')
grep -q "$MAIN/director/reports/X.md" <<< "$out" || fail "report-check let a worktree-only report through: $out"
mkdir -p wtmain/director/reports; echo r > wtmain/director/reports/X.md
[[ -z $(wtrc 'Report: director/reports/X.md') ]] || fail "report-check blocked a report present in the main checkout"
[[ -z $(wtrc "Report: $MAIN/director/reports/X.md") ]] || fail "report-check blocked an absolute main-checkout path"
[[ -z $(rc 'Done, all good.' true) ]] || fail "report-check blocked twice in a row"
[[ -z $(echo '{}' | "$HERE/report-check") ]] || fail "report-check blocked on missing input"

# issue-check stop hook, with a fake gh on PATH
mkdir -p fakebin; cat > fakebin/gh <<'GH'
#!/usr/bin/env bash
[[ -n ${GH_FAIL:-} ]] && exit 1
[[ -n ${GH_SLEEP:-} ]] && sleep "$GH_SLEEP"
if [[ $2 == view ]]; then cat "$GH_ISSUE"; else echo "${GH_PRS:-[]}"; fi
GH
chmod +x fakebin/gh
ic() { jq -n --arg t "$1" '{agent_transcript_path: $t, stop_hook_active: ('"${2:-false}"')}' | PATH=$T/fakebin:$PATH "$HERE/issue-check"; }
brief() { jq -nc --arg c "$1" '{type: "user", message: {content: $c}}' > tr-$2.jsonl; echo '{"type":"assistant"}' >> tr-$2.jsonl; }
brief $'Fix it.\nIssue: acme/app#126  Job: build\nmore' b
brief $'Issue: acme/app#126  Job: plan' p
brief 'no issue line here' n
export GH_ISSUE=$T/issue.json
echo '{"state":"OPEN","assignees":[{"login":"x"}],"labels":[{"name":"ready-for-agent"}]}' > issue.json
ic tr-b.jsonl | grep -q 'acme/app#126' || fail "issue-check let an abandoned issue through"
[[ -z $(ic tr-p.jsonl) ]] || fail "issue-check blocked a plan job"
[[ -z $(ic tr-n.jsonl) ]] || fail "issue-check blocked a brief without an issue line"
[[ -z $(ic tr-b.jsonl true) ]] || fail "issue-check blocked twice in a row"
[[ -z $(GH_FAIL=1 ic tr-b.jsonl) ]] || fail "issue-check blocked on a gh failure"
[[ -z $(GH_PRS='[{"number":130,"body":"Closes #126."}]' ic tr-b.jsonl) ]] || fail "issue-check blocked an issue with an open PR"
ic tr-b.jsonl > /dev/null
GH_PRS='[{"number":131,"body":"see #1260 and acme/app#12 and 126 and #26"},{"number":132,"body":null}]' ic tr-b.jsonl | grep -q '"block"' || fail "issue-check took an unrelated PR for a link"
SECONDS=0; [[ -z $(GH_SLEEP=20 ISSUE_CHECK_TIMEOUT=1 ic tr-b.jsonl) ]] || fail "issue-check blocked on a hung gh"
[[ $SECONDS -lt 10 ]] || fail "issue-check did not time out a hung gh"
brief $'- **Issue: `acme/app#126`  Job: Build**' m
ic tr-m.jsonl | grep -q 'acme/app#126' || fail "issue-check missed a markdown-wrapped brief line"
echo '{"state":"OPEN","assignees":[],"labels":[{"name":"ready-for-agent"}]}' > issue.json
[[ -z $(ic tr-b.jsonl) ]] || fail "issue-check blocked an unassigned issue"
echo '{"state":"OPEN","assignees":[{"login":"x"}],"labels":[{"name":"needs-info"}]}' > issue.json
[[ -z $(ic tr-b.jsonl) ]] || fail "issue-check blocked a relabelled issue"
[[ -z $(echo '{}' | "$HERE/issue-check") ]] || fail "issue-check blocked on missing input"

# skill-check stop hook
sc() { jq -n --arg t "$1" '{agent_transcript_path: $t, stop_hook_active: ('"${2:-false}"')}' | "$HERE/skill-check" tdd code-review; }
skill() { jq -nc --arg s "$1" '{type: "assistant", message: {content: [{type: "tool_use", name: "Skill", input: {skill: $s}}]}}'; }
brief $'Issue: acme/app#126  Job: build' sb
sc tr-sb.jsonl | grep -q 'tdd, code-review' || fail "skill-check let a build job through with no skills"
skill mattpocock-skills:tdd >> tr-sb.jsonl
sc tr-sb.jsonl | grep -q 'not loaded yet: code-review\.' || fail "skill-check named a loaded skill as missing"
skill code-review >> tr-sb.jsonl
[[ -z $(sc tr-sb.jsonl) ]] || fail "skill-check blocked a build job that loaded its skills"
[[ -z $(sc tr-p.jsonl) ]] || fail "skill-check blocked a plan job"
[[ -z $(sc tr-n.jsonl) ]] || fail "skill-check blocked a brief without a Job line"
[[ -z $(sc tr-b.jsonl true) ]] || fail "skill-check blocked twice in a row"
cp tr-p.jsonl tr-pb.jsonl; jq -nc '{type: "user", message: {content: [{type: "text", text: "Your plan is approved.\nJob: **build**"}]}}' >> tr-pb.jsonl
sc tr-pb.jsonl | grep -q '"block"' || fail "skill-check missed a plan job resumed as a build"
skill tdd-extra >> tr-pb.jsonl; skill code-review >> tr-pb.jsonl
sc tr-pb.jsonl | grep -q 'not loaded yet: tdd\.' || fail "skill-check matched a skill by prefix"
[[ -z $(echo '{}' | "$HERE/skill-check" tdd) ]] || fail "skill-check blocked on missing input"

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
R=$T/other; git init -q --bare "$R-origin.git"; git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; cd "$R"
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

# hc-worker: refuses outside Herdr, without a role file, or in an untrusted folder; else runs hc
H=$T/hc; mkdir -p "$H/bin" "$H/cfg" "$H/proj/sub/.claude/agents" "$H/other/.claude/agents"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/args"; pwd -P > "%s/cwd"; [ -n "$FAKE_ADDR" ] && printf "{\\"address\\":\\"%%s\\"}\\n" "$FAKE_ADDR"; exit 0\n' "$H" "$H" > "$H/bin/hc"; chmod +x "$H/bin/hc"
touch "$H/proj/sub/.claude/agents/builder.md" "$H/other/.claude/agents/builder.md"
jq -n --arg p "$H/proj" '{projects: {($p): {hasTrustDialogAccepted: true}}}' > "$H/cfg/.claude.json"
hcw() { local d=$1; shift; (cd "$d" && PATH=$H/bin:$PATH CLAUDE_CONFIG_DIR=$H/cfg "$HERE/hc-worker" "$@"); }
echo brief | HC_TERMINAL_ID= hcw "$H/proj/sub" b builder sonnet medium 2>/dev/null && fail "hc-worker ran outside Herdr"
export HC_TERMINAL_ID=t1
echo brief | hcw "$H/proj/sub" b verifier sonnet medium 2>/dev/null && fail "hc-worker ran without a role file"
echo brief | hcw "$H/other" b builder sonnet medium 2>/dev/null && fail "hc-worker ran in an untrusted folder"
printf 'the brief\nline 2' | hcw "$H/proj/sub" builder-x builder sonnet high -- --permission-mode auto || fail "hc-worker refused a trusted subfolder"
has "$H/args" 'builder-x'; has "$H/args" 'director.role=builder'; has "$H/args" '--permission-mode'
[[ $(tail -2 "$H/args") == $'the brief\nline 2' ]] || fail "brief not passed last: $(cat "$H/args")"
# --repo: the worker starts in the other repo with its role; the report path must point home
mkdir -p "$H/proj/home" "$H/proj/nerea/.claude/agents"; touch "$H/proj/nerea/.claude/agents/infra-builder.md"
HOMEP=$(cd "$H/proj/home" && pwd -P)
echo "Report: director/reports/R-0001-x.md" | hcw "$H/proj/home" --repo ../nerea ib infra-builder sonnet medium 2>/dev/null && fail "hc-worker --repo took a relative report path"
echo "Report: $HOMEP/director/reports/R-0001-x.md" | hcw "$H/proj/home" --repo ../nerea infra-builder-x infra-builder sonnet medium || fail "hc-worker --repo refused a good brief"
[[ $(cat "$H/cwd") == "$(cd "$H/proj/nerea" && pwd -P)" ]] || fail "hc-worker --repo ran in $(cat "$H/cwd")"
has "$H/args" 'infra-builder-x'
# workers.tsv: one line per worker in the home project, with the session id the worker was started with
[[ ! -e $H/proj/home/director/workers.tsv ]] || rm "$H/proj/home/director/workers.tsv"
echo "Report: $HOMEP/director/reports/R-0001-x.md" | FAKE_ADDR=t9 CLAUDE_CODE_SESSION_ID=dir-sess-1 hcw "$H/proj/home" --repo ../nerea infra-builder-y infra-builder sonnet medium > "$H/stdout" || fail "hc-worker failed"
grep -q '"address":"t9"' "$H/stdout" || fail "hc-worker hid hc's output: $(cat "$H/stdout")"
wsid=$(grep -A1 -x -- '--session-id' "$H/args" | tail -1)
[[ $wsid =~ ^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$ ]] || fail "hc-worker passed no session id to claude: $(cat "$H/args")"
[[ $(wc -l < "$H/proj/home/director/workers.tsv" | tr -d " ") == 1 ]] || fail "workers.tsv: $(cat "$H/proj/home/director/workers.tsv")"
[[ ! -e $H/proj/nerea/director/workers.tsv ]] || fail "workers.tsv written in the other repo"
IFS=$'\t' read -r w_t w_name w_role w_cwd w_sid w_term w_dir < "$H/proj/home/director/workers.tsv"
[[ $w_t =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ && $w_name == infra-builder-y && $w_role == infra-builder && $w_cwd == "$(cd "$H/proj/nerea" && pwd -P)" && $w_sid == "$wsid" && $w_term == t9 && $w_dir == dir-sess-1 ]] || fail "workers.tsv fields: $(cat "$H/proj/home/director/workers.tsv")"
echo "Report: $HOMEP/director/reports/R-0001-x.md" | hcw "$H/proj/home" --repo ../nerea infra-builder-z infra-builder sonnet medium || fail "hc-worker failed with no terminal address"
[[ $(wc -l < "$H/proj/home/director/workers.tsv" | tr -d " ") == 2 ]] || fail "workers.tsv did not grow"
[[ $(tail -1 "$H/proj/home/director/workers.tsv" | awk -F'\t' '{print NF ":" $6 ":" $7}') == "7::" ]] || fail "workers.tsv line without terminal or director session: $(tail -1 "$H/proj/home/director/workers.tsv")"
echo brief | hcw "$H/proj/home" b norole sonnet medium 2>/dev/null || true; [[ $(wc -l < "$H/proj/home/director/workers.tsv" | tr -d " ") == 2 ]] || fail "a refused worker was recorded"
echo "Report: $HOMEP/director/reports/R-0001-x.md" | hcw "$H/proj/home" --repo ../missing ib infra-builder sonnet medium 2>/dev/null && fail "hc-worker --repo ran in a missing folder"
echo "Report: $HOMEP/director/reports/R-0001-x.md" | hcw "$H/proj/home" --repo "$H/other" ib builder sonnet medium 2>/dev/null && fail "hc-worker --repo ran in an untrusted folder"
unset HC_TERMINAL_ID

# director-retro, on a synthetic config dir: a director session with a subagent and a Herdr worker in another project folder
cd "$T"; RR=$T/retro-home; CFG=$T/cfg; mkdir -p "$RR/director/requests/open" "$RR/director/requests/closed" "$RR/director/reports"
touch "$RR/DIRECTOR.md"; RR=$(cd "$RR" && pwd -P)
j() { jq -nc "$@"; }
PD=$CFG/projects/$(printf '%s' "$RR" | sed 's/[^A-Za-z0-9-]/-/g'); mkdir -p "$PD/D1/subagents" "$CFG/projects/-elsewhere"
{ j '{type:"user",timestamp:"2026-11-23T10:00:00.000Z",origin:{kind:"human"},message:{content:"fix the flaky deploy, PROJ-5"}}'
  j '{type:"user",isMeta:true,message:{content:"<system-reminder>not a message</system-reminder>"}}'
  j '{type:"user",origin:{kind:"task-notification"},message:{content:"<task-notification>x</task-notification>"}}'
  j '{type:"user",origin:{kind:"human"},message:{content:"no, use the staging bucket"}}'
  j '{type:"assistant",timestamp:"2026-11-23T10:01:00.000Z",message:{content:[{type:"tool_use",id:"tu1",name:"Bash",input:{command:"~/.local/share/director/bin/req status R-0001 in-flight"}},{type:"tool_use",id:"tu2",name:"Bash",input:{command:"false"}},{type:"tool_use",id:"tu3",name:"Edit",input:{}}]}}'
  j '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"tu1",content:"ok"}]}}'
  j '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"tu2",is_error:true,content:"Exit code 2\nboom: no such file\nmore"}]}}'
  j '{type:"user",toolDenialKind:"automode-blocked",permissionDecision:{decision:"reject"},message:{content:[{type:"tool_result",tool_use_id:"tu3",is_error:true,content:"Permission for this action was denied by the Claude Code auto mode classifier. Reason: [Destructive]. If you have other tasks, go on."}]}}'
  j '{type:"user",isMeta:true,message:{content:"Stop hook feedback:\nYour reply is 24 lines. The full report is in x."}}'
  j '{type:"user",isMeta:true,message:{content:"Stop hook feedback:\nYour reply is 31 lines. The full report is in x."}}'
  j '{type:"system",subtype:"turn_duration",durationMs:60000,timestamp:"2026-11-23T11:30:00.000Z"}'
} > "$PD/D1.jsonl"
{ j '{type:"user",message:{content:"Investigate the cache"}}'; j '{type:"assistant",message:{content:[{type:"tool_use",id:"s1",name:"Read",input:{}}]}}'; } > "$PD/D1/subagents/agent-aa.jsonl"
echo '{"agentType":"verifier","description":"Check the PR"}' > "$PD/D1/subagents/agent-aa.meta.json"
{ j '{type:"user",message:{content:"Build the fix"}}'; j '{type:"user",isMeta:true,message:{content:"Stop hook feedback:\nWrite your full report to a file."}}'; } > "$CFG/projects/-elsewhere/W1.jsonl"
printf '2026-11-23T10:05:00Z\tbuilder-x\tbuilder\t/elsewhere\tW1\tt9\tD1\n2026-11-23T10:06:00Z\tother-w\tbuilder\t/elsewhere\tW2\tt8\tD9\n' > "$RR/director/workers.tsv"
j '{type:"user",origin:{kind:"human"},message:{content:"an older session"}}' > "$PD/D2.jsonl"; touch -t 202401010000 "$PD/D2.jsonl"
mkreq() { printf -- '---\nid: %s\ndate: 2026-11-23\nstatus: %s\nmission: %s\n%s---\n\n## Request\n%s\n\n## Addenda\n\n## Outcome\n%s\n\n## Receipts\n' "$1" "$2" "$3" "$4" "$5" "$6" > "$RR/director/requests/$7/$1.md"; }
mkreq R-0001 done m1 'owner: D1
' "fix PROJ-5 deploy" "2026-11-23: rework (builder): verify failed" closed
mkreq R-0002 open none '' "again PROJ-5, other cause" "" open
mkreq R-0003 done none 'kind: retro
' "retro" "" closed; touch -t 202501010000 "$RR/director/requests/closed/R-0003.md"
printf 'Done.\nNext time: a staging bucket name in the role file would have saved a question.\n' > "$RR/director/reports/R-0001-builder.md"
rt() { (cd "$RR" && CLAUDE_CONFIG_DIR=$CFG "$HERE/director-retro" "$@"); }
out=$(rt --session D1) || fail "director-retro failed: $out"
for want in "session D1" "turns 1, active 1m0s, wall 1h30m" 'user messages (2):' '- fix the flaky deploy, PROJ-5' '- no, use the staging bucket' 'tools: Bash×2 Edit×1' \
  'failed tool calls (1):' '- Bash: Exit code 2 | boom: no such file' 'denied (1):' '- Edit: auto mode: Reason: [Destructive].' 'stop hook blocks (2):' 'Your reply is N lines. The full report is in x. ×2' \
  '### subagent verifier: Check the PR' '- Investigate the cache' '### herdr worker builder-x (builder, t9' '- Build the fix' 'Write your full report to a file.' \
  'R-0001  done' 'rework=1' 'R-0002' 'PROJ-5: R-0001, R-0002' 'R-0001-builder Next time: a staging bucket name' '## req stats'; do
  grep -qF -- "$want" <<< "$out" || fail "director-retro output lacks: $want
$out"
done
grep -qF 'not a message' <<< "$out" && fail "director-retro showed a system reminder as a user message"
grep -qF 'task-notification' <<< "$out" && fail "director-retro showed a task notification as a user message"
grep -qF 'other-w' <<< "$out" && fail "director-retro listed another director's worker"
grep -qF 'an older session' <<< "$out" && fail "director-retro read a session outside its scope"
# the current session is the default scope
out=$(CLAUDE_CODE_SESSION_ID=D1 rt) || fail "default scope failed"; grep -qF 'director session D1' <<< "$out" || fail "default scope is not the current session"
rt > /dev/null 2>&1 && fail "director-retro ran with no scope"
rt --session NOPE > /dev/null 2>&1 && fail "director-retro accepted a session with no transcript"
# limits: messages cut, and the output says so
out=$(rt --session D1 --msgs 1 --clip 12); grep -qF 'user messages (2), first 1:' <<< "$out" || fail "--msgs did not bound messages: $out"
grep -qF -- '- fix the flak…' <<< "$out" || fail "--clip did not cut: $out"
# a mission, a theme, and everything since the last retro
out=$(rt --mission m1) || fail "--mission failed"; grep -qF 'director session D1' <<< "$out" || fail "--mission missed the session that owns its request"
out=$(rt --theme 'other CAUSE') || fail "--theme failed"; grep -qF 'R-0002' <<< "$out" || fail "--theme missed a request"
rt --mission nothing > /dev/null 2>&1 && fail "--mission with no request succeeded"
out=$(rt --since-last) || fail "--since-last failed: $out"
grep -qF 'retro R-0003 closed' <<< "$out" || fail "--since-last did not name the retro: $out"
grep -qF 'director session D1' <<< "$out" || fail "--since-last missed a session after the retro"
grep -qF 'an older session' <<< "$out$(grep -F 'director session D2' <<< "$out")" && fail "--since-last read a session before the retro"
out=$(rt --since 2025-06-01) || fail "--since failed"; grep -qF 'director session D1' <<< "$out" || fail "--since missed a session"
rm "$RR/director/requests/closed/R-0003.md"
rt --since-last > /dev/null 2>&1 && fail "--since-last worked with no retro request"
# a transcript it cannot read does not stop the digest
echo 'not json' > "$PD/D3.jsonl"; out=$(rt --session D3) || fail "director-retro died on a broken transcript"; grep -qF 'could not read' <<< "$out" || fail "broken transcript not reported: $out"
rm "$PD/D3.jsonl"
# director-audit finds the latest session of the current directory through the shared lookup
out=$(cd "$RR" && CLAUDE_CONFIG_DIR=$CFG "$HERE/director-audit" 2>&1) || fail "director-audit found no session: $out"
grep -qF 'session: ' <<< "$out" || fail "director-audit output: $out"
(cd "$RR" && CLAUDE_CONFIG_DIR=$T/nocfg "$HERE/director-audit" > /dev/null 2>&1) && fail "director-audit ran with no session"

echo "all tests passed"
