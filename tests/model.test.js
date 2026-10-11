// Run with: node --test tests/*.test.js
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs"); const path = require("node:path"); const vm = require("node:vm");
const src = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(/^\.pragma library\s*/, "");
const M = {}; vm.runInNewContext(src + "\nM.build = build; M.matches = matches; M.ago = ago; M.parseClaims = parseClaims; M.visible = visible; M.summary = summary; M.cleanupReason = cleanupReason; M.selectedIndex = selectedIndex; M.scope = scope;", { M, JSON, Math, Date });

const scan = JSON.stringify({ now: 1000000, repos: [
  { path: "/h/p/app", name: "app", remote: "x", worktrees: [
    { path: "/h/p/app", branch: "main", head: "abc", dirty: 0, ahead: 0, behind: 0, lastCommit: 999000, main: true },
    { path: "/h/p/.wt/app/a1", branch: "agent/a1", head: "def", dirty: 3, ahead: 2, behind: 0, lastCommit: 990000, main: false },
    { path: "/h/p/.wt/app/a2", branch: "agent/a1", head: "def", dirty: 0, ahead: 0, behind: 0, lastCommit: 990000, main: false } ] } ],
  terminals: [
    { address: "0x1", pty: "pts/1", title: "◐ fixing", agent: "working", cwd: "/h/p/.wt/app/a1/src" },
    { address: "0x2", pty: "pts/2", title: "✳ done", agent: "idle", cwd: "/h/p/app" },
    { address: "0x3", pty: "pts/3", title: "zsh", agent: "other", cwd: "/tmp" } ] });
const claims = JSON.stringify({ claims: [
  { id: "c1", project: "app", agent: "codex", device: "here", state: "active", stale: true, branch: "agent/a1", worktree: "/h/p/.wt/app/a1", task: "t", updated: 5, head: "d", pushed_head: "" },
  { id: "c2", project: "app", agent: "claude", device: "mac", state: "active", stale: false, branch: "agent/zz", worktree: "/V/.wt/app/zz", task: "t", updated: 6, head: "d", pushed_head: "d" } ] });

test("terminals land in the deepest worktree and claims attach by path", () => {
  const r = M.build(scan, claims, "here").repos[0];
  const a1 = r.worktrees.find((w) => w.branch === "agent/a1" && w.path.endsWith("a1"));
  assert.equal(a1.terminals.length, 1);
  assert.equal(a1.claim.id, "c1");
  assert.ok(a1.warnings.includes("stale claim"));
  assert.ok(a1.warnings.includes("2 unpushed"));
  assert.equal(r.worktrees[0].main, true, "main worktree sorts first");
});

test("repo-level warnings: duplicate branch and remote claims", () => {
  const r = M.build(scan, claims, "here").repos[0];
  assert.ok(r.warnings.some((w) => w.startsWith("branch agent/a1 checked out 2")));
  assert.ok(r.warnings.some((w) => w.includes("claim on mac (claude)")));
  assert.equal(r.remoteClaims.length, 1);
  assert.equal(r.working, true);
});

test("path-scoped claims say what they cover", () => {
  const scoped = JSON.stringify({ claims: [
    { id: "c3", project: "app", agent: "codex", device: "laptop", state: "active", stale: false, branch: "agent/ios", worktree: "/L/.wt/app/ios", task: "t", updated: 7, head: "d", pushed_head: "d", paths: ["ios", "shared/api.ts", 5] } ] });
  const r = M.build(scan, scoped, "here").repos[0];
  assert.deepEqual(r.remoteClaims[0].paths, ["ios", "shared/api.ts"]);
  assert.ok(r.warnings.includes("claim on laptop (codex · ios, shared/api.ts)"));
  assert.equal(M.scope(M.parseClaims(claims, "here")[0]), "whole project");
});

test("terminals outside any repo are reported as unplaced", () => {
  const b = M.build(scan, claims, "here");
  assert.deepEqual([...b.unplaced.map((t) => t.pty)], ["pts/3"]);
});

test("works without ekkOS and survives bad input", () => {
  assert.equal(M.build(scan, "", "").repos[0].remoteClaims.length, 0);
  assert.equal(M.build("not json", "{", "").repos.length, 0);
  assert.equal(M.parseClaims("nope").length, 0);
});

test("filter matches repo, branch or terminal title; ago formats", () => {
  const r = M.build(scan, "", "").repos[0];
  assert.equal(M.matches(r, "fixing"), true);
  assert.equal(M.matches(r, "agent/a1"), true);
  assert.equal(M.matches(r, "zzz"), false);
  assert.equal(M.ago(90), "1m"); assert.equal(M.ago(7200), "2h"); assert.equal(M.ago(3 * 86400), "3d");
});

test("filters combine words, attention includes worktree warnings, and pins sort first",()=>{
 const b=M.build(scan,claims,"here");
 assert.equal(M.visible(b.repos,"app fixing","attention",[],"attention").length,1);
 assert.equal(M.visible(b.repos,"app missing","all",[],"name").length,0);
 assert.equal(M.visible(b.repos,"","pinned",[],"name").length,0);
 assert.equal(M.visible(b.repos,"","pinned",["/h/p/app"],"name").length,1);
 assert.equal(M.summary(b.repos).waiting,1);
 assert.equal(M.selectedIndex([{path:"b"},{path:"a"}],"a"),1);
 assert.equal(M.selectedIndex([],"a"),-1);
 assert.equal(M.cleanupReason(b.repos[0].worktrees[0]),"Main checkout");
});
test("Git branch names matching object keys cannot corrupt branch grouping",()=>{
 const value=JSON.parse(scan);value.repos[0].worktrees.forEach(w=>w.branch="constructor");
 assert.equal(M.build(JSON.stringify(value),"","").repos.length,1);
});
