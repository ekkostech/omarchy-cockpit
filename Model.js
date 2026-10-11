.pragma library

// Cockpit's picture of the desktop: repos → worktrees → the terminals working
// in them, plus (optionally) ekkOS work claims from every machine.

function basename(p) { var s = String(p || "").replace(/\/+$/, ""); return s.slice(s.lastIndexOf("/") + 1); }

function inside(path, dir) {
  if (!path || !dir) return false;
  dir = String(dir).replace(/\/+$/, "");
  return path === dir || path.indexOf(dir + "/") === 0;
}

function ago(seconds) {
  if (!isFinite(seconds) || seconds < 0) return "";
  if (seconds < 60) return "just now";
  if (seconds < 3600) return Math.floor(seconds / 60) + "m";
  if (seconds < 86400) return Math.floor(seconds / 3600) + "h";
  return Math.floor(seconds / 86400) + "d";
}

// ekkOS claim records (from `ekkos-personal work status`), kept as data.
function parseClaims(text, thisDevice) {
  var out = [];
  try {
    var j = JSON.parse(text);
    (j.claims || []).forEach(function (c) {
      if (!c || typeof c !== "object") return;
      out.push({
        id: String(c.id || ""), project: String(c.project || ""), agent: String(c.agent || ""),
        device: String(c.device || ""), local: !!thisDevice && c.device === thisDevice,
        state: String(c.state || ""), stale: c.stale === true, branch: String(c.branch || ""),
        worktree: String(c.worktree || "").replace(/\/+$/, ""), task: String(c.task || ""),
        updated: Number(c.updated) || 0, pushed: !!c.pushed_head && c.pushed_head === c.head,
        // ekkOS 1.14: a claim may cover only some paths; none means the whole project.
        paths: Array.isArray(c.paths) ? c.paths.filter(function (p) { return typeof p === "string"; }).slice(0, 24) : []
      });
    });
  } catch (e) { }
  return out;
}

// One worktree row for the UI, with the terminals inside it and its claim.
// What a claim covers, in words.
function scope(claim) {
  return claim && claim.paths && claim.paths.length ? claim.paths.join(", ") : "whole project";
}

function buildWorktree(wt, repo, terminals, claims, now) {
  var terms = terminals.filter(function (t) { return inside(t.cwd, wt.path); });
  // The deepest worktree wins: a terminal in a nested worktree is not in the outer one.
  terms = terms.filter(function (t) {
    return !repo.worktrees.some(function (o) { return o.path !== wt.path && inside(o.path, wt.path) && inside(t.cwd, o.path); });
  });
  var claim = null;
  claims.forEach(function (c) {
    if (c.local && c.worktree === wt.path && (!claim || c.updated > claim.updated)) claim = c;
  });
  var warnings = [];
  if (claim && claim.state === "active" && claim.stale) warnings.push("stale claim");
  if (wt.ahead > 0) warnings.push(wt.ahead + " unpushed");
  if (wt.statusKnown === false) warnings.push("Git status unavailable");
  if (wt.locked) warnings.push("locked worktree");
  if (!wt.upstream && wt.published === false) warnings.push("no known remote copy");
  if (wt.dirty > 0 && terms.length === 0 && !wt.main) warnings.push("dirty, nobody in it");
  return Object.assign({}, wt, {
    name: wt.main ? basename(wt.path) : basename(wt.path),
    terminals: terms, claim: claim, warnings: warnings,
    working: terms.some(function (t) { return t.agent === "working"; }),
    waiting: terms.some(function (t) { return t.agent === "idle"; }),
    age: ago(now - (wt.lastCommit || now))
  });
}

function buildRepo(repo, terminals, claims, now) {
  var wts = repo.worktrees.map(function (w) { return buildWorktree(w, repo, terminals, claims, now); });
  // Same branch checked out in two places, or two terminals on one branch.
  var byBranch = Object.create(null);
  wts.forEach(function (w) { if (w.branch) { (byBranch[w.branch] = byBranch[w.branch] || []).push(w); } });
  var warnings = [];
  Object.keys(byBranch).forEach(function (b) {
    var places = byBranch[b];
    var busy = places.reduce(function (n, w) { return n + w.terminals.length; }, 0);
    if (places.length > 1) warnings.push("branch " + b + " checked out " + places.length + " times");
    else if (busy > 1) warnings.push(busy + " terminals on " + b);
  });
  var name = basename(repo.path);
  var remote = claims.filter(function (c) {
    return !c.local && c.state === "active" && (c.project === name || inside(c.worktree, repo.path));
  });
  remote.forEach(function (c) { warnings.push((c.stale ? "stale " : "") + "claim on " + (c.device.split(":")[0] || "another machine") + " (" + c.agent + (c.paths.length ? " · " + scope(c) : "") + ")"); });
  wts.sort(function (a, b) { return (b.main - a.main) || (b.terminals.length - a.terminals.length) || (b.lastCommit || 0) - (a.lastCommit || 0); });
  return Object.assign({}, repo, {
    name: name, worktrees: wts, remoteClaims: remote, warnings: warnings,
    dirty: wts.reduce(function (n, w) { return n + (w.dirty || 0); }, 0),
    terminals: wts.reduce(function (n, w) { return n + w.terminals.length; }, 0),
    working: wts.some(function (w) { return w.working; }),
    waiting: wts.some(function (w) { return w.waiting; })
  });
}

