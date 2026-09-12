#!/usr/bin/env python3
"""Check mock inventory byte totals and protection rules in MockInventory.swift."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "MacHousekeeping" / "Collection" / "MockInventory.swift"
TEXT = SOURCE.read_text()

GIB = 1024**3
MEDIA_TARGET = 28 * GIB
WORKTREE_TARGET = 23 * GIB


def ints_in(block: str) -> list[int]:
    return [int(match) for match in re.findall(r"bytes:\s*([0-9_]+)", block)]


def extract(fn_name: str) -> str:
    start = TEXT.index(f"private static func {fn_name}")
    rest = TEXT[start:]
    depth = 0
    for index, char in enumerate(rest):
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return rest[: index + 1]
    raise SystemExit(f"could not extract {fn_name}")


def main() -> int:
    media_block = extract("mediaItems")
    workspace_block = extract("workspaceItems")
    leftover_block = extract("leftoverItems")

    media_bytes = sum(ints_in(media_block))
    leftover_bytes = sum(ints_in(leftover_block))
    worktree_bytes = 0
    for chunk in workspace_block.split("GitWorkspace(")[1:]:
        if "kind: .worktree" in chunk:
            values = ints_in(chunk)
            if values:
                worktree_bytes += values[0]

    errors = []
    if media_bytes != MEDIA_TARGET:
        errors.append(f"media {media_bytes} != {MEDIA_TARGET} (28 GiB)")
    if worktree_bytes != WORKTREE_TARGET:
        errors.append(f"worktrees {worktree_bytes} != {WORKTREE_TARGET} (23 GiB)")

    combined = leftover_block + media_block + workspace_block
    for banned in ("nightshift", "ai-memory", "ai_memory"):
        if re.search(banned, combined, re.I) and "ai-memory" in combined and "ProtectedKeep" not in extract.__name__:
            if banned in leftover_block.lower() or banned in media_block.lower():
                errors.append(f"protected name leaked into cleanup lists: {banned}")
    if re.search(r"nightshift|ai[-_]?memory", leftover_block, re.I):
        errors.append("leftovers mention a protected path")
    if re.search(r"nightshift|ai[-_]?memory", media_block, re.I):
        errors.append("media mentions a protected path")
    if "git worktree remove" not in workspace_block:
        errors.append("worktree later-suggestion is missing")
    if leftover_bytes <= 0:
        errors.append("leftovers have no size")

    print(f"media_bytes={media_bytes} ({media_bytes / GIB:.3f} GiB)")
    print(f"worktree_bytes={worktree_bytes} ({worktree_bytes / GIB:.3f} GiB)")
    print(f"leftover_bytes={leftover_bytes}")
    if errors:
        print("FAIL")
        for error in errors:
            print(error)
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
