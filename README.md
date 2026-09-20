# Localhost HQ

A native macOS control center for every development server listening on localhost.

Open it and your local environment is already there: what is running, on which port, from which
project, on which branch, and what it costs in CPU and memory. No configuration, no registration
step, no per-project setup.

Part 1 (discovery) is implemented. Parts 2 and 3 are not.

---

## What it does

- Discovers every TCP socket in `LISTEN` state, de-duplicating dual-stack (IPv4 + IPv6) listeners
- Maps each port to its owning process: executable, full `argv`, parent, start time
- Resolves the process's working directory, and from it the package root and repository root
  (kept distinct — a monorepo service reports `apps/web` *and* `dicee`)
- Names the service from its manifest (`@dicee/web` → **web**), falling back to directory, then process
- Detects framework and runtime heuristically, with a confidence score
- Reads Git repository root and current branch (including detached HEAD)
- Samples CPU, resident memory and uptime
- Groups services by repository; loose dev servers and infrastructure get their own sections
- Separates macOS/app daemons from your own work, hidden behind a toggle
- Menu bar item with a live count and a compact summary
- Search across project, service, framework, port, path, branch and PID
- Open in Browser / Reveal in Finder / Open in Terminal
- Refreshes every 2 seconds

### Not in Part 1

Logs, killing or restarting processes, starting projects, saved environments, Docker management,
request inspection, historical analytics, remote machines. The architecture leaves room for them;
none of it is stubbed or faked.

---

## Requirements

- macOS 14 or later
- Xcode 16 or later to build (developed against Xcode 27)

---

## Build and run

```bash
open LocalhostHQ.xcodeproj      # then Run
```

or from the command line:

```bash
xcodebuild -scheme LocalhostHQ -destination 'platform=macOS' build
xcodebuild -scheme LocalhostHQ -destination 'platform=macOS' test
```

If `xcodebuild` reports that it requires Xcode, point it at a full install:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

### The app icon

The icon is generated from code rather than checked in as opaque artwork:

```bash
swift Tools/GenerateAppIcon.swift LocalhostHQ/Assets.xcassets/AppIcon.appiconset
```

It renders **full-bleed** artwork. Modern macOS applies its own icon shape and shadow, so artwork
that bakes in its own squircle and transparent margin gets nested inside the system container and
renders as a small tile on a dark square. `Views/HubMark.swift` mirrors the same geometry as a
SwiftUI `Canvas`, so the menu bar glyph and in-app badge match the icon.

---

## Permissions

**No root, no `sudo`, no Full Disk Access.**

The one non-default requirement is that **App Sandbox is disabled** (`ENABLE_APP_SANDBOX = NO`).
This is not incidental — a sandboxed app cannot spawn `lsof`, cannot call `proc_pidinfo` on other
processes, and cannot read project directories outside its container. Discovery is impossible under
the sandbox.

Within those bounds the app is read-only: it inspects processes and reads manifest files. It never
writes to your projects and never signals a process.

Processes owned by other users (root daemons such as a system Postgres) deny `proc_pidpath`,
`proc_pidinfo` and `KERN_PROCARGS2` with `EPERM`. That is expected and handled: the service still
appears with whatever the kernel does surrender, and the inspector marks it *limited access*.

---

## Architecture

```
Discovery/          how facts are obtained
  PortScanner            lsof -F → listening sockets
  LsofFieldParser        pure parser + de-duplication
  ProcessInspector       libproc / sysctl
  ProjectDetector        upward walk → package root + repo root
  ManifestLoader         package.json, pyproject.toml, Cargo.toml, go.mod, …
  FrameworkDetector      scores signatures, returns a ranking
  FrameworkCatalog       the signature knowledge base
  GitInspector           git rev-parse
  MetricsCollector       CPU rate from rusage deltas
  ServiceOriginClassifier   developer vs. system

Services/           composition
  LocalhostDiscoveryService   the pipeline, an actor
  ServiceGrouper              repository / dev / infrastructure sections
  ServiceFilter               search
  ServiceActions              browser, Finder, Terminal

Stores/ServicesStore          @MainActor @Observable, owns the refresh loop
Models/                       value types, all Sendable
Views/                        SwiftUI, no discovery logic
```

The pipeline:

```
listening socket → process → cwd → project → framework → git → metrics → LocalService
```

`LocalhostDiscoveryService` is an `actor`, so overlapping refreshes cannot race on its caches.
Views never touch it directly; `ServicesStore` is the only caller and the only `@MainActor` state.

### Discovery strategy

`lsof -nP -w +c 0 -F pcfntP -iTCP -sTCP:LISTEN`, parsed in **field mode**.

macOS exposes no public API to enumerate another process's sockets.
`proc_pidinfo(PROC_PIDLISTFDS)` works only for processes you can already inspect and would require
walking every PID on the system. `lsof` does that walk in one shot in about 40 ms, which is both
more reliable and cheaper.

Field output (`-F`) is used instead of the human-readable table so that nothing depends on column
alignment, and `+c 0` stops lsof truncating command names at 9 characters. Process names containing
spaces (`Code Helper (Plugin)`) parse correctly as a result. Malformed rows are skipped
individually rather than failing the scan.

