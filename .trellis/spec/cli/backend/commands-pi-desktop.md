# `trellis pi-desktop` Command

> Install / inspect / remove the Trellis PI-Desktop plugin.

---

## Scope

`packages/cli/src/commands/pi-desktop/**` bridges the repository-side plugin that
`trellis init --pi-desktop` generates into PI-Desktop's own plugin store. The
platform contract lives in `platform-integration.md` → "Scenario: PI-Desktop
Host Plugin Bridge"; this page covers the command surface.

## Commands

| Command | Flags | Effect |
| --- | --- | --- |
| `trellis pi-desktop install` | `--data-dir <path>`, `--agents-dir <path>`, `--dry-run`, `--force`, `--skip-skills`, `--skip-subagents` | Copy `.pi-desktop/trellis/` into the host store, upsert the registry row, write the global sub-agents, register the repo's skills |
| `trellis pi-desktop status` | `--data-dir <path>`, `--agents-dir <path>`, `--json` | Read-only: registry row, install drift, skill counts, sub-agent count, host state |
| `trellis pi-desktop uninstall` | `--data-dir <path>`, `--agents-dir <path>`, `--dry-run`, `--force` | Remove the row, installed files, this repo's skill rows, and the marked sub-agents |

Data directory resolution: `--data-dir` → `PI_DESKTOP_DATA_DIR` → `~/.pi-desktop`.
Sub-agent home resolution: `--agents-dir` → `AGENTS_HOME` → `~/.agents`.

## What it writes

Writes stay inside the data directory plus the sub-agent home:

| Path | Content |
| --- | --- |
| `plugins/installed/local.trellis/**` | Copy of the repository plugin, synced file by file |
| `plugins/registry.json` | Exactly one row (`local.trellis`), merged into the array |
| `agent-capabilities/skills.json` | One row per **Trellis-owned** `.agents/skills/*/SKILL.md`, scoped to this repo |
| `~/.agents/subagents/trellis-{implement,check,research}.md` | The three roles in the host's shape, marked `<!-- trellis-managed: pi-desktop -->` |

Every JSON write first copies the previous file to a fixed `<file>.trellis.bak`
sibling — the next write overwrites that copy, so backups never accumulate — and
lands the new bytes with `writeFileAtomic` (`utils/atomic-write.ts`). Plugin
files and sub-agent files are compared by content and only rewritten when they
differ; files an older Trellis left behind in the install directory are deleted.
`--dry-run` performs no filesystem work while still reporting the full plan.

### Why global sub-agents

The host scans `~/.agents/subagents` only — there is no project-level sub-agent
discovery — and it validates `tools` case-sensitively (`Read`, `Glob`, `Grep`,
`BrowserPreview`, `Bash`, `Edit`, `Write`). `.pi/agents/*.md` uses the pi CLI
shape (`tools: read, …`), so a copy would fail to load with "`tools` lists no
usable tool". Each generated file therefore carries a scope guard: outside a
`.trellis/` project the role refuses to run, which keeps a global install from
affecting unrelated repositories.

## Contracts

1. **Validate before write.** The manifest (`validatePlugin`), the plugin
   registry and the skill registry are all read and checked *before* the first
   byte is written, so an unknown schema never leaves a copied plugin with no
   registry row.
2. **Schema guard.** `plugins/registry.json` and `agent-capabilities/skills.json`
   must be JSON arrays. Anything else aborts with the file left byte-identical;
   Trellis never rewrites a file it does not understand.
3. **Scope union.** The row carries `scope: { mode: "projects", projects: [...] }`.
   Installing a second repository appends to that list instead of replacing it,
   and rows/entries Trellis does not own are preserved untouched. A
   `mode: "global"` row exists only when the user made it global in the host's
   own UI: `install` writes a project scope, and a global row stays global.
4. **Idempotent.** A second `install` reports `unchanged` for the registry,
   `unchanged` for every skill, and rewrites no plugin or sub-agent file: every
   write is preceded by a content comparison.
5. **Host guard.** `install` refuses while PI-Desktop is running (the host
   rewrites `registry.json` from memory) unless `--force`. Dry runs are always
   allowed because they write nothing.
6. **Delete only our own.** `uninstall` drops the `local.trellis` row, the
   installed directory, the skill rows whose `path` is under this repository's
   `.agents/skills/`, and the sub-agent files carrying the Trellis marker. A
   hand-written skill or an unrelated `~/.agents/subagents/*.md` is never
   touched. Both registries are read before the first write, so an unreadable
   `skills.json` aborts with nothing removed; when the row is missing entirely
   (the host rewrote the file), the shared install directory and sub-agents are
   kept, because no scope list is left to prove they are unused.

## Failure messages carry the fix

| Message | Meaning |
| --- | --- |
| `No PI-Desktop plugin found at .pi-desktop/trellis/manifest.json` | Platform not configured — run `trellis init --pi-desktop` / `trellis update` |
| `must request the "agent.extension" permission` | Manifest edited by hand or stale |
| `is not a plugin registry (expected a JSON array)` | Host schema changed — inspect before forcing |
| `PI-Desktop is running` | Quit the app, or pass `--force` |

## Tests

`test/commands/pi-desktop.test.ts` covers install, idempotency, scope union,
both guards, both schema guards, dry runs, uninstall isolation and status drift.
It never touches a real `~/.pi-desktop`: every case passes an explicit
`--data-dir` and a `hostRunning` stub.
