# wt — git worktrees as KDE Activities

One branch = one git worktree = one KDE Plasma Activity with its own colored
desktop, terminal, IDE, browser, and a live PR/CI status widget.

```
wt add fix/timeout          # worktree + activity + wezterm + IDE + Chrome, all set up
# ...work, push, get reviewed...
wt list                     # all branches, numbered: agent (claude/codex), PR, CI, reviews
wt switch                   # fzf picker with status preview — or wt switch 2
wt remove feat/timeout      # by branch (from anywhere), by number (wt remove 2),
                            # or bare from inside the worktree; -f forces dirty
                            # worktree + unmerged (squash-merged) branch deletion
```

## What you get

- **Isolation**: each branch lives in `~/.worktrees/<repo>/<branch>` with a KDE
  Activity named `<repo>: <branch>`. Switching activities (`Meta+Tab`, or
  KRunner → type branch name) switches your whole context.
- **Color coding**: the activity's desktop is a solid color per repo, hue-shifted
  per branch. Enable *System Settings → Colors → Accent color → From current
  wallpaper* and the whole UI tints per activity.
- **Auto-opened apps**: wezterm (in the worktree), your IDE (worktree as
  project), Chrome (dedicated profile so your personal session/history is
  untouched; tabs: the branch's PR — or the branch on GitHub, or the repo —
  plus claude.ai/code (the tied session if there is one, see below) and any
  `WT_URLS` you configure).
- **claude.ai/code sessions, without the browser**: `wt cloud` lists the web
  sessions, urgent first — `needs you` (a live prompt waiting on you), `failed`,
  `working`, `your turn` (the last turn ended asking something), `done` — each
  with its branch, its age, and the one-line "where I left off" the session
  itself wrote. Branch names are OSC-8 links: ctrl-click opens the session.
  Idle >48h drops off (`--all` keeps it); `wt list` appends the ones with no
  worktree here as `cloud elsewhere`.
- **Cloud dashboard**: `wt dashboard` puts that list on a desktop (default the
  `Work` activity) as a `wt board` card — two lines per session, the branch
  linking to the session, a `local` badge on the ones you have checked out, and
  a hover button that either switches to that worktree's activity or checks the
  branch out (`wt add`) if it has none. It also (re)installs the branch card on
  every worktree activity, so it is the one command for fixing widgets.
- **Cloud session on the branch row**: a worktree is tied to the session that
  pushed its branch, so the widget's agent row carries a `cloud your turn 11h`
  chip linking straight to the session, ranked next to the local agents. Only a
  live prompt or a fresh failure takes over the verdict — nearly every session
  *ends* by asking something, so that state is informational by design.
  The link is found automatically (live session list, else the PR body) and can
  be set by hand with `wt add <branch> --session <url|session_…>`; it lives in
  the worktree's gitdir, and Chrome then opens that session instead of the list.
- **Start from a session**: `wt add <session_…|cse_…|claude.ai/code URL>` checks
  out whatever branch that session pushed and ties the worktree to it.
- **Verdict-first status**: every surface leads with "what's the next action"
  — `! codex needs you`, `✘ merge conflicts`, `✘ CI failing · 1/2`,
  `✔ ready to merge`, `⧗ waiting on 2 reviews`, `merged — wt remove?` — then
  the facts (PR, CI counts, per-reviewer state, linked issues).
- **Status card** on each activity desktop, drawn by the `wt board` plasmoid:
  branch and repo on top, the verdict as a coloured pill on the right, then a
  label/value list with a fixed row skeleton — same information always at the
  same place, dim placeholders when a slot is empty: `agent` · `local`
  (`3 uncommitted · 2 unpushed`, live, catches "agent finished but never
  pushed") · `pr` link + state + `+603 −2259` size · `title` · `ci` (failing
  check by name, `✘ tests ✔ 15`) · `rev` (`✔MQ37 ○alice`) · `issues` links.
  PR, issue and session links are clickable. Refreshes instantly when you switch
  to the activity, else cached (GitHub hit ≤1/min current, ≤1/10min background).
- **Coding-agent awareness**, fresh every ~5s, with brand-colored names in the widget (claude orange, codex green):
  Claude via Code hooks (`wt-agent-state`; busy/blocked/idle +
  process-liveness guard), Codex hook-free (rollout write age + wezterm pane
  title "Action Required" for the blocked state), Cursor hook-free
  (`~/.cursor/chats/<md5-of-workspace-path>/` write age; no blocked detection
  yet). A blocked or working agent overrides the verdict — it is the branch's
  current actor.
- **Activity descriptions + icons** mirror the verdict, so the `Meta+Q`
  switcher is a live dashboard: warning triangle = needs you / CI failing,
  gear = agent working / CI running, green check = ready or merged.
- **Window discipline**: new windows opened inside an activity stay in that
  activity (fixes the Plasma/Wayland default where they appear everywhere).
