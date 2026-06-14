# coralline

> A [Powerlevel10k](https://github.com/romkatv/powerlevel10k)-inspired statusline for Claude
> Code that **installs itself through your AI** — paste one prompt, answer a few questions
> about colors and layout, done.

[繁體中文說明](./README.zh-TW.md)

![All six coralline themes rendered side by side](./assets/hero.png)

## Install (the fun way)

Paste this into Claude Code:

```text
Please install coralline for me:
fetch https://raw.githubusercontent.com/Nanako0129/coralline/main/INSTALL.md
and follow the playbook in it.
```

Claude will ask you to pick a theme (with previews), choose which segments you want, decide
between a one-line or two-line layout, then wire everything up and verify it. No manual
config editing required.

## What you get

```text
╭ ~/side-project/coralline  ⎇ main+!  ◆ Fable 5  ⬡ ▰▰▰▱▱ 62% ↑1.2M ↓45.6k  5h ▰▰▱▱▱ 41% ↺2h44m  $1.23  ⊙ 02:45 pm ╮
```

| Segment | Shows |
|---|---|
| `dir` | current directory, long paths collapsed to `~/a/…/z` |
| `project` | repo name (`⬢`), stable across every worktree; hidden outside a git repo |
| `git` | branch, staged `+` / modified `!` / untracked `?`, ahead `⇡` behind `⇣` |
| `model` | active Claude model |
| `ctx` | context-window gauge, input/output/cache token counts |
| `limit5h` / `limit7d` | rate-limit gauges with reset countdown |
| `limit7ds` / `limit7do` | per-model 7-day rate-limit gauges (Sonnet / Opus), when present |
| `cost` | session cost in USD |
| `clock` | time, 12h or 24h |
| `lines` | lines added/removed this session |
| `style` | active output style |
| `duration` | session wall-clock duration |
| `stash` | git stash count |
| `sha` | short commit hash (`@2b97af9`) — free, from the same `git status` |
| `conflicts` | unmerged-path count (`⚠`) — free, from the same `git status` |
| `effort` | thinking effort level (`✲ high`), when set |
| `cache` | prompt-cache hit rate (`↯`) from token counts already on stdin |
| `vim` | vim mode (`⌨ NORMAL`), when vim mode is on |
| `worktree` | Claude Code worktree name + branch (`⧉`), when in one |
| `version` | Claude Code CLI version |
| `session` | short session id (`#abcd1234`) |
| `custom` | first line of `VL_CUSTOM_CMD`'s output |

Gauges change color as they fill: green → yellow at 50% → red at 75% (thresholds configurable).

The `effort`, `cache`, `vim`, `worktree`, `version`, `session`, `sha`, and `conflicts` segments
all read data Claude Code already pipes in (or that's already in the single `git status` call) —
so they cost no extra subprocess, and hide themselves when their data isn't present.

## Why it's fast

The statusline is just a local shell script: it makes no network or API calls and uses zero
tokens. Claude Code pipes the session JSON to it on stdin and renders whatever it prints.

It runs every second (`refreshInterval: 1`), so the script is built to be cheap on CPU: one
`jq` invocation extracts every field at once, and one `git status --porcelain=v2 --branch`
call provides branch, dirty state, and ahead/behind together. No `bc`, no per-field subprocess
spam. Works on stock macOS bash 3.2 and any Linux bash.

## Manual install

```bash
git clone https://github.com/Nanako0129/coralline ~/.claude/coralline-src
mkdir -p ~/.claude/coralline/themes
cp ~/.claude/coralline-src/statusline.sh ~/.claude/coralline/
cp ~/.claude/coralline-src/themes/claude-coral.conf ~/.claude/coralline/themes/
```

Then add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/coralline/statusline.sh",
    "refreshInterval": 1
  }
}
```

> **Note:** requires `jq` and a [Nerd Font](https://www.nerdfonts.com/) terminal.
> No Nerd Font? Set `VL_ASCII=1` in your config for a glyph-free rendering.

### Verify your setup

Run the script with `--doctor` to check your config without waiting for Claude Code to feed
it a session — it reports the config it loaded, whether `jq` is present, flags any unknown
segment names, and prints a sample bar:

```bash
bash ~/.claude/coralline/statusline.sh --doctor
```

### Warp terminal

coralline renders cleanly in [Warp](https://www.warp.dev/) — it supports true-color and Nerd
Font powerline glyphs out of the box. Two things to set:

- **Font:** Settings → Appearance → Text → pick a Nerd Font (e.g. *MesloLGS Nerd Font*), so the
  pill caps and segment glyphs render. Without one, set `VL_ASCII=1`.
- **Theme:** the bundled [`warp` theme](./themes/warp.conf) is tuned to Warp's default dark
  palette — source it from your `coralline.conf` to match.

The responsive `auto` layout reacts to window resizing in Warp the same as any terminal: Claude
Code sets `COLUMNS` before each render, and coralline wraps to fit.

## Configuration

Everything lives in `~/.claude/coralline.conf` (plain bash, sourced by the script):

| Variable | Default | Meaning |
|---|---|---|
| `VL_STYLE` | `pill` | `pill`: powerline pills · `lean`: flat colored text, p10k-lean style |
| `VL_LAYOUT` | `fixed` | `fixed`: one line per `VL_SEGMENTS*` var · `auto`: responsive |
| `VL_MAX_LINES` | `3` | `auto` only — wrap into at most this many lines (`1` = never wrap) |
| `VL_WRAP_MARGIN` | `4` | `auto` only — columns kept free on the right so segments never touch the edge |
| `VL_SEGMENTS` | `dir git model ctx limit5h limit7d cost clock` | segments on line 1, in order (the full list in `auto` mode) |
| `VL_SEGMENTS2` / `VL_SEGMENTS3` | _(empty)_ | `fixed` only — optional second/third line |
| `VL_CLOCK` | `12h` | `12h` / `24h` / `off` |
| `VL_CLOCK_SECONDS` | `1` | show seconds in the clock |
| `VL_BAR_WIDTH` | `5` | gauge width in cells |
| `VL_PATH_DEPTH` | `4` | collapse paths deeper than this |
| `VL_NAME_MAX` | `0` | max chars for the `dir` leaf / `project` / `git` / `worktree` names before `…` truncation (`0` = off) |
| `VL_CTX_TOKENS` | `full` | `ctx` token detail: `full` (↑↓ + cache) · `io` (↑↓ only) · `off` |
| `VL_COST_DECIMALS` | `2` | decimal places for the cost segment |
| `VL_WARN_PCT` / `VL_HOT_PCT` | `50` / `75` | gauge color thresholds |
| `VL_GIT_CACHE` | `0` | reuse `git status` for this many seconds (helps huge repos at `refreshInterval: 1`); `0` = always live |
| `VL_LIMIT_RESET` | `countdown` | limit-gauge reset display: `countdown` · `clock` (absolute time) · `both` |
| `VL_GIT_LINK` | `0` | `1` = OSC 8 hyperlink the git branch to its GitHub page (needs a terminal that passes OSC 8 through) |
| `VL_CUSTOM_CMD` | _(empty)_ | shell command for the `custom` segment (first line of stdout is shown) |
| `VL_CUSTOM_TIMEOUT` | `1` | seconds before the custom command is killed (when `timeout`/`gtimeout` is available) |
| `VL_ASCII` | `0` | `1` disables Nerd Font glyphs |
| `VL_BG_*` / `VL_FG_*` | theme | colors — `256`-color index or `"R,G,B"` |

### Responsive layout

With `VL_LAYOUT="auto"` the bar stays on a single line while it fits, and greedily wraps into
up to `VL_MAX_LINES` rows when the window gets narrow. Once the line cap is reached, remaining
segments overflow on the last line. `VL_WRAP_MARGIN` keeps a few columns free on the right so
wrapped lines never butt against the window edge — raise it if your terminal adds padding.

Width comes from `$COLUMNS`. Claude Code v2.1.153+ sets `COLUMNS` to the current terminal width
before running the status line, so wrapping responds to window resizing out of the box. Outside
Claude Code the script falls back to `stty size` on the controlling terminal; if neither is
available it stays on one line.

```text
wide window:    ~/dev/app  ⎇ main  ◆ Fable 5  ⬡ ▰▰▰▱▱ 62%  5h ▰▰▱▱▱ 41%  $1.23  ⊙ 14:45

