#!/usr/bin/env python3
"""Sidebar scroll daemon: makes wheel scrolling over the sidebar smooth.

Every wheel notch used to spawn a bash script plus curl (tens of ms each), so a
trackpad flick queued up and the list moved in jumps. Now the tmux wheel binding
only writes one byte ("u"/"d") into a FIFO; this long-running process drains
whatever arrived, moves the offset one row per notch, renders the visible rows
from the cached full list in-process, and posts them to fzf over its unix socket
directly — at most one frame per ~16ms, no process spawns.

Rendering matches sidebar-view.sh (which the normal refresh path still uses):
blank parking row first, scrollbar in the last column.
"""
import os
import re
import select
import socket
import sys
import time

T = os.path.join(os.environ.get("TMPDIR", "/tmp"), f"tmux-sidebar-{os.getuid()}")
FIFO, ALL, SIZE, OFF, META = T + ".scroll.fifo", T + ".all", T + ".size", T + ".offset", T + ".offset.meta"
CACHE, POS, SOCK, PID = T + ".rows", T + ".pos", T + ".sock", T + ".scrolld.pid"
ANSI = re.compile(r"\x1b\[[0-9;]*m")
BOR, THUMB, RST = "\x1b[38;2;42;74;80m", "\x1b[38;2;64;212;231m", "\x1b[0m"
CUR = "\t▶"
FRAME = 1 / 60


def read(path, default=""):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return default


def write(path, text):
    tmp = path + ".d"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


def post(body):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(1)
    try:
        s.connect(SOCK)
        data = body.encode()
        s.sendall(b"POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: %d\r\n\r\n" % len(data) + data)
        s.recv(1024)
    except OSError:
        pass
    finally:
        s.close()


def render(delta):
    rows = read(ALL).split("\n")
    if rows and rows[-1] == "":
        rows.pop()
    try:
        w, ph = (int(x) for x in read(SIZE, "51 40").split()[:2])
    except ValueError:
        w, ph = 51, 40
    view, cw, total = ph - 1, w - 2, len(rows)
    try:
        off = int(read(OFF, "0").split()[0])
    except (ValueError, IndexError):
        off = 0
    off = max(0, min(off + delta, total - view))
    write(OFF, f"{off}\n")
    meta = read(META).split()
    key = meta[0] if meta else ""
    write(META, f"{key} {total} {view}\n")

    bar = total > view
    if bar:
        ts = max(1, view * view // total)
        tp = (view - ts) * off // (total - view)
    out, pos = ["\t "], 1
    for r, line in enumerate(rows[off:off + view]):
        cm = ""
        if line.endswith(CUR):
            cm, line = CUR, line[: -len(CUR)]
            pos = r + 2
        if bar:
            t, _, d = line.partition("\t")
            pad = max(0, cw - 1 - len(ANSI.sub("", d)))
            g = f"{THUMB}┃{RST}" if tp <= r < tp + ts else f"{BOR}│{RST}"
            line = f"{t}\t{d}{' ' * pad}{g}"
        out.append(line + cm)
    write(CACHE, "\n".join(out) + "\n")
    write(POS, f"pos({pos})\n")
    post(f"reload-sync(cat {CACHE})+pos({pos})")


def main():
    try:
        os.mkfifo(FIFO)
    except FileExistsError:
        pass
    write(PID, f"{os.getpid()}\n")
    fd = os.open(FIFO, os.O_RDWR | os.O_NONBLOCK)   # RDWR: never sees EOF when writers come and go
    last = 0.0
    while True:
        select.select([fd], [], [])
        delta = 0
        deadline = time.monotonic() + FRAME
        while True:                                   # coalesce a burst into one frame
            try:
                chunk = os.read(fd, 4096)
            except BlockingIOError:
                chunk = b""
            delta += chunk.count(b"d") - chunk.count(b"u")
            wait = deadline - time.monotonic()
            if wait <= 0 or not select.select([fd], [], [], wait)[0]:
                break
        if delta:
            since = time.monotonic() - last
            if since < FRAME:
                time.sleep(FRAME - since)
            render(delta)
            last = time.monotonic()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
