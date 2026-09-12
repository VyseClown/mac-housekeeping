# Mac Housekeeping

A precise housekeeping tool for Alessandro Gentil’s developer Mac. It is not a generic “clean my Mac” sweeper.

Two views:

1. **Cleanup** — investigation leftovers and already-used images/videos, with size and usage validation (open handles, last access, parent/holder, idle vs in use).
2. **Processes** — what is running, which files they hold, and how to localize a process before any kill. Xcode Simulators are listed here.

`nightshift` and `ai-memory` were installed on purpose. They are never flagged or deleted.

Nothing deletes, kills, or shuts down a simulator unless you confirm it. Simulators default to list-only. Booted devices are treated as in use by models and cannot be closed from this UI.

## Run locally

```bash
nvm use 20
pnpm install
pnpm dev
```

The app listens on [http://127.0.0.1:43147](http://127.0.0.1:43147).

```bash
pnpm build
pnpm start
pnpm lint
```

## Data

- **macOS** — live snapshot from `du`, `stat`, `lsof`, `ps`, and `xcrun simctl list`. Only paths that look like investigation leftovers or used media are candidates.
- **Linux / other** — realistic mock Mac data so the UI is usable off-machine.

Force mock on a Mac with `HOUSEKEEPING_FORCE_MOCK=1`.

Cleanup matches names such as `investigation`, `repro-har`, `used-captures`, `used-exports`, and `used-review`. Generic caches are ignored.