narrow window:  ~/dev/app  ⎇ main  ◆ Fable 5
                ⬡ ▰▰▰▱▱ 62%  5h ▰▰▱▱▱ 41%  $1.23  ⊙ 14:45
```

Prefer a layout that never moves? Keep `VL_LAYOUT="fixed"` and pin rows with
`VL_SEGMENTS` / `VL_SEGMENTS2` / `VL_SEGMENTS3`.

### Lean style

Prefer Powerlevel10k's *lean* look — no backgrounds, just colored text? Set
`VL_STYLE="lean"` and each segment's `VL_BG_*` color becomes its text accent instead:

![Lean style compared with pill style](./assets/style-lean.png)

| Variable | Default | Meaning |
|---|---|---|
| `VL_STYLE` | `pill` | set to `lean` for the flat look |
| `VL_LEAN_SEP` | _(empty)_ | extra text between segments, e.g. `·` |
| `VL_LEAN_FG` | _(empty)_ | force a text color; empty = inherit each segment's accent |

> **Tip:** already a p10k user? Tell the AI installer to import your `~/.p10k.zsh` — it will
> carry over your style, colors, and time format. See the
> [Powerlevel10k import step in INSTALL.md](./INSTALL.md#step-25--powerlevel10k-import-optional).

## Themes

| | |
|---|---|
| **`claude-coral`** — steel blue · mauve · Claude coral (default)<br>![claude-coral theme preview](./assets/theme-claude-coral.png) | **`catppuccin-mocha`** — soft pastels on dark<br>![catppuccin-mocha theme preview](./assets/theme-catppuccin-mocha.png) |
| **`nord`** — arctic frost<br>![nord theme preview](./assets/theme-nord.png) | **`gruvbox-dark`** — warm retro<br>![gruvbox-dark theme preview](./assets/theme-gruvbox-dark.png) |
| **`tokyo-night`** — neon on deep navy<br>![tokyo-night theme preview](./assets/theme-tokyo-night.png) | **`mono`** — grayscale minimalism<br>![mono theme preview](./assets/theme-mono.png) |
| **`warp`** — tuned to Warp's default dark theme<br>![warp theme preview](./assets/theme-warp.png) | |

A theme is just a `.conf` file assigning `VL_BG_*` / `VL_FG_*` — copy one, change the colors,
and source yours from `coralline.conf` instead. PRs with new themes are welcome.

> **Tip:** the preview images are generated from the real script by
> [`tools/render-screenshots.py`](./tools/render-screenshots.py) — after adding a theme, add it
> to the `THEMES` list there and re-run it to get a matching preview.

## Acknowledgements

The visual language of coralline — segmented pills, powerline transitions, the `⇡⇣` git
glyphs, gauges that shift color as they fill — is a loving tribute to
[Powerlevel10k](https://github.com/romkatv/powerlevel10k) by
[@romkatv](https://github.com/romkatv), which set the bar for what a fast, beautiful prompt
can be. Thanks also to the wider [powerline](https://github.com/powerline/powerline) lineage
that started it all, and to [Nerd Fonts](https://www.nerdfonts.com/) for the glyphs that make
the pill shapes possible.

As for the name: coralline algae build reefs one thin, colorful layer at a time —
and **coral·line** is exactly what this is: a line, in Claude's coral.

## License

[MIT](./LICENSE)
