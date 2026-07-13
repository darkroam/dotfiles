# Maintenance Policy

## Project Constraints

- Track only reusable home-directory configuration. Do not add caches,
  credentials, installed-browser state, build output, or other machine state.
- Keep root compatibility links when applications or display managers rely on
  them; put canonical configuration below `.config` or `.local`.
- Prefer existing local patterns and POSIX shell for shared helpers.
- Treat command availability as optional unless a feature cannot run without
  it. A missing optional program must not break login or X11 startup.
- Keep package-manager behavior portable across APT, pacman, XBPS, and
  Portage where the configuration supports it.
- Preserve trusted personal values and templates unless an entry is provably
  invalid, ineffective, or dangerous.
- Add a new tracked file only when it creates a clear configuration or
  maintenance boundary; otherwise extend the existing owning file.
- Do not change the editor selection or the established `vim` invocation
  convention without an explicit decision.
- Review tracked content and Git history for credentials and personal data
  before a public push.
- Every change below `.local/share/docs/` requires a repository-wide document
  consistency review before commit. Verify terminology is uniform, internal
  links resolve, documented directory structure matches tracked paths, and
  relationships and responsibilities between documents remain valid.
- `project/architecture.md` is a self-contained Codex/developer design
  document: structure, ownership, runtime relationships, decisions, and
  maintenance boundaries only. `user/desktop-guide-zh.md` is a self-contained
  user operation document: installation, daily use, personalization, and
  troubleshooting only. Both follow the `dependencies.md` layouts, but neither
  may require the other to be understood or duplicate the other's role.
- Inspect and discuss a behavior change before applying it; verify and commit
  only after approval.

## Accepted Decisions

- `c` remains the central bare-repository command.
- `profile.local` and `aliasrc.local` are supported per-machine extension
  points.
- PipeWire and WirePlumber are owned by systemd user services.
- Static colors and desktop defaults must work without `wal` or wallpaper.
- The input-method selector is centralized in `xprofile`, preferring `fcitx5`,
  then `fcitx`, then `ibus`.
- Microsoft Edge is the configured browser through `BROWSER`.
- `nmtui` remains the interactive network-management interface when
  NetworkManager is installed.
- Existing ALSA fallback files remain until a sustained PipeWire-only test
  justifies removing them.
- DWM, DWMBlocks, dmenu, and st source are maintained separately under
  `~/src/`; the user builds and installs them.

## Explicitly Not Adopting

- Voidrice manual PipeWire/WirePlumber X-session autostart.
- Voidrice Bash/LUKS-specific `mounter` and `unmounter` scripts.
- A persistent `remapd` udev monitor; current remap entry points are enough.
- Tor wrapping and upstream personal browser, Neovim, and Python
  configurations.
- Voidrice `xdg-terminal-exec` unchanged; it lacks useful fallback and desktop
  registration.
- Blindly importing any upstream DWM keybinding or user guide: this repository
  documents its own configured behavior.

Review history is in [history.md](../planning/history.md); deferred proposals
are in [suspended.md](../planning/suspended.md).
