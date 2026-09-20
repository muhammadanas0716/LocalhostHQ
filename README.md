# Localhost HQ

A native macOS control center for every development server listening on localhost.

Open it and your local environment is already there: what is running, on which port, from which
project, on which branch, what it costs, what it is printing, and what you can safely do to it.
No configuration, no registration step, no per-project setup.

Part 1 (discovery) and Part 2 (control, logging, lifecycle) are implemented. Part 3 is not.

---

## What it does

### Discovery — what exists

- Discovers every TCP socket in `LISTEN` state, de-duplicating dual-stack (IPv4 + IPv6) listeners
- Maps each port to its owning process: executable, full `argv`, parent, start time
- Resolves the process's working directory, and from it the package root and repository root
  (kept distinct — a monorepo service reports `apps/web` *and* `dicee`)
- Names the service from its manifest (`@dicee/web` → **web**), falling back to directory,
  framework, then process
- Detects framework and runtime heuristically, with a confidence score
- Reads Git repository root and current branch (including detached HEAD)
- Samples CPU, resident memory and uptime
- Groups services by repository; loose dev servers and infrastructure get their own sections
- Separates macOS/app daemons from your own work, hidden behind a toggle
- Refreshes every 2 seconds

### Control — what you can safely do

- **Stop** (SIGTERM) and, as a separate explicit action, **Force Stop** (SIGKILL)
- **Restart**, when the original launch command can be reconstructed with confidence
- **Restart Project** / **Stop Project** for every eligible service in a repository
- Process trees, showing exactly which processes an action would affect
- Port conflict detection, naming the owning project and offering to free the port
- Every destructive action verifies process identity first (see *Process safety*)

### Logging — what it is saying

- stdout and stderr captured live for anything Localhost HQ launches
- Search, level filters, follow/wrap, copy line
- Heuristic error and warning highlighting
- Deterministic diagnosis of common failures (`EADDRINUSE`, `MODULE_NOT_FOUND`, …)
- Bounded 10,000-line ring buffer per service

### Lifecycle — what happened to it

- Distinguishes an intentional stop from an unexpected exit
- Exit codes where genuinely knowable
- A session-scoped event log per service

### Not implemented

Saved environments, startup orchestration, `.env` editing, Docker Compose management, request
proxying/inspection, persisted history, remote machines, AI explanations. The architecture leaves
room for them; none of it is stubbed or faked.

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

## Process safety

Signalling the wrong process is the worst thing this app could do, so three rules constrain it.

**1. Identity is verified before every destructive action.** A PID is not an identity — PIDs are
recycled, and the gap between discovering a service and acting on it is easily long enough. Each
service carries a `ProcessInstanceIdentity` of *PID + start time + executable*, captured at
discovery and re-checked against the live process immediately before any signal. A mismatch aborts
with "This process has changed since it was discovered." A process whose start time the kernel
would not surrender cannot be verified, and so cannot be controlled at all.

**2. The blast radius is the job, never the terminal.** A dev server is rarely one process:

```
zsh              ← the terminal you typed in. Must never be signalled.
└── pnpm         ← part of the job
    └── node
        └── next-server  :3000
```

The boundary used is the **process group**. Shells with job control put each job in its own group,
so an interactive shell is never in its child job's group, while a wrapper script legitimately is —
and *must* be stopped, or it is orphaned. Two further guards cover shells started without job
control: an ancestor is never adopted if it is a session leader (a login or interactive shell always
is), nor if it is in a small deny-list (`launchd`, `sshd`, `login`, terminal emulators, this app).
Only processes owned by the current user are ever signalled. The resulting `ControlRoot` and its
members are shown in the inspector's process tree, so the blast radius is visible before you act.

**3. Escalation is never silent.** Stop sends SIGTERM and waits 5 seconds. If the process is still
alive it reports that and offers a choice; it does not fall through to SIGKILL. Force Stop is a
separate action, behind a confirmation that states the consequence.

### Restart

Restart is only offered when the original command can be reconstructed with confidence. The command
is recovered from the **control root**, not the listening process — Next.js rewrites its worker's
`argv` to `next-server (v15.0.3)`, which is a label, not a command, and rerunning it would fail.
Such rewritten titles are detected and rejected outright rather than producing a restart that
breaks.

The flow is: verify identity → stop the job → confirm the port is actually free → relaunch with
pipes attached → wait for rediscovery. Because the new process has a different PID, services carry a
`ServiceKey` — a logical identity anchored on the package directory — that survives the change, so
selection, logs, runtime state and history follow the service across a restart. A framework that
falls back to another port (`3000 in use, trying 3001`) is recognised by its shared anchor and
reported as "restarted on port 3001".

**Environment variables are not reproduced.** The environment of a running process is not
recoverable through public macOS APIs, and reading another process's environment would leak secrets
besides. A relaunch inherits Localhost HQ's environment plus the recovered working directory. That
is correct for a shell-launched dev server but will not reproduce variables exported only in that
shell. The app states this rather than pretending otherwise.

