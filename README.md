# Cockpit

Every repo, worktree and agent terminal on your desktop, in one keyboard-driven overlay for [Omarchy](https://omarchy.org).

When several coding agents run at once, each in its own worktree, it gets hard to know what is where: which branch each terminal is on, which worktrees have uncommitted or unpushed work, which ones were abandoned, and whether two agents are quietly editing the same branch. Cockpit answers that at a glance.

## What it shows

- **Repos** found under `~/Projects`, `~/code`, `~/src`, `~/dev` and `~/Work` (three levels deep), plus any repo a terminal is currently in.
- **Worktrees** of the selected repo: branch, short head, last-commit age, uncommitted changes, commits ahead/behind upstream, and the terminals working inside each one with their agent state (◐ working, ✳ waiting for you).
- **Warnings**: a branch checked out in two worktrees, two terminals on one branch, unpushed commits, dirty worktrees with nobody in them, and stale work claims.
- **ekkOS claims** (optional): with [ekkOS Personal](https://github.com/ekkostech) installed, each worktree shows its work claim (agent, state, age, task), and claims held on *other machines* appear as repo warnings.

Terminals are matched to worktrees by their shell's working folder, the same way Ombre does it.

## Install

```bash
omarchy plugin add https://github.com/ekkostech/omarchy-cockpit.git --enable --yes
omarchy restart shell
```

Then bind a key, in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + C", "Cockpit", "omarchy-shell shell toggle ekkostech.cockpit '{}'")
```

## Keys

| Key | Action |
|-----|--------|
| `↑`/`↓`, `j`/`k` | Move in the current pane |
| `Tab`, `←`/`→`, `h`/`l` | Switch between the repo and worktree panes |
| `Enter` / `T` | Open a terminal in the selected worktree |
| `A` | Start your default agent (`omarchy default agent`) in it |
| `F` | Focus the terminal already working in it |
| `X` | Remove the selected worktree (asks once; `Shift+X` for a dirty one) |
| `P` | Prune stale worktree entries for the repo |
| `R` | Refresh (it also refreshes itself every 5 s while open) |
| `/` then letters | Filter by repo, branch or terminal title; `Esc` clears |
| `Esc` | Close |

Mouse works too: click a repo or a worktree to select it.

## Scripting

`bin/cockpit-scan` prints everything Cockpit knows as JSON (`repos`, `terminals`), for your own scripts:

```bash
~/.config/omarchy/plugins/ekkostech.cockpit/bin/cockpit-scan --root ~/work | jq '.repos[].name'
```

## Requirements

Omarchy 4 (Quickshell shell), `git`, `python3`. ekkOS Personal is optional.

## Development

```bash
node --test tests/*.test.js
omarchy plugin validate .
```

## Uninstall

```bash
omarchy plugin remove ekkostech.cockpit
```

## License

MIT
