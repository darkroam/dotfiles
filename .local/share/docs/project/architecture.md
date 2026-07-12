# Architecture and Design

## Scope

This is a bare Git repository at `$HOME/.cfg` whose work tree is `$HOME`.
Only tracked configuration belongs to the project; device state, caches,
credentials, build products, and per-machine overrides remain untracked.

The central command is `c`, an alias for Git with the bare repository and home
work tree. Root-level dotfiles are compatibility entry points. Their canonical
configuration lives below `.config` or `.local`.

## Layout

| Area | Canonical location | Responsibility |
| --- | --- | --- |
| Shell | `.config/shell/`, `.config/zsh/`, `.bashrc` | Environment, aliases, package commands, history, bookmarks, completion |
| X11 session | `.config/x11/` | X startup, input method, compositor, Xresources, wallpaper, remaps |
| Desktop appearance | `.config/fontconfig/`, `.config/gtk-*`, `.config/dunst/` | Fonts, GTK appearance, notifications |
| Audio and media | `.config/mpd/`, `.config/ncmpcpp/`, `.config/mpv/`, `.config/alsa/` | MPD clients, MPV, retained ALSA fallback |
| File and document tools | `.config/lf/`, `.config/sxiv/`, `.config/zathura/`, `.config/mimeapps.list` | File manager, previews, MIME handlers |
| User commands | `.local/bin/` | Interactive helpers, status modules, cron helpers |
| LARBS runtime resources | `.local/share/larbs/` | Retained upstream runtime data, keyboard map, Unicode data, and helper text |
| Project documentation | `.local/share/docs/` | Project, planning, and end-user documentation |
| System templates | `.local/share/sys-etc/` | Examples to copy and adapt, never automatically installed |
| Per-machine extension points | `*.local` files | Untracked overrides loaded only when present |

## Load Order

1. Login shells load `.profile` or `.zprofile`, which point to
   `.config/shell/`. These establish XDG locations, program defaults, and
   `$PATH`.
2. `startx` loads `.xinitrc`, then `.config/x11/xprofile`; display managers
   load the root `.xprofile` link directly.
3. `xprofile` adds `.local/bin` if needed, selects one input-method engine,
   loads static Xresources, optionally overlays pywal colors, starts remaps,
   wallpaper handling, compositor, MPD, Dunst, and unclutter.
4. `.xinitrc` finally starts `ssh-agent dwm`.
5. DWM and DWMBlocks are separate source repositories under `~/src/`; this
   repository configures the commands they invoke but does not build them.

## Design Decisions

- **XDG-first, compatibility links retained.** Canonical files are organized
  under `.config`; root links remain where programs expect them.
- **Cross-distribution shell behavior.** Package aliases use a common `p`
  prefix and detect APT, pacman, XBPS, or Portage. Documentation names commands
  rather than distribution-specific package names.
- **Optional dependencies must fail quietly.** Missing optional programs must
  not break a normal login, X startup, or status bar.
- **PipeWire is service-owned.** PipeWire, pipewire-pulse, and WirePlumber are
  systemd user services; X startup does not launch them.
- **Wallpaper and pywal are independent.** Static Xresources, Dunst, and
  Zathura defaults work without `wal` or a configured wallpaper. `setbg`
  augments them when wallpaper and pywal are available.
- **Personal overrides stay local.** `aliasrc.local` and `profile.local` are
  intentionally optional and untracked, so different devices can diverge
  without polluting the common configuration.

## Ownership Boundaries

`~/src/dwm`, `~/src/dwmblocks`, `~/src/dmenu`, and `~/src/st` are maintained,
compiled, and installed separately. Do not change their source or generated
files when making a dotfile-only change. System templates below
`.local/share/sys-etc/` are examples, not active system configuration.

For current work, completed work, and paused work, use
[TODO](../planning/todo.md), [history](../planning/history.md), and
[suspended items](../planning/suspended.md).
