# CLAUDE.md

 let's 
# What this is

A desktop tool, not a library: bash + python3 + QML, no build step, no dependencies to
install. `wt` maps one git branch → one git worktree (`~/.worktrees/<repo>/<branch>`) →
one KDE Plasma Activity named `<repo>: <branch>`. Read `README.md` for the user-facing
feature list and the install steps.

## Commands

```bash
./wt-tests.sh                              # the whole test suite (session-id norm, PR-body scan, wt-cloud parsing)
./wt-status ~/.worktrees/<repo>/<branch> | jq   # the widget's JSON card, as the plasmoid sees it
./wt-status <path> plain                   # what `wt list` renders (ANSI)
./wt-status <path> force                   # bypass the cache
./wt-cloud json | jq                       # the cloud card
./wt-cloud raw [match]                     # raw private-API records — first stop when the shape drifts
./wt-cloud refresh                         # force a snapshot refresh
bash -n wt && bash -n wt-status            # syntax check (no linter configured)
```

Scripts are symlinked into `~/.local/bin` and `~/.local/share/plasma/plasmoids/`, so edits
to `wt`/`wt-status`/`wt-cloud` take effect immediately. **QML is the exception**:
plasmashell caches it, so after editing the plasmoid run
`systemctl --user restart plasma-plasmashell`, then `wt dashboard` to re-place the cards.

There is no single-test selector — `wt-tests.sh` is ~20 assertions and runs in a second.
It does two fragile things worth knowing before you refactor:

- it `sed`-extracts `norm_session()` out of `wt` and `eval`s it, so that function must stay
  a self-contained block matching `/^norm_session()/,/^}/`;
- it imports `wt-cloud` as a python module, so `wt-cloud` must stay import-safe (all work
  behind `main()`), and the PR-body regex in the test must stay in sync with the `scan(...)`
  in `wt-status`'s jq program.

## Architecture

**Four producers, one renderer.** `wt-status <worktree>` and `wt-cloud json` each print one
JSON *card* on stdout; the `org.kde.wt.board` plasmoid renders it and knows nothing else.
The contract is documented at the top of `plasmoid/.../ui/main.qml` — `{title, subtitle,
badge, layout, rows}` with `layout: "fields"` (label/value rows, `wt-status`) or `"list"`
(one hoverable session per row, `wt-cloud`). Producers emit semantic **levels**
(`ok/warn/error/info/dim/normal`), never colors; `levelColor()` resolves them against the
Plasma theme. All quoting is done by `jq`/`json.dump`, never by hand.

**Verdict then facts.** Every surface (widget badge, `wt list` line, activity description +
icon) leads with one verdict — "what is the next action for this branch" — then facts. The
verdict is computed once, in `wt-status`'s big jq program, from the `gh pr view` JSON, and a
live coding agent can *override* it: `agent_rank` 3 (blocked) or 2 (working) replaces the
verdict in `compose()`, because the agent is the branch's current actor.

**The emoji vocabulary is internal.** `wt-status` builds status strings with emoji
(`🤖 ✋ 💤 ❔ ❌ ⏳ ✅ 🟣`), then translates: `stylize()` (sed) → ANSI glyphs for terminals,
and the `glyph`/`lvl` jq functions in `compose()` → widget glyph + level. Adding a status
means touching all three: the producer string, `stylize()`, and `compose()`'s jq.

**Join keys.** The activity name `"<repo>: <branch>"` is what links a worktree to its
Activity everywhere (`find_activity`, `wt_name`, `wt-activity-watch`), and
`~/.worktrees/<repo>/<branch>` encodes both — which is why `wt-cloud` can map branches to
worktrees with no git calls. The claude.ai session tied to a worktree lives in
`$(git rev-parse --absolute-git-dir)/wt-session`: outside the working tree, so it never
shows as a change and dies with the worktree. `wt-status` refreshes it from the live session
list, else from the PR body.

**Agent detection**, one branch per agent in `wt-status`, all via `count_in_worktree` (pgrep
+ `/proc/<pid>/cwd` under the worktree, parent-dedup): claude reads hook-written state files
in `$XDG_RUNTIME_DIR/wt-agents/` (`wt-agent-state`, TSV `agent state cwd ts`); codex uses
`~/.codex/sessions/rollout-*.jsonl` write age plus a wezterm pane titled "Action Required"
for blocked; cursor uses `~/.cursor/chats/<md5-of-path>/` write age. Cloud sessions have no
process — `wt-cloud lookup` matches the branch against what each session pushed.

**Caching.** `wt-status` writes `$XDG_CACHE_HOME/wt-status/<cksum>.v3.json` plus `.desc`
and `.icon` siblings. The widget ticks every ~5s but almost always hits the cache: GitHub is
touched at most every 55s for the current activity, 10 min for inactive ones, immediately
with `force` (what `wt-activity-watch` fires on activity switch). **Bump the `.vN` in
`cache_file` whenever the row shape changes** — an old cache rendered in a new skeleton is
the failure mode it exists to prevent. Agent state and dirty/unpushed counts are always
live, never cached. `wt-cloud` keeps a 30s snapshot in `cloud.json`, written atomically
under a lock, and keeps the last good one on failure so the widget never blanks.

**Failure posture.** `wt` runs `set -euo pipefail`; `wt-status` deliberately does **not**
use `-e` and exits 0 on missing worktrees, no PR, or offline `gh` — a hard failure would
blank the widget. Keep that.

**KDE plumbing quirks** (all in `wt`): a desktop applet's geometry is read-only through the
scripting API, so `install_board()` resizes by removing and re-adding the widget at the old
coordinates (which can legitimately be negative). **`wt` never writes the wallpaper**: it
used to set a per-repo solid color via `org.kde.color`, whose `config.qml` (plasma-workspace
6.6.5) omits the `configDialog`/`wallpaperConfiguration` properties `kcm_wallpaper` assigns
unconditionally — so the wallpaper config UI died on any containment wt had touched. Activity
name, icon and description are the only KDE state wt owns; keep it that way.
Windows are pinned to an activity by a throwaway KWin script that self-unloads after 120s,
because Wayland ties new windows to the launching terminal instead. `wt remove` runs its
window-close + activity-removal tail detached via `setsid`, since it may be closing the
terminal running the script.

**`wt-cloud` talks to a private, unsupported API** (`api.anthropic.com/v1/code/sessions`)
with the Claude CLI's OAuth token from `~/.claude/.credentials.json`. All endpoint and field
knowledge is confined to `fetch()` and `normalize()` so a rename breaks one place — keep it
that way, and keep it read-only (never start/stop/archive a session) and token-silent (never
log, persist, or pass it as an argument).

## Conventions

- Deliberate simplifications with a known ceiling are marked `# ponytail: <what, and the
  upgrade path>` (see `wt-status:183`, `wt:604`). Follow that when you take a shortcut.
- Comments explain *why the obvious thing does not work here* (Wayland, Plasma, jq quoting,
  set -e interactions). Keep that density; do not add narration.
- `wt` subcommands are listed in four places that must stay in sync: the `case` dispatch,
  `usage()`, `help()`, and `completions/_wt`.
- User-tunable values are `WT_*` vars with defaults at the top of `wt`, overridable via
  `~/.config/wt/config` — a new knob also goes into `config.example` and the README table.
- No emoji in the widget font stack for hourglasses — the widget path uses `✔ ✘ ○ ⟳`.