- **Terminal dashboard**: `wt list` (numbered, ANSI-styled — glyphs + color
  instead of emoji, stripped when piped) and `wt switch` (fzf rows carrying
  live agent + cached PR status; Enter switches). `wt switch <n>` jumps
  straight to entry n. Plain activities are included too — non-wt activities
  (e.g. Work) first, Personal pinned last.
- **Shortcuts**: `Meta+1..6` → `wt switch 1..6` (list order at press time);
  `Meta+A` cycles activities (Plasma built-in).
- **Teardown**: `wt remove` closes the activity's windows, removes the worktree
  and activity, deletes the branch only if merged.

## Requirements

KDE Plasma 6 (Wayland), `git`, `gh` (authenticated), `jq`, `python3`, `qdbus6`,
Google Chrome, zsh (for completion), and wezterm — the terminal is not
configurable: codex blocked-detection reads wezterm pane titles. The IDE is
(`WT_IDE`, default `webstorm` — any command taking a directory works).

## Install

```bash
# 0. clone somewhere stable — the install symlinks into it, edits take effect live
git clone https://github.com/jirispilka/wt ~/github/wt
REPO=~/github/wt

# 1. commands on PATH
ln -sfn "$REPO/wt" ~/.local/bin/wt
ln -sfn "$REPO/wt-activity-watch" ~/.local/bin/wt-activity-watch

# 2. the wt board widget (plasmashell caches QML — restart it after any plasmoid edit)
ln -sfn "$REPO/plasmoid/org.kde.wt.board" ~/.local/share/plasma/plasmoids/org.kde.wt.board
systemctl --user restart plasma-plasmashell    # discovers the new applet
wt dashboard                                   # place the cards

# 3. zsh completion — add BEFORE the oh-my-zsh/compinit line in ~/.zshrc:
#    fpath=($REPO/completions $fpath)
rm -f ~/.zcompdump*

# 4. activity-switch watcher (instant widget refresh on Meta+Tab)
cp "$REPO/wt-activity-watch.service" ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now wt-activity-watch

# 5. KWin script (new windows stay in the current activity)
cp -r "$REPO/kwin/wt-activity-bind" ~/.local/share/kwin/scripts/
kwriteconfig6 --file kwinrc --group Plugins --key wt-activity-bindEnabled true
qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure

# 6. wezterm: new tabs follow the pane's cwd — add to ~/.zshrc (after plugins):
#    [[ $TERM_PROGRAM == WezTerm && -r /etc/profile.d/wezterm.sh ]] && source /etc/profile.d/wezterm.sh

# 7. Claude Code agent-status hooks (jq appends to existing hooks, backup kept):
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq --arg repo "$REPO" 'def h(cmd): {"hooks":[{"type":"command","command":cmd,"timeout":10}]};
    def hm(cmd): {"matcher":"*","hooks":[{"type":"command","command":cmd,"timeout":10}]};
    .hooks.SessionStart      = (.hooks.SessionStart // [])      + [h($repo + "/wt-agent-state idle")] |
    .hooks.UserPromptSubmit  = (.hooks.UserPromptSubmit // [])  + [h($repo + "/wt-agent-state busy")] |
    .hooks.PermissionRequest = (.hooks.PermissionRequest // []) + [hm($repo + "/wt-agent-state blocked")] |
    .hooks.PostToolUse       = (.hooks.PostToolUse // [])       + [hm($repo + "/wt-agent-state busy")] |
    .hooks.Stop              = (.hooks.Stop // [])              + [h($repo + "/wt-agent-state idle")] |
    .hooks.SessionEnd        = (.hooks.SessionEnd // [])        + [h($repo + "/wt-agent-state end")]
' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json

# 8. Meta+1..6 -> wt switch 1..6 (KDE global shortcuts)
#    8a. free the keys MANUALLY first: System Settings -> Keyboard -> Shortcuts
#        -> Plasma -> "Activate Task Manager Entry 1..N" -> remove Meta+N -> Apply
#    8b. create launchers and bind (safe API; grant is the key code, [0] = refused):
for n in 1 2 3 4 5 6; do
  printf '[Desktop Entry]\nType=Application\nName=wt switch %d\nExec=%s/wt switch %d\nNoDisplay=true\n' \
    "$n" "$REPO" "$n" > ~/.local/share/applications/wt-switch-$n.desktop
  # register first — setShortcut on an unregistered action returns an empty grant
  gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel \
    --method org.kde.KGlobalAccel.doRegister \
    "['wt-switch-$n.desktop','_launch','wt switch $n','wt switch $n']" >/dev/null
  gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel \
    --method org.kde.KGlobalAccel.setShortcut \
    "['wt-switch-$n.desktop','_launch','wt switch $n','wt switch $n']" "[$(( 0x10000000 + 0x30 + n ))]" 4
done
# DANGER: never call setForeignShortcutKeys to evict another app's key — it
# crashed kwin_wayland (= the whole session) here. Free keys via the GUI only.
```

## Configure

Optional. `wt` sources `~/.config/wt/config` (plain shell) if it exists;
without it you get the defaults below.

```bash
cp "$REPO/config.example" ~/.config/wt/config   # then uncomment what you need
```

