#!/usr/bin/env python3
"""Draw Linux stand-in frames of the Pulse-tab SwiftUI chrome."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path("/cursor/stores/bc-c1bcf9bb-f833-47e4-a05c-0f3f4614856b/media")
W, H = 1280, 800
BG = (14, 16, 19)
BAR = (9, 10, 12)
CARD = (22, 24, 28)
TEXT = (235, 235, 238)
MUTED = (140, 144, 152)
GREEN = (59, 214, 133)
PURPLE = (158, 122, 250)
BLUE = (79, 176, 245)
AMBER = (245, 179, 61)
TABS = ("Cleanup", "Media", "Branches", "Processes")


def font(size, bold=False):
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    ]
    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def rounded(draw, box, radius, fill, outline=None):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline)


def chrome(draw, active):
    draw.rectangle([0, 0, W, 64], fill=BAR)
    draw.text((22, 22), "Housekeeping", font=font(16, True), fill=TEXT)
    x = 180
    for title in TABS:
        width = 92 if title != "Processes" else 100
        if title == active:
            rounded(draw, (x, 16, x + width, 48), 14, (28, 30, 36))
        draw.text((x + 12, 24), title, font=font(12, title == active), fill=TEXT if title == active else MUTED)
        x += width + 6
    rounded(draw, (980, 18, 1118, 46), 14, (28, 30, 36))
    draw.ellipse([992, 28, 1002, 38], fill=AMBER)
    draw.text((1008, 24), "Mock · companion", font=font(10, True), fill=TEXT)
    rounded(draw, (1132, 16, 1258, 48), 16, GREEN)
    draw.text((1146, 24), "Scan leftovers", font=font(11, True), fill=(10, 20, 14))


def badge(draw, x, y, label, color):
    rounded(draw, (x, y, x + 58, y + 18), 9, tuple(c // 6 + 20 for c in color))
    draw.text((x + 8, y + 3), label, font=font(10, True), fill=color)


def save(image, name):
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    image.save(path, "PNG")
    return path


def leftovers():
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    chrome(d, "Cleanup")
    d.ellipse([40, 110, 260, 330], outline=(30, 32, 38), width=18)
    d.arc([40, 110, 260, 330], start=-90, end=200, fill=GREEN, width=18)
    d.arc([40, 110, 260, 330], start=200, end=270, fill=AMBER, width=18)
    d.text((92, 190), "2.54 GB", font=font(20, True), fill=TEXT)
    d.text((88, 220), "leftovers only", font=font(11), fill=MUTED)
    d.text((290, 140), "Idle 2.47 GB", font=font(14, True), fill=GREEN)
    d.text((290, 166), "In use 72.8 MB", font=font(14, True), fill=AMBER)
    d.text((290, 198), "Media and worktrees stay on their own tabs.", font=font(12), fill=MUTED)
    rows = [
        ("investigation-2026-03-trace", "1.52 GB", "Idle", GREEN),
        ("repro-har-dumps", "195 MB", "Idle", GREEN),
        ("investigation-scratch-gkxw", "933 MB", "Idle", GREEN),
        ("investigation-packet-captures", "72.8 MB", "In use", AMBER),
    ]
    for i, (name, size, usage, color) in enumerate(rows):
        y = 360 + i * 72
        rounded(d, (40, y, 1240, y + 64), 12, CARD)
        d.text((56, y + 12), name, font=font(14, True), fill=TEXT)
        d.text((56, y + 36), size, font=font(12), fill=MUTED)
        badge(d, 1120, y + 22, usage, color)
        d.text((1210, y + 22), ">", font=font(16), fill=MUTED)
    return save(img, "native-cleanup.png")


def leftover_detail():
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    chrome(d, "Cleanup")
    d.text((40, 88), "<  Back", font=font(13), fill=BLUE)
    d.text((40, 120), "investigation-2026-03-trace", font=font(22, True), fill=TEXT)
    d.text((40, 156), "/Users/alessandro/Downloads/investigation-2026-03-trace", font=font(12), fill=MUTED)
    rounded(d, (40, 200, 760, 420), 16, CARD)
    d.text((56, 216), "Usage validation", font=font(14, True), fill=TEXT)
    d.text((56, 250), "Open handles   None", font=font(13), fill=MUTED)
    d.text((56, 276), "Last access    12d ago · mock", font=font(13), fill=MUTED)
    d.text((56, 302), "Parent         No holder", font=font(13), fill=MUTED)
    d.text((56, 328), "Idle vs in use Looks unused.", font=font(13), fill=MUTED)
    rounded(d, (56, 368, 200, 400), 16, GREEN)
    d.text((72, 376), "Review delete", font=font(12, True), fill=(10, 20, 14))
    return save(img, "native-cleanup-detail.png")


def media():
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    chrome(d, "Media")
    tiles = [
        ("prove-login-flow.mov", "8.3 GB", True),
        ("evidence-repro-loop.mp4", "6.0 GB", True),
        ("pr-1842-walkthrough.mov", "5.0 GB", True),
        ("prove-settings-pass.mov", "4.9 GB", True),
        ("crash-01.png", "176 MB", False),
        ("crash-02.png", "192 MB", False),
    ]
    for i, (name, size, video) in enumerate(tiles):
        col, row = i % 3, i // 3
        x, y = 40 + col * 400, 100 + row * 220
        hue = (55, 28, 90) if video else (22, 48, 52)
        rounded(d, (x, y, x + 372, y + 150), 12, hue)
        if video:
            d.ellipse([x + 166, y + 55, x + 206, y + 95], outline=TEXT, width=2)
        d.text((x, y + 162), name, font=font(13, True), fill=TEXT)
        d.text((x, y + 184), size + "  ·  already used on a PR", font=font(11), fill=MUTED)
    return save(img, "native-media.png")


def worktrees():
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    chrome(d, "Branches")
    d.text((40, 96), "Worktree space", font=font(18, True), fill=TEXT)
    d.text((40, 124), "23 GB across 4 worktrees. Leftovers and media stay on their tabs.", font=font(12), fill=MUTED)
    rounded(d, (40, 156, 1240, 190), 8, CARD)
    d.rectangle([44, 162, 500, 184], fill=BLUE)
    d.rectangle([502, 162, 820, 184], fill=AMBER)
    d.rectangle([822, 162, 1080, 184], fill=BLUE)
    d.rectangle([1082, 162, 1236, 184], fill=(50, 110, 160))
    rows = [
        ("/tmp/cursor-worktree-housekeeping-a1", "8.19 GB", "Idle", GREEN),
        ("/tmp/cursor-worktree-agent-b2", "7.10 GB", "In use", AMBER),
        ("/tmp/cursor-worktree-pr-review-c3", "5.40 GB", "Idle", GREEN),
        ("/tmp/cursor-worktree-old-d4", "2.31 GB", "Idle", GREEN),
    ]
    for i, (path, size, usage, color) in enumerate(rows):
        y = 220 + i * 80
        rounded(d, (40, y, 1240, y + 70), 12, CARD)
        d.text((56, y + 12), path, font=font(14, True), fill=TEXT)
        d.text((56, y + 38), "mac-housekeeping · " + size, font=font(12), fill=MUTED)
        badge(d, 1120, y + 24, usage, color)
    return save(img, "native-worktrees.png")


def processes():
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    chrome(d, "Processes")
    d.text((40, 96), "Xcode Simulators", font=font(16, True), fill=TEXT)
    rounded(d, (40, 128, 1240, 196), 12, CARD)
    d.text((56, 142), "iPhone 16 Pro  ·  iOS 18.5  ·  Booted", font=font(13, True), fill=TEXT)
    d.text((56, 166), "Models are using this device. Close stays off.", font=font(12), fill=MUTED)
    rounded(d, (1120, 148, 1218, 176), 10, (40, 40, 44))
    d.text((1140, 154), "Close", font=font(11), fill=MUTED)
    d.text((40, 226), "Processes", font=font(16, True), fill=TEXT)
    rows = [("ffmpeg", "55210", "Idle", GREEN), ("tcpdump", "33901", "Idle", GREEN), ("Preview", "77812", "In use", AMBER)]
    for i, (name, pid, usage, color) in enumerate(rows):
        y = 260 + i * 80
        rounded(d, (40, y, 1240, y + 70), 12, CARD)
        d.text((56, y + 14), name, font=font(16, True), fill=TEXT)
        d.text((56, y + 40), f"PID {pid} · parent launchd", font=font(12), fill=MUTED)
        badge(d, 1120, y + 24, usage, color)
    return save(img, "native-processes.png")


def main():
    old = OUT / "native-overview.png"
    if old.exists():
        old.unlink()
    paths = [leftovers(), leftover_detail(), media(), worktrees(), processes()]
    for path in paths:
        size = path.stat().st_size
        if size < 10_000:
            raise SystemExit(f"{path} too small: {size}")
        print(f"{path} {size}")


if __name__ == "__main__":
    main()
