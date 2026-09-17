#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["textual>=3,<4"]
# ///
"""Quiet file viewer for the tmux sidebar.

One pane, never split: the files you open become tabs along the top and one is
shown at a time, the way cmux does it. Markdown is rendered — plain left-aligned
headings, links open in the browser. Anything else is shown as it is: syntax
highlighted and wrapped to the pane, because "open that file" is the useful part
and rendering a .ts as prose is not. Reloads when a file changes.

  mdview.py <file>         open one file
  mdview.py <list>.tabs    follow the tab list md-sidebar.sh writes

Keys: q close · ←/→ or [/] switch tab · w (or the tab's ✕) close tab ·
g/G top/bottom · r reload
"""
import os
import re
import sys
import webbrowser
from pathlib import Path

# Textual slides the tab underline and fades widgets in on a switch; through two
# tmux layers those partial repaints read as a flash.
os.environ.setdefault("TEXTUAL_ANIMATIONS", "none")

from rich.syntax import Syntax
from textual import events
from textual.app import App, ComposeResult
from textual.containers import Container, VerticalScroll
from textual.widgets import ContentSwitcher
from textual import _xterm_parser
from textual.widgets import Markdown, Static, Tab, Tabs

_parse_mouse = _xterm_parser.XTermParser.parse_mouse_code
_HWHEEL = re.compile(r"\x1b\[<(\d+);")

MD_SUFFIXES = (".md", ".markdown", ".mdown", ".mkd")


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
/* the screen itself never scrolls: only the file does. Without this the tab bar
   could be shoved off the top by a stray wheel event. */
Screen { background: ansi_default; overflow: hidden; }
/* the tab bar sits in its own rounded box, like the window sidebar's cards */
#tabbar { height: 3; border: round #2a4a50; padding: 0 1; background: ansi_default; }
Tabs { background: ansi_default; height: 1; }
Underline { display: none; }
/* Textual dims the whole tab list and only un-dims the active tab while the
   widget has focus, which it never has here — the file has it. Say it plainly. */
#tabs-list { text-style: not dim; }
/* Textual pins the tab strip (overflow: hidden) and only scrolls it to reach the
   active tab; let the wheel move it too, without a scrollbar eating a row */
