# Mac Housekeeping

Native SwiftUI app for Alessandro Gentil’s developer Mac. It maps leftovers, Desktop PR evidence, git worktrees, and holding processes. It is not a generic cleaner and not a wrapped web page.

Open `macos/MacHousekeeping/MacHousekeeping.xcodeproj` on a Mac. The dashboard is four Pulse-style tabs. Cleanup, Media, Branches, and Processes. Shared topbar. Confirm overlays. Drill-in with Back. A compact notch companion shows scan status only. Office, achievements, ECG, and phone are not copied.

`nightshift` and `ai-memory` stay off the cleanup lists. The app never deletes files, never kills a process, never runs `git worktree remove`, and never closes a simulator.

## How to run

1. On a Mac, open `macos/MacHousekeeping/MacHousekeeping.xcodeproj` in Xcode 15 or later.
2. Select the MacHousekeeping scheme.
3. Run. The first scan loads a live Darwin snapshot, or mock inventory if the host is not macOS. A later Scan leftovers keeps the last tabs on screen while the new snapshot is collected.

```bash
# Optional, from Xcode or a Mac shell
xcodebuild -project macos/MacHousekeeping/MacHousekeeping.xcodeproj -scheme MacHousekeeping -destination 'platform=macOS' test
```

Linux in this repo cannot compile SwiftUI. Mock sizes are checked with:

```bash
python3 macos/MacHousekeeping/scripts/verify-inventory.py
```

## What each module shows

- **Cleanup leftovers.** Investigation folders, sizes, open handles, last access, parent, idle vs in use.
- **Media.** Desktop prove and evidence images and videos already used on PRs. Thumbnails and in-app preview. Live files load on Darwin. Mock art stands in off-Mac.
- **Branches and worktrees.** Separate stacked size map. `/tmp` worktrees are the large slice. `git worktree remove` is text only.
- **Processes.** Holding processes, localize steps, simulator list. Close stays disabled.

## Data

- **macOS.** `du`, `stat`, `lsof`, `ps`, `xcrun simctl list`, `git worktree list`.
- **Linux / other.** Mock snapshot for Alessandro’s machine: about 28 GiB Desktop evidence and about 23 GiB `/tmp` worktrees.

Force mock on a Mac with `HOUSEKEEPING_FORCE_MOCK=1`.

An earlier Next.js slice remains under `src/` as domain reference. Do not ship it as the product.
