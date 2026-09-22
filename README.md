# wt

`wt add fix/timeout` gives you:

- a git worktree at `~/.worktrees/<repo>/fix/timeout`
- a KDE Activity `<repo>: fix/timeout` — its name, icon and description are the
  only Plasma state `wt` writes; your wallpaper is yours
- wezterm, your IDE and Chrome (dedicated profile; tabs: the branch's PR,
  claude.ai/code, your `WT_URLS`) opened in the worktree and pinned to the
  activity — new windows you open there stay there, which Plasma/Wayland
  doesn't do on its own
- a status card on that desktop: what to do next, then PR / CI / reviews /
  uncommitted+unpushed / linked issues, plus what your coding agents are doing
  right now

`Meta+Tab`, KRunner, `wt switch` (fzf) or `Meta+1..6` switch branch, desktop,
windows and status all at once. `wt remove` closes the windows, removes
worktree + activity, deletes the branch only if merged. `wt list` is the same
overview in the terminal, numbered — the numbers feed `switch` and `remove`.
Command semantics, session flags, edge cases: `wt --help`.

## Status

Every surface — widget, `wt list` row, the activity's icon and description in
the `Meta+Q` switcher — leads with a verdict, "what's the next action":
`! codex needs you`, `✘ merge conflicts`, `✘ CI failing · 1/2`,
`⧗ waiting on 2 reviews`, `✔ ready to merge`, `merged — wt remove?`. Facts
follow in a fixed row skeleton: `agent` · `local` (`3 uncommitted · 2 unpushed`,
live — catches "agent finished but never pushed") · `pr` (link, state,
`+603 −2259`) · `title` · `ci` (failing check by name) · `rev` (`✔MQ37 ○alice`)
· `issues`. Refreshes instantly on activity switch, else cached — GitHub is hit
at most 1/min for the current activity, 1/10min for background ones.

## Coding agents

The card's `agent` row is live (~5s): Claude Code via hooks (`wt-agent-state`;
busy/blocked/idle), Codex hook-free (rollout write age; a wezterm pane titled
"Action Required" = blocked), Cursor hook-free (chat-dir write age, no blocked
detection). A working or blocked agent overrides the verdict — it's the
branch's current actor.

claude.ai/code cloud sessions count too: `wt cloud` lists them urgent-first
(`needs you` / `failed` / `working` / `your turn` / `done`) with branch, age,
and the session's own "where I left off" line; branches are OSC-8 links.
A worktree is tied to the session that owns its branch (auto-detected from
the live list or the PR body, or set with `--session`), giving the card a
`cloud your turn 11h` chip and Chrome that session as a tab. `wt add
<session-id|URL>` starts from the other end: checks out whatever branch the
session works on, creating it locally if the session never pushed it.
`wt dashboard` puts the session list on a desktop as a card —
`local` badge on branches you have checked out, hover button to switch or
`wt add` — and reinstalls every branch card, so it's the one command for
fixing widgets.

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
| `WT_REPOS` | *(empty)* | parent dirs searched when the repo is a bare name, space-separated — makes `wt add apify-mcp-server fix/x` work from anywhere; first hit wins |
| `WT_IDE` | `webstorm` | IDE command, run as `$WT_IDE <worktree-path>`; may carry flags |
| `WT_CHROME_PROFILE` | `Default` | Chrome `--profile-directory`. Make a dedicated profile so wt windows can't clobber your personal session-restore; directory names are in `~/.config/google-chrome/Local State` |
| `WT_URLS` | *(empty)* | extra Chrome tabs per worktree, space-separated |
| `WT_DASHBOARD_ACTIVITY` | `Work` | plain activity that gets the cloud-session card |
| `WT_WINDOW_CLASSES` | `jetbrains-webstorm org.wezfurlong.wezterm google-chrome` | window classes pinned to the new activity — change alongside `WT_IDE` |
| `WT_REPO_MARKS` | *(empty)* | pin a repo's color, `"<repo>:<color>[:<emoji>]"` space-separated — e.g. `"wt:green:🌳 apify-mcp-server:violet"`. Colors: `red orange yellow green blue violet brown grey`. Unlisted repos get a stable color from their name |
| `WT_CARD_CLOUD` | `1240 760` | cloud card size, `"<width> <height>"` px. Taller shows more sessions (the list scrolls past the bottom) |
| `WT_CARD_BRANCH` | `1000 170` | branch card size, `"<width> <height>"` px. Wider means less eliding; it's a fixed 7 rows, so extra height is blank |