#tabs-scroll { overflow-x: auto; overflow-y: hidden; scrollbar-size: 0 0; }
/* the ✕ is a click action, which Textual underlines by default */
Tab { color: #5f8791; padding: 0 1; height: 1; text-style: not dim; border-right: solid #2a4a50;
      link-style: none; link-color: #dddddd; link-style-hover: bold; link-color-hover: #40d4e7; link-background-hover: transparent; }
Tab:last-of-type { border-right: none; }
Tab.-active { color: #40d4e7; text-style: bold not dim; }
ContentSwitcher { background: ansi_default; height: 1fr; }
VerticalScroll { height: 1fr; padding: 0 2 1 1; scrollbar-size-vertical: 1; scrollbar-color: #2a4a50; scrollbar-background: ansi_default; }
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

/* non-markdown: the file as it is, wrapped to the pane like prose — the sidebar
   is narrow and a long line is worth reading, not scrolling sideways for. */
.plain { background: ansi_default; width: 1fr; padding: 0 1 1 0; }
VerticalScroll.plainbox { padding: 0 0 0 1; }
"""


class MdView(App):
    CSS = CSS
    # Textual 3 selects text when you drag the mouse. A click on a tab that
    # slides a cell highlights a whole block and repaints the pane — the flash.
    # Shift-drag still selects, at the terminal's level, which is what copies.
    ALLOW_SELECT = False
    BINDINGS = [
        # NOT escape: a mouse sequence the parser cannot make sense of — the ones
        # a drag on the pane border produces — arrives as a bare escape, and the
        # whole sidebar would vanish mid-resize
        ("q", "quit", "quit"), ("r", "reload", "reload"),
        ("g", "top", "top"), ("G", "bottom", "bottom"),
        ("right", "next_tab", "next"), ("bracketright", "next_tab", "next"),
        ("left", "prev_tab", "prev"), ("bracketleft", "prev_tab", "prev"),
        ("w", "close_tab", "close tab"), ("ctrl+w", "close_tab", "close tab"),
    ]

    def __init__(self, target: Path):
        super().__init__(ansi_color=True)
        # a .tabs file is the list md-sidebar.sh appends to; anything else is
        # simply the one file to show, with nothing to follow
        self.list_path = target if target.suffix == ".tabs" else None
        self.active_path = Path(f"{target}.active") if self.list_path else None
        self.files: list[Path] = [] if self.list_path else [target]
        self.current: Path | None = None
        self.current_tid: str | None = None
        self.kinds: dict[str, str] = {}   # mounted view id → "md" | "plain"
        self.mtimes: dict[Path, float] = {}
        self.seen_active = ""
        self.tab_ids: dict[str, Path] = {}
        self.next_tab_id = 0
        self.reloading = False

    def compose(self) -> ComposeResult:
        with Container(id="tabbar"):
            yield Tabs(id="tabs")
        yield ContentSwitcher(id="body")

    async def on_mount(self) -> None:
        if self.list_path is not None:
            await self.sync_tabs()
            self.set_interval(0.3, self.sync_tabs)
        else:
            self.add_tabs(self.files)
        self.set_interval(1.0, self.watch_file)

    # ── tabs ────────────────────────────────────────────────────────────
    def add_tabs(self, paths: list[Path]) -> None:
        tabs = self.query_one(Tabs)
        for p in paths:
            tid = f"t{self.next_tab_id}"
            self.next_tab_id += 1
            self.tab_ids[tid] = p
            # Tab is a Static, so its label can carry a click action: the ✕
            # closes that one tab, wherever it is in the bar
            name = p.name.replace("[", "\\[")
            tabs.add_tab(Tab(f"{name} [@click=app.close_id('{tid}')]✕[/]", id=tid))

    async def sync_tabs(self) -> None:
        """Bring the tab bar in line with the list file, then honour .active."""
        if self.list_path is None:
            return
        try:
            lines = self.list_path.read_text().split("\n")
        except OSError:
            return
        wanted = [Path(line) for line in lines if line.strip()]
        if not wanted:
            # an empty or half-written list is not a reason to close the pane;
            # only closing the last tab is
            return

        tabs = self.query_one(Tabs)
        for tid, p in list(self.tab_ids.items()):
            if p not in wanted:
                del self.tab_ids[tid]
                tabs.remove_tab(tid)
                self.kinds.pop(f"p-{tid}", None)
                for pane in self.query(f"#p-{tid}"):
                    pane.remove()
        self.add_tabs([p for p in wanted if p not in self.tab_ids.values()])
        self.files = wanted

        try:
            active = self.active_path.read_text().strip()
        except OSError:
            active = ""
        if active and active != self.seen_active:
            self.seen_active = active
            for tid, p in self.tab_ids.items():
                if str(p) == active:
                    tabs.active = tid
                    return
        if self.current is None or self.current not in wanted:
            for tid, p in self.tab_ids.items():
                if p == wanted[0]:
                    tabs.active = tid
                    break

    async def on_tabs_tab_activated(self, event: Tabs.TabActivated) -> None:
        tid = event.tab.id if event.tab else None
        path = self.tab_ids.get(tid) if tid else None
        if tid is not None and path is not None and path != self.current:
            await self.show(tid, path)

    def action_next_tab(self) -> None:
        self.query_one(Tabs).action_next_tab()

    def action_prev_tab(self) -> None:
        self.query_one(Tabs).action_previous_tab()

    def action_close_tab(self) -> None:
        """Close the tab in front; the ✕ on any tab closes that one instead."""
        if self.current_tid is None:
            self.exit()
            return
        self.action_close_id(self.current_tid)

    def action_close_id(self, tid: str) -> None:
        """Drop one tab. The list file is the source of truth, so the viewer
        picks the change up through the same path md-sidebar.sh writes."""
        path = self.tab_ids.get(tid)
        if self.list_path is None or path is None:
            self.exit()
            return
        rest = [p for p in self.files if p != path]
        try:
            self.list_path.write_text("".join(f"{p}\n" for p in rest))
        except OSError:
            return
        if not rest:
            self.exit()

    # ── content ─────────────────────────────────────────────────────────
    async def show(self, tid: str, path: Path) -> None:
        """Bring a tab's view to the front, building it the first time only.

        Every tab keeps its own mounted view, so a switch is a swap rather than
        a rebuild: no flash, and each tab remembers where it was scrolled to.
        """
        self.current, self.current_tid = path, tid
        self.title = path.name
        switcher = self.query_one("#body", ContentSwitcher)
        pid = f"p-{tid}"
        if pid not in self.kinds:
            markdown = path.suffix.lower() in MD_SUFFIXES
            self.kinds[pid] = "md" if markdown else "plain"
            if markdown:
                pane = VerticalScroll(Markdown(open_links=False), id=pid)
            else:
                pane = VerticalScroll(
                    Static(classes="plain", expand=False, shrink=False),
                    id=pid,
                    classes="plainbox",
                )
            await switcher.mount(pane)
            await self.load(path, pid)
        switcher.current = pid

    async def load(self, path: Path, pid: str) -> None:
        message = ""
        try:
            self.mtimes[path] = path.stat().st_mtime
            text = path.read_text(errors="replace")
        except OSError as e:
            text = None
            message = f"Cannot read {path}: {e}"
        pane = self.query_one(f"#{pid}")
        if self.kinds.get(pid) == "md":
            await pane.query_one(Markdown).update(
                text if text is not None else f"**{message}**"
            )
            return
        static = pane.query_one(Static)
        if text is None:
            static.update(message)
            return
        static.update(
            Syntax(
                text,
                Syntax.guess_lexer(str(path), code=text),
                theme="native",
                line_numbers=True,
                word_wrap=True,
                background_color="default",
            )
        )

    async def action_reload(self) -> None:
        if self.current is not None and self.current_tid is not None:
            await self.load(self.current, f"p-{self.current_tid}")

    async def watch_file(self) -> None:
        # never stack reloads: a slow re-render of a big file overlapping the
        # next 1s tick is the likeliest way to wedge the app
        if self.reloading or self.current is None:
            return
        try:
            if self.current.stat().st_mtime != self.mtimes.get(self.current):
                self.reloading = True
                try:
                    await self.action_reload()
                finally:
                    self.reloading = False
        except OSError:
            pass

    def _scroll_tabs(self, dx: int, event: events.MouseEvent) -> None:
        """A wheel over the tab bar moves it sideways — there is nothing to
        scroll vertically up there, and the strip is usually wider than the pane."""
        if event.screen_y > 2:   # the boxed bar occupies the first three rows
            return
        self.query_one("#tabs-scroll").scroll_relative(x=dx, animate=False)
        event.stop()

    def on_mouse_scroll_down(self, event: events.MouseScrollDown) -> None:
        self._scroll_tabs(3, event)

    def on_mouse_scroll_up(self, event: events.MouseScrollUp) -> None:
        self._scroll_tabs(-3, event)

    def visible(self) -> VerticalScroll | None:
        if self.current_tid is None:
            return None
        return self.query_one(f"#p-{self.current_tid}", VerticalScroll)

    def action_top(self) -> None:
        pane = self.visible()
        if pane is not None:
            pane.scroll_home(animate=False)

    def action_bottom(self) -> None:
        pane = self.visible()
        if pane is not None:
            pane.scroll_end(animate=False)

    def on_markdown_link_clicked(self, event: Markdown.LinkClicked) -> None:
        if event.href.startswith(("http://", "https://")):
            webbrowser.open(event.href)


if __name__ == "__main__":
    MdView(Path(sys.argv[1]).expanduser()).run()
