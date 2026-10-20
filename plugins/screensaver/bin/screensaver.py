"""The dev-null.sh wordmark drifting across the terminal until Esc.

The wordmark (assets/wordmark.svg, built by tools/build_wordmark.py) is
rasterised by rsvg-convert at the window's physical pixel size and shown through
the kitty graphics protocol, so it is drawn at native resolution and moves a
pixel at a time.
"""

import base64
import fcntl
import json
import math
import os
import pathlib
import random
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time
import tty

SVG = (pathlib.Path(__file__).resolve().parent.parent / "assets" / "wordmark.svg").read_text()
_, _, _view_w, _view_h = map(float, re.search(r'viewBox="([^"]+)"', SVG).group(1).split())
ASPECT = _view_w / _view_h

# The site's own fills for its two colour schemes: (ink, accent).
PALETTES = {
    "dark": ("#ececec", "#ff8a4c"),
    "light": ("#121417", "#d9480f"),
}

WIDTH_SHARE = 0.7
HEIGHT_SHARE = 0.3
SPEED = 0.12  # window heights per second
FPS = 60


def terminal_size(fd):
    rows, cols, xpix, ypix = struct.unpack("HHHH", fcntl.ioctl(fd, termios.TIOCGWINSZ, b"\0" * 8))
    return cols, rows, xpix, ypix


def query_background(fd):
    """Asks the terminal for its background (OSC 11); black when it does not answer."""
    os.write(fd, b"\x1b]11;?\x1b\\")
    reply, deadline = b"", time.monotonic() + 0.3
    while time.monotonic() < deadline and not reply.endswith((b"\x07", b"\x1b\\")):
        if select.select([fd], [], [], max(0, deadline - time.monotonic()))[0]:
            reply += os.read(fd, 64)
    found = re.search(rb"rgb:([0-9a-fA-F]+)/([0-9a-fA-F]+)/([0-9a-fA-F]+)", reply)
    if not found:
        return (0, 0, 0)
    return tuple(int(h, 16) * 255 // (16 ** len(h) - 1) for h in found.groups())


def transmit(out, palette, width, height):
    """Uploads the logo as kitty image 1, replacing any earlier upload."""
    ink, accent = palette
    png = subprocess.run(
        ["rsvg-convert", "-w", str(width), "-h", str(height)],
        input=SVG.format(ink=ink, accent=accent).encode(),
        capture_output=True,
        check=True,
    ).stdout
    data = base64.b64encode(png).decode()
    chunks = [data[i : i + 4096] for i in range(0, len(data), 4096)]
    out.write("\x1b_Ga=d,d=I,i=1,q=2\x1b\\")
    for n, chunk in enumerate(chunks):
        more = int(n < len(chunks) - 1)
        head = "a=t,f=100,i=1,q=2,m=%d" % more if n == 0 else "m=%d" % more
        out.write("\x1b_G%s;%s\x1b\\" % (head, chunk))


def main():
    fd = sys.stdin.fileno()
    out = sys.stdout
    saved = termios.tcgetattr(fd)
    resized = [True]
    signal.signal(signal.SIGWINCH, lambda *_: resized.__setitem__(0, True))
    for stop in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(stop, lambda *_: sys.exit())
    tty.setraw(fd)
    out.write("\x1b[?1049h\x1b[?25l\x1b[2J")
    out.flush()
    try:
        bg = query_background(fd)
        luminance = 0.2126 * bg[0] + 0.7152 * bg[1] + 0.0722 * bg[2]
        palette = PALETTES["dark" if luminance < 128 else "light"]
        angle = random.choice([0.6, 2.5, 3.8, 5.6])
        direction = [math.cos(angle), math.sin(angle)]
        position, drawn = None, None
        last = time.monotonic()

        while True:
            if resized[0]:
                resized[0] = False
                cols, rows, xpix, ypix = terminal_size(fd)
                cell_w, cell_h = xpix / cols, ypix / rows
                width = round(min(WIDTH_SHARE * xpix, HEIGHT_SHARE * ypix * ASPECT))
                height = round(width / ASPECT)
                transmit(out, palette, width, height)
                bounds = (xpix - width, ypix - height)
                speed = SPEED * ypix
                if position is None:
                    position = [bounds[0] / 2, bounds[1] / 2]
                position = [min(max(p, 0), b) for p, b in zip(position, bounds)]
                drawn = None

            now = time.monotonic()
            step, last = min(now - last, 0.1), now
            for axis in (0, 1):
                position[axis] += direction[axis] * speed * step
                if not 0 <= position[axis] <= bounds[axis]:
                    direction[axis] = -direction[axis]
                    position[axis] = min(max(position[axis], 0), bounds[axis])

            x, y = round(position[0]), round(position[1])
            if (x, y) != drawn:
                col, row = int(x // cell_w), int(y // cell_h)
                offset_x, offset_y = int(x - col * cell_w), int(y - row * cell_h)
                out.write(
                    "\x1b[?2026h\x1b[%d;%dH\x1b_Ga=p,i=1,p=1,X=%d,Y=%d,C=1,q=2\x1b\\\x1b[?2026l"
                    % (row + 1, col + 1, offset_x, offset_y)
                )
                out.flush()
                drawn = (x, y)

            try:
                ready = select.select([fd], [], [], 1 / FPS)[0]
            except InterruptedError:
                continue
            if ready:
                keys = os.read(fd, 64)
                if keys in (b"\x1b", b"q", b"\x03"):
                    return
    finally:
        out.write("\x1b_Ga=d,d=A,q=2\x1b\\\x1b[?25h\x1b[?1049l")
        out.flush()
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)
        active = subprocess.run(["hyprctl", "activewindow", "-j"], capture_output=True, text=True).stdout
        if len(sys.argv) > 1 and json.loads(active or "{}").get("class") == "sh.devnull.screensaver":
            # Hand focus back to the covered window before this one closes, or Hyprland picks another.
            subprocess.run(
                ["hyprctl", "dispatch", 'hl.dsp.focus({ window = "address:%s" })' % sys.argv[1]],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )


if __name__ == "__main__":
    main()