function build(scanText, claimsText, thisDevice) {
  var scan;
  try { scan = JSON.parse(scanText); } catch (e) { return { repos: [], terminals: [], unplaced: [], claims: [] }; }
  var now = Number(scan.now) || Math.floor(Date.now() / 1000);
  var terminals = Array.isArray(scan.terminals) ? scan.terminals : [];
  var claims = parseClaims(claimsText || "", thisDevice);
  var repos = (Array.isArray(scan.repos) ? scan.repos : []).map(function (r) { return buildRepo(r, terminals, claims, now); });
  repos.sort(function (a, b) { return (b.working - a.working) || (b.waiting - a.waiting) || (b.terminals - a.terminals) || a.name.localeCompare(b.name); });
  var placed = {};
  repos.forEach(function (r) { r.worktrees.forEach(function (w) { w.terminals.forEach(function (t) { placed[t.address] = true; }); }); });
  return {
    now: now, repos: repos, terminals: terminals, claims: claims,
    unplaced: terminals.filter(function (t) { return !placed[t.address]; })
  };
}

function matches(repo, filter) {
  var words = String(filter || "").toLowerCase().trim().split(/\s+/).filter(Boolean);
  var haystack = [repo.name, repo.path].concat(repo.worktrees.map(function(w) {
    return [w.branch, w.path, w.claim ? w.claim.task : ""].concat(w.terminals.map(function(t) { return t.title + " " + t.workspace; })).join(" ");
  })).join(" ").toLowerCase();
  return words.every(function(w) { return haystack.indexOf(w) >= 0; });
}
function attention(repo) {
  return !!repo.error || repo.waiting || repo.dirty > 0 || repo.warnings.length > 0 || repo.worktrees.some(function(w) { return w.warnings.length > 0 || w.behind > 0; });
}
function visible(repos, query, mode, pins, sort) {
  var out = repos.filter(function(r) {
    if (!matches(r, query)) return false;
    if (mode === "attention") return attention(r);
    if (mode === "active") return r.terminals > 0 || r.worktrees.some(function(w) { return w.claim && w.claim.state === "active"; }) || r.remoteClaims.length > 0;
    if (mode === "pinned") return pins.indexOf(r.path) >= 0;
    return true;
  });
  return out.slice().sort(function(a,b) {
    var pin = (pins.indexOf(b.path) >= 0) - (pins.indexOf(a.path) >= 0);
    if(pin) return pin;
    if(sort === "name") return a.name.localeCompare(b.name);
    return (b.waiting-a.waiting) || (attention(b)-attention(a)) || (b.working-a.working) || (b.terminals-a.terminals) || a.name.localeCompare(b.name);
  });
}
function selectedIndex(list, path) {
  for(var i=0;i<list.length;i++) if(list[i].path===path) return i;
  return list.length ? 0 : -1;
}
function summary(repos) {
  var result={repos:repos.length,worktrees:0,terminals:0,working:0,waiting:0,attention:0};
  repos.forEach(function(r){ result.worktrees+=r.worktrees.length;result.terminals+=r.terminals;result.attention+=attention(r)?1:0;
    r.worktrees.forEach(function(w){w.terminals.forEach(function(t){result.working+=t.agent==="working"?1:0;result.waiting+=t.agent==="idle"?1:0;});});});
  return result;
}
function cleanupReason(w) {
  if(!w) return "Choose a worktree.";
  if(w.main) return "Main checkout";
  if(w.locked) return "Locked worktree";
  if(w.statusKnown===false) return "Git status unavailable";
  if(w.dirty>0) return "Uncommitted changes";
  if(w.terminals.length) return "Terminal still using it";
  if(w.claim && w.claim.state==="active") return "Active agent claim";
  if(w.ahead>0 || w.published===false) return "No known remote copy";
  return "";
}