### Logging

Localhost HQ can only stream the output of processes it started itself. macOS provides no way to
attach to the stdout of a process started elsewhere, and there is no honest workaround — so a
service adopted from a terminal shows an explanation and a **Restart and Capture Logs** button
rather than a fake empty log.

Output is delivered in batches, one per pipe read, so 50,000 lines arrive as ~130 UI updates rather
than 50,000. Retention is a 10,000-entry ring buffer per service; the viewer is a `LazyVStack`, so
only visible lines are built.

---

## Architecture

Part 2 keeps four concerns separate rather than growing the discovery service:

```
DISCOVERY   what exists?
CONTROL     what can we safely do to it?
LOGGING     what is it outputting?
LIFECYCLE   what happened to it?
```

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

Control/            what may safely be done
  ProcessTable              whole process table in one sysctl (~0.8 ms)
  ProcessTreeInspector      trees, ancestors, control-root selection
  ProcessController         identity verification and signalling, an actor
  LaunchDescriptor(+Builder)  reconstructing the original command
  ServiceCapabilityResolver  one place that decides what the UI may offer
  PortConflictResolver      who owns a port, and is it safe to free
  ServiceController         the facade views actually call

Logging/            what it is saying
  ProcessOutputCapture      launching with pipes, line assembly, ANSI stripping
  LogBuffer                 bounded ring buffer
  LogStore / LogManager     observable per-service logs, keyed logically
  LogClassifier             level heuristics and deterministic diagnosis

Lifecycle/          what happened to it
  LifecycleTracker          runtime state, intent, unexpected-exit detection
  ServiceEvent              session-scoped history

Services/           composition
  LocalhostDiscoveryService   the pipeline, an actor
  ServiceGrouper              repository / dev / infrastructure sections
  ServiceFilter               search
  ServiceActions              browser, Finder, Terminal

App/AppEnvironment            composition root, wires the four systems
Stores/ServicesStore          @MainActor @Observable, owns the refresh loop
Models/                       value types, all Sendable
Views/                        SwiftUI, no control logic
```

Views call `await controller.restart(service)`, never `kill(pid, SIGTERM)`. Capability flags
(`canStop`, `canRestart`, `canStreamLogs`, …) are resolved once in `ServiceCapabilityResolver`, so
no view re-derives rules like "don't offer Restart to Postgres" from framework names.

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
- **Logs only exist for processes Localhost HQ launched.** See *Logging* above. Restarting a
  service through the app is what makes its output available.
- **Exit codes are only known for processes Localhost HQ launched.** macOS does not report the exit
  status of a process we are not the parent of, so for anything else the exit is reported without a
  code rather than with an invented one.
- **Environment variables are not reproduced on restart.** See *Restart* above.
- **Restart is refused when the command cannot be recovered confidently** — a rewritten process
  title, a missing working directory, or a binary that no longer exists. The inspector shows the
  recovered command and its confidence so the refusal is explainable.
- **A detached grandchild that reparents to launchd escapes the control root**, since it leaves the
  process group. Stopping the job will not reach it. This is deliberate: widening the net would risk
  signalling unrelated processes.
- **No notifications.** Lifecycle events are surfaced in the app rather than as system
  notifications; requesting notification permission was not worth it for Part 2.

---

## Tests

```bash
xcodebuild -scheme LocalhostHQ -destination 'platform=macOS' test
```

190 tests (Swift Testing) covering the logic that does not need live processes.

Part 2 adds:

- **Process identity** — PID reuse rejected via start time, differing executables rejected,
  unverifiable processes refused, `timeval` precision tolerated
- **Control root selection** — the `zsh → pnpm → node → next-server` fixture resolves to `pnpm`
  with the shell excluded; wrapper scripts in the same job *are* adopted; session leaders, other
  users' processes and deny-listed names are refused; parent cycles terminate
- **Launch descriptors** — `pnpm dev`, `npm run dev`, `bun dev`, `uvicorn main:app --reload`,
  `python manage.py runserver`, `cargo run`, `go run .`; rewritten process titles rejected; missing
  directories and executables rejected
- **Capabilities** — dev servers controllable, system services conservative, low-confidence
  commands block restart but not stop, databases never offer a browser action
- **Log classification** — errors, warnings, successful access logs not mis-flagged as errors,
  `EADDRINUSE` diagnosed with the port extracted, no false diagnosis on healthy output
- **Log buffering** — eviction at capacity, repeated wrapping, drop counting, clamped capacity
- **Lifecycle transitions** — `running → stopping → stopped`, `running → restarting → running`,
  unannounced disappearance as an unexpected exit, and the restart window *not* reported as a crash
- **Service keys** — anchor precedence, and surviving a port change

Part 1 coverage:

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