Process metadata comes from direct syscalls, never subprocesses:

| Fact | API |
| --- | --- |
| Executable path | `proc_pidpath` |
| Working directory | `proc_pidinfo(PROC_PIDVNODEPATHINFO)` |
| CPU time, resident memory | `proc_pid_rusage(RUSAGE_INFO_V4)` |
| Parent, start time, short name | `sysctl(KERN_PROC_PID)` → `kinfo_proc` |
| Full `argv` | `sysctl(KERN_PROCARGS2)` |

The environment block that follows `argv` in `KERN_PROCARGS2` is deliberately **not** read; it
routinely contains secrets.

### Cost model

A refresh is split by expense:

- **Every 2 s** — one `lsof`, then pure syscalls per PID for CPU and memory
- **Once per process** — cwd, project walk, manifest parsing, framework detection; cached by
  service identity and invalidated if the PID's start time changes (PID reuse protection)
- **Every 20 s at most** — `git rev-parse`, cached per repository root

In the steady state a tick is one subprocess and a handful of syscalls. Measured at 16 services:
**~43 ms per full refresh**.

### CPU convention

`cpuPercent` is the share of **one** core, averaged between the two most recent samples. A process
saturating four cores reports ≈400%. The value is never clamped to 100.

It is `nil` until a second sample exists — a rate needs two points, and reporting a since-launch
average would badly misrepresent a server that was busy starting up and is idle now.

### Framework detection

A framework is described by a `FrameworkSignature`: a set of weighted `DetectionRule`s over a pure
`DetectionContext` (process name, own and parent `argv`, executable, port, manifest dependencies,
marker files). Matching rules combine as independent evidence (noisy-OR, `1 - Π(1 - wᵢ)`), capped
at 0.99. The strongest signature wins.

Adding a framework means adding one entry to `FrameworkCatalog` — no other file changes.

Two details that matter in practice:

- **Parent `argv` is a signal.** Next.js rewrites its worker's process title to
  `next-server (v15.0.3)`, and `npm run dev` wrappers leave the real command only on the parent.
  Without the parent's command line, a large share of real dev servers are unidentifiable.
- **Ports are corroborating only.** A port rule can strengthen a detection but never establish one,
  so an unknown process on :5432 is not labelled PostgreSQL.

Supported: Next.js, Nuxt, SvelteKit, Astro, Remix, Vite, React dev server (via `react-scripts`),
NestJS, Hono, Express, Bun, Deno, generic Node; Django, Flask, FastAPI, Uvicorn, Jupyter, generic
Python; Rails, Rust (Cargo), Go; PostgreSQL, MySQL/MariaDB, MongoDB, Redis, Docker, Supabase.

---

## Known limitations

- **`lsof` is required.** It ships with macOS at `/usr/sbin/lsof`. If it is missing the dashboard
  says so explicitly rather than showing an empty list.
- **Other users' processes are opaque.** A root-owned Postgres shows its port, PID, name and
  uptime, but no working directory, command line or CPU/memory. There is no way around this
  without elevated privileges, which the app deliberately does not seek.
- **TCP only.** UDP listeners and Unix domain sockets are not discovered.
- **Detection is heuristic.** A bare `node server.js` with no manifest reports as Node.js, not as
  whichever framework it imports. Confidence and the full ranking are visible in the debug
  inspector (Settings → *Show debug inspector*).
- **Git dirty state is not shown.** `git status` walks the whole index and is too expensive to run
  on every repository on a 2-second cadence. Repository root and branch only.
- **Monorepo package roots need a manifest.** A workspace package with no `package.json` of its own
  resolves to the repository root.
- **Docker containers are attributed to the Docker daemon**, not to the individual container.
- **Uptime is process start time**, not time since the port was bound.

---

## Tests

```bash
xcodebuild -scheme LocalhostHQ -destination 'platform=macOS' test
```

117 tests (Swift Testing) covering the logic that does not need live processes:

- **lsof parsing** — IPv4, IPv6 bracket form, wildcards, zone identifiers, multi-port processes,
  names containing spaces, malformed and truncated output, connected-socket rejection,
  dual-stack de-duplication, ordering stability
- **Project detection** — the monorepo case (package root `apps/web`, repo root `dicee`), sibling
  packages, subdirectory walk-up, worktree `.git` files, and the guard against a dotfiles
  repository in `$HOME` swallowing every service
- **Framework detection** — fixtures for every supported framework, meta-frameworks outranking the
  bundler they embed, FastAPI outranking Uvicorn, the Next.js rewritten-title and parent-command
  cases, and that a port alone identifies nothing
- **Manifest parsing** — names, dependencies, scripts as signals, malformed JSON, TOML comments
- **Origin classification** — including the python.org trap, where the interpreter lives inside
  `Python.app` and a naive `.app/Contents/` test would hide every Flask and Django server
- **CPU maths** — one core, four cores, idle, recycled PID, interval too short
- **Pipeline** — end-to-end with fakes, plus the scan-then-exit race and restricted processes
- **Formatting** — bytes, CPU above 100%, uptime, `~` abbreviation
- **Grouping, filtering, capabilities**

SwiftUI previews run on `SampleData` and never touch live discovery.
