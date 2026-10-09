# Changelog

## 0.1.1 — 2026-10-09
- Security: the scanner is now Python and never puts window titles or window JSON on a command line, where other local users could read them; data moves only through pipes and `/proc`. Reported by the Omarchy marketplace review. It is also three times faster.

## 0.1.0 — 2026-10-09
- First release: repos, worktrees and the agent terminals in them, in one overlay. Branch, dirty, ahead/behind and last-commit age per worktree; warnings for a branch checked out twice, two terminals on one branch, unpushed work and dirty worktrees nobody is in. Open a terminal or the default agent in a worktree, focus its terminal, remove or prune worktrees. With ekkOS Personal installed, work claims from every machine appear on their worktrees.
