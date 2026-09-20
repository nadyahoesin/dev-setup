#!/usr/bin/env bash
# ⌘/ : cheat sheet of the Ghostty ⌘ shortcuts that drive tmux.
B=$'\e[1m' D=$'\e[2m' R=$'\e[0m'
cat <<EOF

  ${B}Tabs${R}
    ⌘T              new tab
    ⌘W              close pane (closes the tab if it's the only pane)
    ⌘R              rename tab (pins the name; the app stops naming it)
    ⌘⇧R             let the app name the tab again (/rename, pi, folder)
    ⌘1 … ⌘9         go to tab 1–9
    ⌘⇧[  ⌘⇧]        previous / next tab (sidebar order)
    ⌘S              tab & session picker (also worker sessions)
    click sidebar   switch tab · click ▾/▸ to fold workers

  ${B}Splits${R}
    ⌘D              split right
    ⌘⇧D             split down
    ⌘⌥ ← ↓ ↑ →      move between splits

  ${B}Other${R}
    ⌘⇧K             clear scrollback
    ⌘⇧U             open a URL from this pane
    ⌘⇧M             markdown picker → sidebar
    ⌥-click / double-click a .md path → sidebar
    ⌘↩              fullscreen
    ⌘/              this help

  ${D}press any key to close${R}
EOF
read -rsn1