| Variable | Default | What |
|---|---|---|
| `WT_IDE` | `webstorm` | IDE command, run as `$WT_IDE <worktree-path>`; may carry flags |
| `WT_CHROME_PROFILE` | `Default` | Chrome `--profile-directory`. Make a dedicated profile so wt windows can't clobber your personal session-restore; directory names are in `~/.config/google-chrome/Local State` |
| `WT_URLS` | *(empty)* | extra Chrome tabs per worktree, space-separated |
| `WT_DASHBOARD_ACTIVITY` | `Work` | plain activity that gets the cloud-session card |
| `WT_WINDOW_CLASSES` | `jetbrains-webstorm org.wezfurlong.wezterm google-chrome` | window classes pinned to the new activity — change alongside `WT_IDE` |

Beyond the config file, in `wt` itself: `repo_color()` pins a hex color per
repo (fallback: hash-picked palette), and the `addWidget` block sets widget
geometry/refresh interval.

Recommended wezterm extra — fresh windows open in the current activity's
worktree. Add to `~/.wezterm.lua`:

```lua
local function wt_activity_cwd()
  local f = io.popen 'qdbus6 org.kde.ActivityManager /ActivityManager/Activities org.kde.ActivityManager.Activities.CurrentActivity 2>/dev/null'
  if not f then return nil end
  local id = f:read '*l' or ''
  f:close()
  if id == '' then return nil end
  f = io.popen("qdbus6 org.kde.ActivityManager /ActivityManager/Activities org.kde.ActivityManager.Activities.ActivityName '" .. id .. "' 2>/dev/null")
  if not f then return nil end
  local name = f:read '*l' or ''
  f:close()
  local repo, branch = name:match '^([^:]+): (.+)$'
  if not repo then return nil end
  local path = wezterm.home_dir .. '/.worktrees/' .. repo .. '/' .. branch
  if os.rename(path, path) then return path end
  return nil
end
local wt_cwd = wt_activity_cwd()
if wt_cwd then config.default_cwd = wt_cwd end
```

and override the launcher to `Exec=wezterm start --always-new-process` in a
local copy of the desktop file (`~/.local/share/applications/`) — a plain
`wezterm start` delegates to the running instance and ignores fresh config.

## Files

| File | Purpose |
|---|---|
| `wt` | main command: `add [-b]` / `remove [-f]` / `list` / `switch [n]` / `cloud` / `dashboard` (see `wt --help`) |
| `wt-status` | renders PR/CI/review/agent status: one JSON card for the widget, plain ANSI text for `wt list` and the activity description; caches in `~/.cache/wt-status/` |
| `wt-cloud` | claude.ai/code session list: `list` / `lookup <branch> [repo]` / `branch <session>` / `json` / `raw` / `refresh`; ~30s snapshot in `~/.cache/wt-status/cloud.json` |
| `config.example` | annotated template for `~/.config/wt/config` |
| `plasmoid/org.kde.wt.board/` | the Plasma 6 widget both cards render in: takes one JSON card on stdout from any command, resolves `ok/warn/error/info/dim` levels against the Plasma theme, hover rows, links, row actions |
| `wt-activity-watch` | daemon: force-refreshes status the moment you switch activities |
| `wt-tests.sh` | self-check: session-id normalization, PR-body scan, `wt-cloud` response parsing |
| `wt-agent-state` | Claude Code hook helper: records session state (busy/blocked/idle) in `$XDG_RUNTIME_DIR/wt-agents/`; wired into `~/.claude/settings.json` by install step 7 |
| `wt-activity-watch.service` | systemd user unit for the daemon (expects the step-1 symlink in `~/.local/bin`) |
| `completions/_wt` | zsh tab completion (subcommands, branches, removable worktrees) |
| `kwin/wt-activity-bind/` | KWin script: bind new windows to the current activity |

## Notes

- `add` is idempotent: re-running repairs color/widget and reuses the
  worktree/branch/activity (existing local branch is checked out; branch
  existing only on origin becomes a tracking branch, so pushes update its PR).
- `add` never invents a branch — like git, that needs `-b`. If origin cannot be
  reached the refusal says so instead of claiming the branch does not exist.
- `remove` refuses to delete unmerged branches (prints a hint instead) and
  fails loudly on uncommitted changes in the worktree.
- JetBrains IDEs write `.idea` state on shutdown and can resurrect a removed
  worktree directory; a janitor sweeps it ~30s later if `.idea` is all that's left.
- `wt-cloud` reads Claude's **private** session API (`/v1/code/sessions`) with the
  Claude CLI's OAuth token from `~/.claude/.credentials.json` — unsupported, so
  expect it to break on a field rename; all of it is confined to `fetch()` and
  `normalize()`, and `wt-tests.sh` covers the parsing. It is read-only (no
  session is started, stopped or archived), never logs or stores the token, and
  keeps the last good snapshot when a refresh fails so the widget never blanks.
  When the token expires (`wt cloud` says `auth expired`), run `claude` once.
