# Architecture and Design

## Purpose and Audience

This document is for Codex and maintainers. It explains the design of the
tracked dotfiles so changes can preserve ownership boundaries, startup order,
cross-distribution behavior, and document consistency. It is not a desktop
operation manual; user tasks belong in `../user/desktop-guide-zh.md`.

## Repository Contract

The repository is bare at `$HOME/.cfg` with `$HOME` as its work tree. The `c`
alias is the canonical Git entry point. Only reusable home-directory
configuration is tracked. Credentials, browser state, caches, build products,
hardware state, and `*.local` per-machine overrides are deliberately outside
the repository.

Root dotfiles are compatibility links. Canonical content belongs under
`.config` or `.local`; do not replace a root link with a duplicate file merely
to make a local edit easier.

## Topology and Runtime Relations

| Layer | Canonical paths | Produces or owns |
| --- | --- | --- |
| Shell | `.config/shell/`, `.config/zsh/`, `.bashrc` | XDG environment, PATH, aliases, completion, package commands |
| X11 session | `.config/x11/`, root profile links | Login/session environment, input method, Xresources, session autostarts |
| Desktop programs | `~/src/{dwm,dwmblocks,dmenu,st}` | Separately maintained and compiled window-manager programs |
| User helpers | `.local/bin/` | Commands called by shell aliases, DWM bindings, MIME entries, status modules, cron |
| Runtime data | `.local/share/larbs/` | Keyboard map, Unicode data, helper text retained for compatible helpers |
| Project documents | `.local/share/docs/` | Dependency model, maintenance rules, plans, history, user material |
| System samples | `.local/share/sys-etc/` | Inactive templates that require explicit copy and adaptation |

The normal X11 relation is: login shell loads the canonical shell profile;
`startx` loads `.xinitrc`; the X session loads `xprofile`; `xprofile` loads
resources and starts only session-owned programs; `.xinitrc` starts
`ssh-agent dwm`. PipeWire, pipewire-pulse, and WirePlumber are intentionally
outside this chain because their owner is the systemd user service manager.

## Layout Model

`dependencies.md` is the authoritative layout model. Every new dependency,
script, document reference, and user-visible capability must belong to one of
the following layouts before it is added. A layout is an ownership boundary,
not a package-installation group.

## Shell, Source Control, and Development

Owns shell initialization, aliases, completion, editor selection, FZF, and
the bare-repository workflow. `.config/shell/profile` establishes shared
environment defaults; `aliasrc` provides commands and package-manager
branches; `.config/zsh/.zshrc` adds Zsh-specific frameworks and completion.

Keep shared helpers POSIX-compatible where possible. Zsh-only behavior stays
in `.config/zsh/`. Package aliases describe common operations, while each
distribution branch owns its own package-manager syntax. `profile.local` and
`aliasrc.local` are the only intended per-machine extension points.

## X11 Desktop and Input

Owns session startup, input-method selection, key remapping, compositor
startup, Xresources loading, and X11 helper integration. `xprofile` is the
single input-method decision point and must export all related environment
variables from the selected engine. It may start Dunst, Picom, MPD, and
unclutter when available, but must not start PipeWire services.

DWM, DWMBlocks, dmenu, st, and slock are external source trees under `~/src/`.
This repository may configure commands they invoke, but must not modify their
source or generated build output as part of a dotfiles change.

## Appearance, Fonts, and Wallpaper

Owns Fontconfig, GTK settings, Dunst appearance, Xresources, wal templates,
and `setbg`. Static colors and configured font fallbacks are the base state.
Wallpaper and pywal are overlays: absence of an image or `wal` must restore
defaults instead of leaving stale generated colors or preventing login.

## Audio, Music, Recording, and Video

Owns ALSA fallback configuration, MPD/Ncmpcpp/MPV settings, and media helpers
for recording, processing, thumbnails, tags, and slideshows. It consumes the
system audio stack through PipeWire-compatible interfaces. Hardware capture,
webcams, and an active MPD service are runtime conditions, not assumptions a
configuration edit may silently make.

## Files, Documents, Passwords, and Desktop Handlers

Owns LF, preview scripts, nsxiv, Zathura, MIME defaults, desktop entries,
document helpers, and password/OTP helpers. MIME entries and LF handlers form
a dependency chain: a new handler requires its command, desktop entry where
needed, dependency documentation, and a non-breaking behavior when optional.

Mail accounts, password-store contents, and personal documents remain
untracked. A helper may refer to those locations but must not require their
contents to make the shell or desktop session load.

## Display, Network, Mounting, and System Control

Owns display selection, remapping, brightness, lock/session actions,
NetworkManager entry points, and mount helpers. Treat hardware-specific paths
as conditional. In particular, Android MTP remains a documented Debian
hangup because the tracked `simple-mtpfs` interface has no verified compatible
package replacement; do not substitute another tool without an interface test.

## Status Bar, Communication, and Network Services

Owns DWMBlocks modules, RSS refresh, mail/task/torrent indicators, and bounded
network lookups. Modules are isolated processes: an unavailable command must
hide or degrade only that module. A status module must not introduce a daemon
or network retry loop that blocks the bar.

## Downloads, Torrents, and Text Browsing

Owns task-spooler download queues, Newsboat actions, link handling,
Transmission helpers, and terminal text browsing. Optional integrations such
as Tremc, FPP, and youtube-viewer need explicit guards and documented fallback
behavior. The daemon/client boundary for Transmission must remain clear.

## Compilation, Typesetting, and Data Helpers

Owns `compiler`, `getbib`, `texclear`, and source-format toolchains. The
compiler selects a command by input extension, so toolchains are feature
scoped rather than a single unconditional base requirement. TeX and broader
language-toolchain validation remain deferred until the actively supported
formats and output policy are decided.

## Templates and Scheduled Work

Owns inactive templates and cron helpers. Templates are never live system
configuration. Cron jobs require an explicit display, user D-Bus environment,
and reviewed sudo policy. Do not turn a documented sample into an autostarted
service without a separate design decision.

## Design and Maintenance Rules

- Prefer existing layout ownership over adding a new abstraction or file.
- Preserve trusted personal settings unless they are demonstrably invalid,
  unsafe, or ineffective.
- Optional programs must not break shell startup, X11 startup, or unrelated
  status modules.
- Keep package names out of cross-distribution design decisions; document
  stable commands and map providers during each distribution audit.
- Every documentation change under `.local/share/docs/` requires the full
  consistency review defined in `maintenance-policy.md`.
- `dependencies.md` defines capabilities; this file defines ownership and
  relationships; the user guide defines operations. Do not duplicate one
  document's role into another.

For active work, completed work, and paused work, use
[TODO](../planning/todo.md), [history](../planning/history.md), and
[suspended items](../planning/suspended.md).
