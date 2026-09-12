#!/usr/bin/env python3
"""Draw Linux stand-in frames of the SwiftUI chrome for store media."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path("/cursor/stores/bc-c1bcf9bb-f833-47e4-a05c-0f3f4614856b/media")
W, H = 1280, 800
BG = (14, 16, 19)
SIDE = (9, 10, 12)
CARD = (22, 24, 28)
TEXT = (235, 235, 238)
MUTED = (140, 144, 152)
GREEN = (59, 214, 133)
PURPLE = (158, 122, 250)
BLUE = (79, 176, 245)
AMBER = (245, 179, 61)


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


def sidebar(draw, active):
    draw.rectangle([0, 0, 232, H], fill=SIDE)
    draw.text((24, 28), "Housekeeping", font=font(18, True), fill=TEXT)
    draw.text((24, 52), "Alessandro Gentil", font=font(12), fill=MUTED)
    items = [
        ("Overview", 90),
        ("Cleanup leftovers", 130),
        ("Media", 170),
        ("Branches and worktrees", 210),
        ("Processes", 250),
    ]
    for title, y in items:
        if title == active:
            rounded(draw, (12, y - 8, 220, y + 24), 8, (28, 30, 36))
        color = TEXT if title == active else MUTED
        draw.text((28, y), title, font=font(13, title == active), fill=color)
    draw.text((24, 740), "Mock Mac data", font=font(11, True), fill=AMBER)
    draw.text((24, 758), "macOS 15.6.1 (mock)", font=font(10), fill=MUTED)


def topbar(draw, title):
    draw.text((256, 22), title, font=font(22, True), fill=TEXT)
    draw.text((256, 52), "alessandro · Alessandros-MacBook-Pro.local", font=font(11), fill=MUTED)
    rounded(draw, (1080, 24, 1248, 58), 16, GREEN)
    draw.text((1102, 32), "Scan leftovers", font=font(12, True), fill=(10, 20, 14))


def badge(draw, x, y, label, color):
    rounded(draw, (x, y, x + 58, y + 18), 9, tuple(c // 6 + 20 for c in color))
    draw.text((x + 8, y + 3), label, font=font(10, True), fill=color)


def save(image, name):
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    image.save(path, "PNG")
    return path


def overview():
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    sidebar(d, "Overview")
    topbar(d, "Overview")
    d.ellipse([300, 140, 560, 400], outline=(30, 32, 38), width=22)
    d.arc([300, 140, 560, 400], start=-90, end=-70, fill=GREEN, width=22)
    d.arc([300, 140, 560, 400], start=-70, end=80, fill=PURPLE, width=22)
    d.arc([300, 140, 560, 400], start=80, end=270, fill=BLUE, width=22)
    d.text((368, 240), "Mapped", font=font(12), fill=MUTED)
    d.text((348, 258), "53.7 GB", font=font(28, True), fill=TEXT)
    d.text((352, 296), "on Alessandro's Mac", font=font(11), fill=MUTED)
    d.text((600, 160), "Space map", font=font(26, True), fill=TEXT)
    d.text((600, 200), "Investigation leftovers, already-used Desktop", font=font(13), fill=MUTED)
    d.text((600, 220), "evidence, and /tmp git worktrees.", font=font(13), fill=MUTED)
    d.text((600, 260), "Leftovers   2.54 GB", font=font(13), fill=GREEN)
    d.text((600, 282), "Media       28 GB", font=font(13), fill=PURPLE)
    d.text((600, 304), "Worktrees   23 GB", font=font(13), fill=BLUE)
    rounded(d, (600, 340, 760, 376), 16, GREEN)
    d.text((618, 350), "Review leftovers", font=font(12, True), fill=(10, 20, 14))
    cards = [
        (256, 460, "Cleanup leftovers", "2.54 GB", GREEN),
        (560, 460, "Desktop media", "28 GB", PURPLE),
        (864, 460, "Branches and worktrees", "23 GB", BLUE),
    ]
    for x, y, title, size, hue in cards:
        rounded(d, (x, y, x + 284, y + 140), 16, CARD)
        d.text((x + 18, y + 18), title, font=font(13), fill=MUTED)
        d.text((x + 18, y + 50), size, font=font(26, True), fill=TEXT)
        d.ellipse([x + 18, y + 104, x + 30, y + 116], fill=hue)
    return save(img, "native-overview.png")


def leftovers():
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    sidebar(d, "Cleanup leftovers")
    topbar(d, "Cleanup leftovers")
    rows = [
        ("investigation-2026-03-trace", "1.52 GB", "Idle", GREEN),
        ("repro-har-dumps", "195 MB", "Idle", GREEN),
        ("investigation-scratch-gkxw", "933 MB", "Idle", GREEN),
        ("investigation-packet-captures", "72.8 MB", "In use", AMBER),
    ]
    for i, (name, size, usage, color) in enumerate(rows):
        y = 100 + i * 78
        fill = (28, 30, 36) if i == 0 else CARD
        rounded(d, (256, y, 760, y + 70), 12, fill)
        d.text((272, y + 12), name, font=font(14, True), fill=TEXT)
        d.text((272, y + 36), size, font=font(12), fill=MUTED)
        badge(d, 680, y + 24, usage, color)
    rounded(d, (780, 100, 1256, 620), 16, CARD)
    d.text((800, 120), "investigation-2026-03-trace", font=font(16, True), fill=TEXT)
    d.text((800, 150), "Usage validation", font=font(13, True), fill=TEXT)
    d.text((800, 180), "Open handles   None", font=font(12), fill=MUTED)
    d.text((800, 204), "Last access    12d ago · mock", font=font(12), fill=MUTED)
    d.text((800, 228), "Parent         No holder", font=font(12), fill=MUTED)
    d.text((800, 252), "Idle vs in use Looks unused.", font=font(12), fill=MUTED)
    rounded(d, (800, 300, 950, 334), 16, GREEN)
    d.text((818, 310), "Review delete", font=font(12, True), fill=(10, 20, 14))
    return save(img, "native-cleanup.png")


def media():
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    sidebar(d, "Media")
    topbar(d, "Media")
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
        x, y = 256 + col * 220, 100 + row * 180
        hue = (55, 28, 90) if video else (22, 48, 52)
        rounded(d, (x, y, x + 200, y + 110), 12, hue)
        if video:
            d.ellipse([x + 78, y + 36, x + 118, y + 76], outline=TEXT, width=2)
        d.text((x, y + 118), name, font=font(11, True), fill=TEXT)
        d.text((x, y + 136), size, font=font(10), fill=MUTED)
    rounded(d, (940, 100, 1256, 620), 16, CARD)
    d.text((956, 118), "prove-login-flow.mov", font=font(15, True), fill=TEXT)
    d.text((956, 146), "Already used on PR #1842", font=font(12, True), fill=PURPLE)
    rounded(d, (956, 176, 1236, 330), 12, (55, 28, 90))
    d.text((1040, 240), "VIDEO PREVIEW", font=font(12, True), fill=TEXT)
    d.text((956, 350), "/Users/alessandro/Desktop/pr-evidence/", font=font(10), fill=MUTED)
    d.text((956, 380), "Usage validation  Idle", font=font(12), fill=GREEN)
    return save(img, "native-media.png")


def worktrees():
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    sidebar(d, "Branches and worktrees")
    topbar(d, "Branches and worktrees")
    d.text((256, 96), "Worktree space", font=font(18, True), fill=TEXT)
    d.text((256, 124), "23 GB across 4 worktrees. Separate from leftover cards.", font=font(12), fill=MUTED)
    rounded(d, (256, 156, 1256, 190), 8, CARD)
    d.rectangle([260, 162, 620, 184], fill=BLUE)
    d.rectangle([622, 162, 920, 184], fill=AMBER)
    d.rectangle([922, 162, 1120, 184], fill=BLUE)
    d.rectangle([1122, 162, 1250, 184], fill=(50, 110, 160))
    rows = [
        ("/tmp/cursor-worktree-housekeeping-a1", "8.19 GB", "Idle", GREEN),
        ("/tmp/cursor-worktree-agent-b2", "7.10 GB", "In use", AMBER),
        ("/tmp/cursor-worktree-pr-review-c3", "5.40 GB", "Idle", GREEN),
        ("/tmp/cursor-worktree-old-d4", "2.31 GB", "Idle", GREEN),
    ]
    for i, (path, size, usage, color) in enumerate(rows):
        y = 220 + i * 70
        rounded(d, (256, y, 860, y + 60), 12, CARD)
        d.text((272, y + 10), path, font=font(13, True), fill=TEXT)
        d.text((272, y + 32), "mac-housekeeping · " + size, font=font(11), fill=MUTED)
        badge(d, 780, y + 20, usage, color)
    rounded(d, (880, 220, 1256, 520), 16, CARD)
    d.text((896, 240), "Later suggestion", font=font(13, True), fill=TEXT)
    d.text((896, 270), "git worktree remove", font=font(12), fill=BLUE)
    d.text((896, 290), "/tmp/cursor-worktree-housekeeping-a1", font=font(11), fill=MUTED)
    d.text((896, 330), "This app does not run the command.", font=font(12), fill=AMBER)
    return save(img, "native-worktrees.png")


def processes():
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    sidebar(d, "Processes")
    topbar(d, "Processes")
    d.text((256, 100), "Xcode Simulators", font=font(16, True), fill=TEXT)
    rounded(d, (256, 132, 760, 200), 12, CARD)
    d.text((272, 146), "iPhone 16 Pro  ·  iOS 18.5  ·  Booted", font=font(13, True), fill=TEXT)
    d.text((272, 170), "Models are using this device. Close stays off.", font=font(11), fill=MUTED)
    rounded(d, (640, 154, 740, 182), 10, (40, 40, 44))
    d.text((660, 160), "Close", font=font(11), fill=MUTED)
    rows = [("ffmpeg", "55210", "Idle", GREEN), ("tcpdump", "33901", "Idle", GREEN), ("Preview", "77812", "In use", AMBER)]
    d.text((256, 230), "Processes", font=font(16, True), fill=TEXT)
    for i, (name, pid, usage, color) in enumerate(rows):
        y = 262 + i * 64
        rounded(d, (256, y, 760, y + 56), 12, CARD)
        d.text((272, y + 10), name, font=font(14, True), fill=TEXT)
        d.text((272, y + 32), f"PID {pid} · parent launchd", font=font(11), fill=MUTED)
        badge(d, 680, y + 18, usage, color)
    rounded(d, (780, 132, 1256, 560), 16, CARD)
    d.text((796, 150), "ffmpeg", font=font(18, True), fill=TEXT)
    d.text((796, 184), "Localize", font=font(13, True), fill=TEXT)
    d.text((796, 210), "Activity Monitor → search ffmpeg", font=font(12), fill=MUTED)
    d.text((796, 232), "lsof -nP -p 55210", font=font(12), fill=MUTED)
    d.text((796, 270), "No signal is sent from this app.", font=font(12), fill=AMBER)
    return save(img, "native-processes.png")


def main():
    paths = [overview(), leftovers(), media(), worktrees(), processes()]
    for path in paths:
        size = path.stat().st_size
        if size < 10_000:
            raise SystemExit(f"{path} too small: {size}")
        print(f"{path} {size}")


if __name__ == "__main__":
    main()
