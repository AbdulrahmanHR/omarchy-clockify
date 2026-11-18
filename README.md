# Clockify for Omarchy

A full-featured [Clockify](https://clockify.me) time tracker, analytics dashboard, and workspace controller for the [Omarchy](https://omarchy.org) bar.

<p align="center"><img src="preview.png" alt="Clockify bar pill and analytics dashboard popup showing live timer, KPI cards, daily activity bar chart, and project breakdown" width="540"></p>

## What it does

- **Live bar pill.** Shows the Clockify icon dimmed when idle, or live `H:MM:SS` elapsed time (and optional active task label) while a timer runs. Hover for task, project, elapsed time, today's total, and this week's total. Left-click opens the panel, right-click toggles start/stop, middle-click refreshes.
- **Personal API Key or Explicit Clockify Desktop Opt-In.** Store a personal API key (`0600` in `~/.config/omarchy/clockify.json` or `$CLOCKIFY_API_KEY`), or explicitly click **Use Clockify Desktop Session** to read your active Clockify Desktop access token in memory without refreshing or copying tokens to disk.
- **Full Timer & Running Entry Control.** Start, switch, stop, split (`Split`), or discard timers. Live-edit the currently running entry's description, project, task, tags, billability, start `HH:MM` (with `▲`/`▼` arrows, Up/Down keys, or wheel stepping), `±step` / `±1m` offsets, or **Stop -Xm** without stopping first.
- **Manual Time Entry, Time Steppers & Weekly Timesheet.** Switch between **Timer**, **Manual Entry** (`DateSpinField` + `TimeSpinField` with configurable minute step and one-click rounding, plus `Shift` for `±1m` and `Ctrl` for `±1h`), and **Timesheet** (7-day project matrix with daily totals and click-to-log cells). Track daily and weekly hour targets directly on the Today / Week summary cards.
- **Interactive Analytics Dashboard.** Browse `Day`, `Week`, `Month`, `Year`, `All`, or `Custom` date ranges with `‹` / `›` period stepping, configurable duration display (`Compact`, `Full`, `Decimal`), toggleable grouping of identical same-day entries (`N×` badge with expandable rows), 4 KPI cards, an interactive activity bar chart, a stacked distribution bar (`By Project`, `By Task`, `By Tag`, `By Day`), multi-filter controls, paginated date groups, and CSV export to `~/Downloads/`.
- **Workspace & Resource Management.** Filter, create, start from, archive, mark tasks Done, or delete **Projects**, **Tasks**, **Tags**, and **Clients** from the Manage tab, and switch between Clockify **Workspaces**.
- **Pomodoro & Idle Automation.** Built-in Pomodoro focus/break cycle with optional timer auto-sync (`Start` starts focus timer, `Break` stops it, `Skip` jumps phase) plus idle reminder notifications and auto-stop limits for forgotten timers.
- **Fast Caching & Parallel Sync.** Non-sensitive metadata and recent entries cache (`0600` in `~/.config/omarchy/clockify-cache.json`) gives instant startup prefill, 14-day incremental background sync, parallel `--full` fetching, and single-request mutation updates.

## Install

```bash
omarchy plugin add https://github.com/AbdulrahmanHR/omarchy-clockify --enable
```

Requires only `python3` (shipped with Omarchy) — no external Python packages or background daemons, and runs entirely in user space.

For terminal CLI access outside the bar, you can optionally symlink `clockify.py`:

```bash
ln -sf ~/.config/omarchy/plugins/io.github.abdulrahmanhr.clockify/clockify.py ~/.local/bin/clockify-ctl
```

### Updating

```bash
omarchy plugin update io.github.abdulrahmanhr.clockify
omarchy restart shell
```

## Authentication

Clockify credentials are never read automatically from Clockify Desktop without your consent:

1. **Personal API Key (recommended):** Open the panel and paste your API key from Clockify → **Preferences → Advanced → API** (stored in `~/.config/omarchy/clockify.json` with `0600` permissions), or set `$CLOCKIFY_API_KEY`.
2. **Clockify Desktop session (explicit opt-in):** Click **Use Clockify Desktop Session** (or run `./clockify.py connect-desktop`) to explicitly opt in (`"useDesktopSession": true`). When opted in, the helper reads the active access JWT from `~/.config/Clockify/Local Storage/leveldb/` strictly in memory and never refreshes or stores Desktop tokens in `clockify.json`. Click **Disconnect Desktop Session** (or run `./clockify.py clear-key`) at any time to opt back out.

## Widget Settings

Configurable in the bar settings panel or under the widget entry in `~/.config/omarchy/shell.json`:

| Key | Default | Description |
| --- | --- | --- |
| `refreshIntervalSec` | `45` | Background polling interval in seconds (`15`–`3600`) |
| `hideWhenIdle` | `false` | Hide the bar pill when no timer is running |
| `showTimerInBar` | `true` | Show live `H:MM:SS` beside the icon while timing |
| `showTaskInBar` | `false` | Include the active task/description in the bar pill |

## Shell IPC & CLI

```bash
omarchy-shell io.github.abdulrahmanhr.clockify toggle
omarchy-shell io.github.abdulrahmanhr.clockify toggleTimer
omarchy-shell io.github.abdulrahmanhr.clockify startTimer "Write docs" ""
omarchy-shell io.github.abdulrahmanhr.clockify stopTimer
omarchy-shell io.github.abdulrahmanhr.clockify discardTimer
omarchy-shell io.github.abdulrahmanhr.clockify status
omarchy-shell io.github.abdulrahmanhr.clockify debug
```

Direct CLI usage:

```bash
./clockify.py status --full | jq
./clockify.py start --description "Deep work" --project <project-id> --task <task-id> --billable
./clockify.py update-running --adjust-minutes 5
./clockify.py split-running --minutes-ago 5
./clockify.py add-manual --date today --start 09:00 --end 10:30 --description "Planning"
./clockify.py set-config --time-step-min 10 --duration-format full --daily-target-hours 8 --weekly-target-hours 40
./clockify.py export-csv --start-date 2026-11-01 --end-date 2026-11-30
```

## Tests

```bash
python3 -m unittest discover -s test -v
omarchy plugin validate .
```

## Remove

```bash
omarchy plugin disable io.github.abdulrahmanhr.clockify
omarchy plugin remove io.github.abdulrahmanhr.clockify
rm -f ~/.config/omarchy/clockify.json ~/.config/omarchy/clockify-cache.json ~/.local/bin/clockify-ctl
```

## License

MIT — see [`LICENSE`](LICENSE).