Beyond the config file, in `wt` itself: the `addWidget` block sets widget
geometry/refresh interval.

`wt` does not set the desktop wallpaper. The activity name, icon and
description are the only KDE state it owns.

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

## What wt writes to KDE, and how to undo it

`wt` is a desktop tool, so it does mutate Plasma state. This is the complete
list — if it is not here, `wt` does not write it.

| What | Written by | Lands in | Undo |
|---|---|---|---|
| Activity: created, named `<repo>: <branch>`, icon `git-branch`, description = the status line | `wt add`, `wt-status`, `wt-activity-watch` | `~/.config/kactivitymanagerdrc` | `wt remove`, or `qdbus6 org.kde.ActivityManager /ActivityManager/Activities RemoveActivity <id>` |
| Current activity switched | `wt add`, `wt switch` | runtime only | switch back |
| One `org.kde.wt.board` widget on the activity's desktop, with its command + refresh interval | `install_board` (`wt add`, `wt dashboard`) | `~/.config/plasma-org.kde.plasma.desktop-appletsrc` | right-click the card → Remove Widget, or the one-liner below |
| New windows pinned to the activity: a throwaway KWin script `wt-assign-<activity-id>` | `wt add` | runtime only — self-unloads after 120s | `qdbus6 org.kde.KWin /Scripting unloadScript wt-assign-<activity-id>` |
| `wt-activity-bind` KWin script (install step 5, permanent) | you, at install | `~/.local/share/kwin/scripts/`, enabled in `~/.config/kwinrc` | System Settings → Window Management → KWin Scripts → untick |
| `Meta+1..6` launchers (install step 8, permanent) | you, at install | `~/.local/share/applications/wt-switch-*.desktop`, `~/.config/kglobalshortcutsrc` | delete those `.desktop` files, unbind in System Settings |

Remove every wt card from one activity:

```bash
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
var ds = desktopsForActivity("<activity-id>");
for (var i = 0; i < ds.length; i++) {
    var ws = ds[i].widgets("org.kde.wt.board");
    for (var j = 0; j < ws.length; j++) ws[j].remove();
}'
```

**`wt` never writes the wallpaper.** Older versions set `wallpaperPlugin =
org.kde.color` plus a per-repo color. Avoid that plugin: its `config.qml` in
plasma-workspace 6.6.5 does not declare the `configDialog` /
`wallpaperConfiguration` properties that `kcm_wallpaper` assigns
unconditionally, so **the wallpaper config UI stops opening** — from the desktop
context menu and System Settings alike — for any containment set to it. If you
are stuck there, put the containment back on an image plugin:

```bash
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
var ds = desktopsForActivity("<activity-id>");
for (var i = 0; i < ds.length; i++)
    if (ds[i].wallpaperPlugin === "org.kde.color") ds[i].wallpaperPlugin = "org.kde.image";'
```

Two more Plasma traps worth knowing, neither of them wt's doing:

- **A black desktop is usually `DynamicMode`.** In the `org.kde.image` plugin,
  `DynamicMode=2` means "only use the light image" and `3` means "only use the
  dark one" — but which image that *is* comes from a `#light` / `#dark` /
  `#day-night` fragment on the URL. Point it at a plain wallpaper package with
  no such fragment and it renders **black**. Fix: set the key back to `0`.
- **A widget keeps the geometry it was created with.** `install_board` therefore
  resizes by removing and re-adding, preserving the old position — so if a card
  sits near a screen edge, the new size gets clamped to whatever room is left,
  and repeated runs can walk it across the screen. Drag it to the top-left, or
  remove it with the snippet above, then re-run `wt dashboard`.

Config changes only take effect once Plasma reloads: `systemctl --user restart
plasma-plasmashell` (then `wt dashboard` to re-place the cards). **A logout is
never needed.** Editing `plasma-org.kde.plasma.desktop-appletsrc` by hand while
plasmashell is running does not work — it rewrites the file on exit and your
edit is lost. Go through the scripting API, as above.

## Notes

- `add` is idempotent: re-running repairs the widget and reuses the
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
