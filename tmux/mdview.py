#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["textual>=3,<4"]
# ///
"""Quiet markdown viewer for the tmux sidebar.

Plain left-aligned headings (no banners/boxes), mouse scroll, links open in the
browser, reloads when the file changes.
Keys: q/esc close · g/G top/bottom · r reload
"""
import re
import sys
import webbrowser
from pathlib import Path

from textual.app import App, ComposeResult
from textual.containers import VerticalScroll
from textual import _xterm_parser
from textual.widgets import Markdown

_parse_mouse = _xterm_parser.XTermParser.parse_mouse_code
_HWHEEL = re.compile(r"\x1b\[<(\d+);")


def _parse_mouse_hwheel(self, code: str):
    # Horizontal wheel/trackpad swipes arrive as buttons 66 (left) / 67 (right).
    # Textual 3 reads them as vertical scrolls; turn them into shift+wheel, which
    # Textual scrolls horizontally — so a swipe over a wide code block pans it.
    m = _HWHEEL.match(code)
    if m and int(m.group(1)) & 67 in (66, 67):
        b = int(m.group(1))
        code = code.replace(m.group(0), f"\x1b[<{(b & ~2) | 4};", 1)
    return _parse_mouse(self, code)


_xterm_parser.XTermParser.parse_mouse_code = _parse_mouse_hwheel

CSS = """
Screen { background: ansi_default; }
VerticalScroll { padding: 0 2 1 1; scrollbar-size-vertical: 1; scrollbar-color: #2a4a50; scrollbar-background: ansi_default; }
Markdown { background: ansi_default; color: #d6dde0; margin: 0; padding: 0; }
MarkdownParagraph { margin: 0 0 1 0; }

MarkdownH1, MarkdownH2, MarkdownH3, MarkdownH4, MarkdownH5, MarkdownH6 {
    background: ansi_default; border: none; content-align: left top;
    padding: 0; margin: 1 0 1 0; width: 1fr;
}
MarkdownH1 { color: #7fd4ff; text-style: bold; margin: 0 0 1 0; }
MarkdownH2 { color: #7fd4ff; text-style: bold; }
MarkdownH3 { color: #a9dcef; text-style: bold; }
MarkdownH4, MarkdownH5, MarkdownH6 { color: #b8c7cc; text-style: bold; }

MarkdownBulletList, MarkdownOrderedList { margin: 0 0 1 0; }
MarkdownBulletList MarkdownBulletList, MarkdownOrderedList MarkdownOrderedList { margin: 0; }
MarkdownBullet { color: #5f8791; }

MarkdownBlockQuote { background: ansi_default; border-left: outer #3d6570; padding: 0 1; margin: 0 0 1 0; color: #9fb3b8; }
/* code blocks keep their lines; the wheel over one scrolls it first (up/down past
   20 rows, left/right with a sideways swipe or shift+wheel), then the page */
MarkdownFence { background: #0b2429; margin: 0 0 1 0; padding: 0 1; max-height: 20; scrollbar-size: 1 1; scrollbar-color: #2a4a50; scrollbar-background: #0b2429; }
MarkdownHorizontalRule { border-bottom: solid #2a4a50; }
MarkdownTable { margin: 0 0 1 0; }
MarkdownTableContent { background: ansi_default; }
"""


class MdView(App):
    CSS = CSS
    BINDINGS = [
        ("q", "quit", "quit"), ("escape", "quit", "quit"), ("r", "reload", "reload"),
        ("g", "top", "top"), ("G", "bottom", "bottom"),
    ]

    def __init__(self, path: Path):
        super().__init__(ansi_color=True)
        self.path = path
        self.mtime = 0.0
        self.reloading = False

    def compose(self) -> ComposeResult:
        with VerticalScroll():
            yield Markdown(id="md", open_links=False)

    async def on_mount(self) -> None:
        self.title = self.path.name
        await self.action_reload()
        self.set_interval(1.0, self.watch_file)

    async def action_reload(self) -> None:
        try:
            self.mtime = self.path.stat().st_mtime
            text = self.path.read_text(errors="replace")
        except OSError as e:
            text = f"**Cannot read** `{self.path}`: {e}"
        await self.query_one("#md", Markdown).update(text)

    async def watch_file(self) -> None:
        # never stack reloads: a slow re-render of a big file overlapping the
        # next 1s tick is the likeliest way to wedge the app
        if self.reloading:
            return
        try:
            if self.path.stat().st_mtime != self.mtime:
                self.reloading = True
                try:
                    await self.action_reload()
                finally:
                    self.reloading = False
        except OSError:
            pass

    def action_top(self) -> None:
        self.query_one(VerticalScroll).scroll_home(animate=False)

    def action_bottom(self) -> None:
        self.query_one(VerticalScroll).scroll_end(animate=False)

    def on_markdown_link_clicked(self, event: Markdown.LinkClicked) -> None:
        if event.href.startswith(("http://", "https://")):
            webbrowser.open(event.href)


if __name__ == "__main__":
    MdView(Path(sys.argv[1]).expanduser().resolve()).run()
