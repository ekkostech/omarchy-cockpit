# Changelog

## 0.2.0 — 2026-10-10
- Three-pane dashboard with worktree details, visible actions and a version label.
- Functional text search, attention/active/pinned filters, priority sorting, saved scan folders and stable selection across refreshes.
- Per-terminal focus and Ombre integration; editor, lazygit, folder and clipboard actions; visible terminals outside repositories.
- Changed files, recent commits, remote claims and latest project handoff context.
- Parallel Git scanning, accurate unavailable-state reporting and local-remote publication checks.
- Cleanup now rechecks live state and refuses dirty, active, locked, unpublished or installed-plugin worktrees. Removed force removal and unguarded prune shortcuts.
- Actual dashboard screenshots and integration tests for Qt, persistence and real Git edge cases.

## 0.1.1 — 2026-10-09
- Security: the scanner is now Python and never puts window titles or window JSON on a command line, where other local users could read them; data moves only through pipes and `/proc`. Reported by the Omarchy marketplace review. It is also three times faster.

## 0.1.0 — 2026-10-09
- First release: repos, worktrees and the agent terminals in them, in one overlay. Branch, dirty, ahead/behind and last-commit age per worktree; warnings for a branch checked out twice, two terminals on one branch, unpushed work and dirty worktrees nobody is in. Open a terminal or the default agent in a worktree, focus its terminal, remove or prune worktrees. With ekkOS Personal installed, work claims from every machine appear on their worktrees.
