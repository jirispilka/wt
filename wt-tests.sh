#!/usr/bin/env bash
# The two bits of wt's session plumbing that can break silently: session-id
# normalization and pulling the session link out of a PR body.
set -uo pipefail
cd "$(dirname "$0")"

fail=0
t() { # <desc> <expected> <actual>
    if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"
    else printf 'FAIL %s: want %q got %q\n' "$1" "$2" "$3"; fail=1; fi
}

u=https://claude.ai/code/session_01AbC_x-1
eval "$(sed -n '/^norm_session()/,/^}/p' wt)"
t "bare id"        "$u" "$(norm_session session_01AbC_x-1)"
t "api cse_ id"    "$u" "$(norm_session cse_01AbC_x-1)"
t "full url"       "$u" "$(norm_session "$u")"
t "junk rejected"  "1"  "$(norm_session /home/jirka >/dev/null; echo $?)"
t "empty rejected" "1"  "$(norm_session "" >/dev/null; echo $?)"

# keep in sync with the scan() in wt-status's jq program
scan='https://claude\\.ai/code/session_[A-Za-z0-9_-]+'
body() { jq -rn --arg b "$1" "((\$b | [scan(\"$scan\")] | last) // \"\")"; }
# the activity join key comes from the worktree PATH, so a checkout inside the
# worktree cannot rename the activity; branches keep their slashes
eval "$(sed -n '/^wt_name()/,/^}/p' wt)"
t "wt_name flat"    "repo: main"     "$(wt_name "$HOME/.worktrees/repo/main")"
t "wt_name slashes" "repo: feat/a/b" "$(wt_name "$HOME/.worktrees/repo/feat/a/b")"

# the per-repo marker: same repo -> same slot forever (no state anywhere), and
# an explicit WT_REPO_MARKS entry beats the hash
eval "$(sed -n '/^repo_mark()/,/^}/p' wt)"
mark() { IFS=$'\t' read -r e a i <<<"$(repo_mark "$1")"; printf '%s %s %s\n' "$e" "$a" "$i"; }
t "mark stable"     "$(WT_REPO_MARKS= mark wt)" "$(WT_REPO_MARKS= mark wt)"
t "mark in palette" "1" \
  "$(WT_REPO_MARKS= mark wt | grep -cE '^(.) (203|215|221|114|75|141|137|245) folder-(red|orange|yellow|green|blue|violet|brown|grey)$')"
t "mark override"   "🟢 114 folder-green" "$(WT_REPO_MARKS="wt:green" mark wt)"
t "mark emoji"      "🌳 114 folder-green" "$(WT_REPO_MARKS="other:red wt:green:🌳" mark wt)"
t "mark bad color"  "$(WT_REPO_MARKS= mark wt)" "$(WT_REPO_MARKS="wt:puce" mark wt)"

t "pr body link"   "$u" "$(body "closes #12

🤖 Generated with [Claude Code](https://claude.com/claude-code)
Session: $u")"
t "no link"        ""   "$(body "just a normal PR body")"
t "last wins"      "$u" "$(body "https://claude.ai/code/session_old $u")"

# wt-cloud's normalize(): the private-API shape, from a real (redacted) response
python3 - <<'PY' || fail=1
import importlib.machinery, importlib.util, sys
spec = importlib.util.spec_from_loader(
    "wt_cloud", importlib.machinery.SourceFileLoader("wt_cloud", "./wt-cloud"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

def sess(worker="idle", status="active", category="review_ready", needs=""):
    return {"id": "cse_01AbC", "status": status, "worker_status": worker,
            "title": "T", "last_event_at": "2026-07-28T18:51:55.514591Z",
            "unread": True,
            "external_metadata": {"post_turn_summary": {
                "status_category": category, "needs_action": needs,
                "status_detail": "D"}},
            "config": {
                "sources": [{"type": "git_repository",
                             "url": "https://github.com/apify/apify-mcp-server"}],
                "outcomes": [{"type": "git_repository", "git_info": {
                    "type": "github", "repo": "apify/apify-mcp-server",
                    "branches": ["claude/foo-ab12"], "ref": None}}]}}

bad = 0
def t(desc, want, got):
    global bad
    print(("ok   " if want == got else "FAIL ") + desc
          + ("" if want == got else ": want %r got %r" % (want, got)))
    bad |= want != got

# the web url reuses the api id's body under a session_ prefix
t("session url", "https://claude.ai/code/session_01AbC", m.normalize(sess())["url"])
t("branch match", [["apify/apify-mcp-server", "claude/foo-ab12"]],
  m.normalize(sess())["heads"])
t("running",   "working",   m.normalize(sess(worker="running"))["state"])
# only a live prompt is an interrupt...
t("requires",  "needs-you", m.normalize(sess(worker="requires_action"))["state"])
# ...an idle session that merely ENDED its turn asking something is your turn:
# nearly every session ends that way, so it must not read as an alarm
t("need_input", "your-turn", m.normalize(sess(category="need_input"))["state"])
t("failed",     "failed",    m.normalize(sess(category="failed"))["state"])
t("done",       "done",      m.normalize(sess())["state"])
t("archived",   "archived",  m.normalize(sess(status="archived", worker="running"))["state"])
t("api id form", "https://claude.ai/code/session_01AbC",
  m.normalize({"id": "cse_01AbC"})["url"])
t("missing config", [], m.normalize({"id": "cse_x"})["heads"])
# pick_head: one branch is listed under every repo of the session's environment,
# so the row must pick the pair we can act on, not heads[0]
multi = [["apify/apify-mcp-server", "claude/foo"],
         ["apify/apify-mcp-server-internal", "claude/foo"],
         ["apify/shepherd", "claude/foo"]]
t("pick_head clone", ("claude/foo", "apify-mcp-server-internal"),
  m.pick_head(multi, {}, {"apify-mcp-server-internal": "/p"}))
t("pick_head worktree", ("claude/foo", "apify-mcp-server-internal"),
  m.pick_head(multi, {"claude/foo": "apify-mcp-server-internal"}, {}))
t("pick_head neither", ("claude/foo", "apify-mcp-server"), m.pick_head(multi, {}, {}))
t("pick_head empty", ("", ""), m.pick_head([], {}, {}))

t("ssh remote",  "apify/apify-mcp-server", m.slug("git@github.com:apify/apify-mcp-server.git"))
t("https remote", "apify/apify-mcp-server", m.slug("https://github.com/apify/apify-mcp-server"))
t("junk remote",  "", m.slug("nonsense"))
sys.exit(1 if bad else 0)
PY

exit $fail
