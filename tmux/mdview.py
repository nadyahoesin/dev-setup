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
import sys
import webbrowser
from pathlib import Path

from textual.app import App, ComposeResult
from textual.containers import VerticalScroll
from textual.widgets import Markdown

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
MarkdownFence { background: #0b2429; margin: 0 0 1 0; padding: 0 1; max-height: 40; }
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
        try:
            if self.path.stat().st_mtime != self.mtime:
                await self.action_reload()
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
