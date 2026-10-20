"""Runs a command in its own pty and types into it what arrives on a control FIFO.

    driver.py FIFO COMMAND...

Each line written to FIFO is typed into the command like a person would, one
key at a time. Escapes: \\r is Enter, \\e is Esc, \\p is a half-second pause.
A line starting with ! is sent as one key sequence instead.
Nothing outside this process receives a keystroke.
"""

import fcntl
import os
import pty
import random
import select
import signal
import sys
import termios
import time
import tty

fifo, command = sys.argv[1], sys.argv[2:]
pid, child = pty.fork()
if pid == 0:
    os.execvp(command[0], command)


def sync_size(*_):
    fcntl.ioctl(child, termios.TIOCSWINSZ, fcntl.ioctl(0, termios.TIOCGWINSZ, b"\0" * 8))


sync_size()
signal.signal(signal.SIGWINCH, sync_size)
tty.setraw(0)
# Opened read-write so the FIFO never reports end-of-file between writers.
control = os.open(fifo, os.O_RDWR | os.O_NONBLOCK)
pending, keys, next_key = b"", [], 0.0

while True:
    timeout = max(0.0, next_key - time.monotonic()) if keys else None
    try:
        ready = select.select([0, child, control], [], [], timeout)[0]
    except InterruptedError:
        continue
    if child in ready:
        try:
            data = os.read(child, 65536)
        except OSError:
            break
        if not data:
            break
        os.write(1, data)
    if 0 in ready:
        os.write(child, os.read(0, 65536))
    if control in ready:
        pending += os.read(control, 4096)
        *lines, pending = pending.split(b"\n")
        for line in lines:
            text = line.decode().replace("\\r", "\r").replace("\\e", "\x1b").replace("\\p", "\0")
            if text.startswith("!"):
                # A key sequence such as an arrow key, which must arrive in one write.
                keys.append(text[1:])
            else:
                keys.extend(text)
        next_key = max(next_key, time.monotonic())
    if keys and time.monotonic() >= next_key:
        key = keys.pop(0)
        if key == "\0":
            next_key = time.monotonic() + 0.5
            continue
        os.write(child, key.encode())
        next_key = time.monotonic() + (0.35 if key == "\r" else random.uniform(0.045, 0.11))

os.waitpid(pid, 0)
