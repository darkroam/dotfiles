# dotfiles

Personal Linux configuration managed as a bare Git repository. The tracked
files are intended to work from `$HOME`; untracked files are deliberately not
part of this repository.

Last reviewed: 2026-07-12

## Repository Usage

The configuration repository is `$HOME/.cfg`, with `$HOME` as its work tree.
The shell configuration defines:

```sh
alias c='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'
```

Use `c status`, `c diff`, `c add <path>`, and `c commit` for tracked
configuration changes. `c` has Zsh and Bash completion support. In
particular, `c diff <Tab>` completes files with uncommitted diffs; it is
correctly empty when the repository is clean.

The repository remote is `git@github.com:darkroam/dotfiles.git`.

## Installation

Bootstrap configuration tracking in `$HOME` with the existing installer:

```sh
curl -Lks https://github.com/darkroam/dotfiles/raw/master/.local/bin/install.sh | /bin/bash
```

The installer clones the bare repository into `$HOME/.cfg`, checks out tracked
files into `$HOME`, backs up checkout conflicts to `.config-backup`, and hides
untracked files from `c status`. Review the script before running it on a
machine with existing configuration.

## Startup Flow

The original entry-point relationship is retained below, with the current
canonical locations shown in parentheses:

```text
shell login
  |-- .profile  -> .config/shell/profile       (Bash and POSIX shells)
  `-- .zprofile -> .config/shell/zprofile      (Zsh login shells)

startx
  `-- .xinitrc  -> .config/x11/xinitrc
        `-- .config/x11/xprofile
              `-- ssh-agent dwm

Xorg display manager
  `-- .xprofile -> .config/x11/xprofile
```

`.xinitrc` first sources `.config/x11/xprofile` and only falls back to the root
`.xprofile` when that configuration file is absent. The tracked `.xprofile`
link lets a display-manager login load the same X11 startup configuration.

## Layout

| Area | Main files | Purpose |
| --- | --- | --- |
| Shell | `.config/shell/profile`, `.config/shell/aliasrc`, `.config/zsh/.zshrc`, `.bashrc` | XDG environment, aliases, bookmarks, package commands, history, and completion |
| Login and X11 | `.zprofile`, `.profile`, `.xinitrc`, `.config/x11/` | Login flow, X startup, input method, compositor, wallpaper, Xresources, and key remaps |
| Desktop appearance | `.config/fontconfig/fonts.conf`, `.config/gtk-2.0/`, `.config/gtk-3.0/`, `.config/dunst/` | Arc GTK theme, Linux Libertine/Biolinum, CJK fallbacks, notifications |
| Audio and media | `.config/mpd/`, `.config/ncmpcpp/`, `.config/mpv/`, `.config/alsa/` | MPD/Ncmpcpp, MPV, PipeWire-oriented controls, retained ALSA fallback |
| File and document tools | `.config/lf/`, `.config/sxiv/`, `.config/zathura/`, `.config/mimeapps.list` | LF, image/document handlers, MIME defaults |
| Status bar and helpers | `.local/bin/statusbar/`, `.local/bin/` | DWM status modules and interactive helper scripts |
| Scheduled jobs | `.local/bin/cron/` | Package/RSS checks and cron toggle helper |
| System samples | `.local/share/sys-etc/*.template` | Per-machine templates for Portage, systemd-networkd, and wpa_supplicant |

The root entry points are tracked links:

```text
.profile   -> .config/shell/profile
.zprofile  -> .config/shell/zprofile
.xinitrc   -> .config/x11/xinitrc
.xprofile  -> .config/x11/xprofile
.asoundrc  -> .config/alsa/asoundrc
.gtkrc-2.0 -> .config/gtk-2.0/gtkrc-2.0
```

## Key Behavior

- Package aliases use a consistent `p` prefix: `pu` update, `pi` install,
  `pr` remove, `pse` search, `pp` information, `pl` list, and `pc` cleanup.
  APT, pacman, XBPS, and Portage are supported.
- PipeWire is managed by systemd user services. X startup does not launch
  PipeWire or PulseAudio manually. DWM volume keys and the volume status
  module use `wpctl`; `pulsemixer` remains the interactive mixer.
- Wallpaper handling is safe without pywal or a wallpaper. Tracked
  Xresources, Dunst, and Zathura defaults remain active. With `wal` installed,
  `setbg` additionally generates a color scheme.
- The input method is selected in one place in `.config/x11/xprofile`:
  `fcitx5`, then `fcitx`, then `ibus`. The selected engine sets GTK, Qt, and
  XMODIFIERS variables consistently.
- Package status modules support APT, pacman, XBPS, and Portage. Portage does
  not run an expensive dependency preview from the status bar; use `pu` for
  that check.
- Optional status modules exit quietly when their feature dependency is absent
  (for example, task-spooler and GeoIP lookup).

## Software Dependencies

This is the full command-level dependency inventory for a new machine. Package
names differ between distributions; command names below are the authoritative
reference. To use every tracked feature, install every group. A group may be
omitted only when its listed feature is intentionally unused.

The scripts also assume a normal GNU/Linux userland: `sh`, `bash`, `zsh`, GNU
coreutils, findutils, grep, sed, awk, util-linux (`setsid`, `lsblk`), procps
(`pgrep`, `pkill`, `pidof`, `ps`), `file`, and `sudo`.

### Base Shell and X11 Session

- `git`, `zsh`, `bash`, `python3` plus a `python` command, `vim` or `nvim`,
  `tmux`, `less`, `fzf`, `curl`, `wget`, `node`, and `npm`
- Xorg/Xinit, `dwm`, `dwmblocks`, `st`, `dbus-launch`, and
  `dbus-update-activation-environment`
- `dmenu`, `slock`, `dunst`, `picom`, `unclutter`, `xwallpaper`, `xrdb`,
  `xrandr`, `xset`, `xdotool`, `xdpyinfo`, `xclip`, `xprop`, `setxkbmap`, and
  `xkblayout-state`, plus `notify-send` from libnotify
- `fcitx5` for the selected input method and `xcape` for Caps-as-Escape
- `firefox` or another browser assigned to `BROWSER`
- `highlight`, `bat` or `batcat`, `fd`, `ripgrep`, `unzip`, `unrar`, and `w3m`
  for FZF and LF previews

The Zsh setup additionally expects Oh My Zsh and its configured plugins:
`zsh-autosuggestions`, `zsh-syntax-highlighting`,
`zsh-history-substring-search`, and `zsh-completions`. Bash completion needs
the distribution's Bash completion package and Git completion script.

`dwm`, `dwmblocks`, `dmenu`, and `st` are maintained outside this repository
at `~/src/dwm`, `~/src/dwmblocks`, `~/src/dmenu`, and `~/src/st` respectively.
Their local source and installation state must be managed separately.

### Appearance, Fonts, and Wallpaper

- Arc GTK theme, Adwaita icon theme, Linux Libertine, Linux Biolinum,
  Noto Sans CJK SC, Noto Serif CJK SC, Noto Sans Mono CJK SC,
  Noto Color Emoji, and FontAwesome fonts
- `wal` (pywal) for generated wallpaper colors; the default tracked colors
  remain usable without it
- `xwallpaper` for wallpaper display
- `lxappearance` is optional when changing GTK settings interactively

### Audio, Music, Recording, and Video

- PipeWire, `pipewire-pulse`, WirePlumber, and `wpctl`
- ALSA utilities and libraries for the retained ALSA configuration and the
  recording script's ALSA capture input
- `mpd`, `mpc`, `ncmpcpp`, `pamixer`, `pulsemixer`
- `mpv`, `socat`, and `ffmpeg`
- `slop` for selected-area screen recording; a V4L2 webcam device for webcam
  recording
- `sox` for `noisereduce`
- ImageMagick (`convert`) for `slider`
- `vorbiscomment`, `opustags`, `eyeD3`, and `metaflac` for `tag`

### File Management, Documents, and Desktop Handlers

- `lf`, `ueberzug`, `atool`, `mimeopen`, `vidir`, `sxiv`, `zathura`, `mpv`,
  `gimp`, ImageMagick (`display` and `convert`), `mediainfo`,
  `ffmpegthumbnailer`, `pdftoppm`, `odt2txt`, `gpg`, `man`, `col`, and
  `xdg-open`
- `neomutt` for `mail.desktop`; `newsboat` for RSS configuration
- `pdftotext` and `pdfinfo` for `getbib`
- `pass`, `pass-otp`, `zbarimg`, `maim`, `xclip`, and `dmenu` for password and
  OTP helpers
- `timedatectl` from systemd, or `chronyc` or `ntpdate`, for OTP time sync
- WPS Office, including the `wps-office-prometheus.desktop` entry, for the
  spreadsheet, document, and presentation MIME defaults

The tracked desktop entries call `st`, `lfub`, `sxiv`, `neomutt`, `zathura`,
`nvim`, `rssadd`, `transadd`, and `mpv`. All of those commands must be
available on a fully deployed desktop.

### Mounting, Display, Network, and System Controls

- `arandr`, `xrandr`, `bc`, `dmenu`, `dunst`, and `xwallpaper` for display
  selection
- `nmtui` and `nmcli` from NetworkManager for the network status-bar menu
- `xbacklight` for the battery module scroll action and `lm-sensors` for CPU
  temperature display when the hardware exports a CPU sensor
- `simple-mtpfs`, `udisks2`, `cifs-utils`, `smbclient`, `avahi-browse`, and a
  running Avahi daemon for USB, Android, and CIFS mount helpers
- `systemd`, `loginctl`, `systemctl`, `pstree`, and `slock` for `sysact`
- `geoiplookup` for the optional IP location module

### Status Bar, RSS, Mail, Weather, and Task Queue

- `htop`, `bmon`, `cal`, `calcurse`, `sensors`, `curl`, `nmtui`, `newsboat`,
  `neomutt`, `mbsync`, `tsp`, `transmission-remote`, `wpctl`, and
  `pulsemixer`
- `dwmblocks` must run if the status modules are used; scripts signal it with
  real-time signals after interactive actions
- `wttr.in` network access is used by forecast and moon-phase modules;
  Doppler and price modules also require outbound HTTPS access
- `urlscan` and `youtube-viewer` are used by Newsboat URL and video macros

The package status modules require one supported package manager: APT,
pacman, XBPS, or Portage. The APT check scripts additionally use `sudo`.

### Downloads, Torrents, and Online Media

- `yt-dlp`, `curl`, `tsp`, and `entr` for queued downloads and Newsboat queue
  monitoring
- `transmission-daemon`, `transmission-remote`, `transmission-show`, and
  `tremc` for torrent helpers and the torrent status module
- `lynx` for the text-browser option in `dmenuhandler`
- `urlview` and Facebook PathPicker (`fpp`) for the configured tmux bindings

### Compilation, Typesetting, and Data Helpers

Install the tools for every source format that `compiler` is expected to
handle:

| Source format or helper | Commands |
| --- | --- |
| TeX and bibliography | `pdflatex`, `xelatex`, `biber` |
| Groff, mom, and ms | `preconv`, `refer`, `groff` |
| Markdown | `lowdown` or `groffdown`, otherwise `pandoc` |
| Org mode | `emacs` with Org and LaTeX export support |
| R Markdown | `Rscript` with the `rmarkdown` package |
| C, C++, C#, Go, Java, Rust | `cc`, `g++`, `mcs`, `mono`, `go`, `javac`, `java`, `cargo` |
| Octave, Sass, OpenSCAD, Sent | `octave`, `sassc`, `openscad`, `sent` |
| Build and LaTeX cleanup | `make`, GNU `find`, and `rm` |
| Audiobook splitting | `ffmpeg`, `iconv` |

### System Templates

The files below are templates, not automatically installed system
configuration. Install only the matching stack on the target machine before
copying and adapting a template:

- `.local/share/sys-etc/portage/make.conf.template`: Portage and `emerge`
- `.local/share/sys-etc/systemd/network/wireless.network.template`:
  systemd-networkd and `networkctl`
- `.local/share/sys-etc/wpa_supplicant/wpa_supplicant.conf.template`:
  `wpa_supplicant`

### Cron

The cron helpers require `cron`, `crontab`, `notify-send`, `xdotool`,
`newsboat`, and a running user DBus session. The example in
`.local/bin/cron/README.md` sets `DISPLAY` and `DBUS_SESSION_BUS_ADDRESS`, then
sources `.profile`.

`checkup` runs `sudo apt update`. For unattended cron use, configure an
appropriate narrowly scoped passwordless sudo rule or run the check manually;
cron cannot answer a sudo password prompt.

### Current Machine Gaps

This section is a local verification record, not the deployment requirement.
At the last review, `mpc`, `sxiv`, `nmtui`, `cal`, `calcurse`, and
`xbacklight` were absent. Their tracked features remain configured and need
the corresponding commands above on a fully deployed machine.

## Current Review Status

Completed:

- Verified tracked root symbolic links and key shell script syntax.
- Consolidated package aliases and package-status behavior across supported
  package managers.
- Switched status volume actions to `wpctl` while retaining the ALSA fallback
  configuration and `pulsemixer` UI.
- Made wallpaper/pywal behavior optional and preserved static defaults.
- Validated PipeWire user-service ownership; no duplicate X-session startup.
- Hardened optional helper scripts for missing dependencies and failed queues.
- Fixed status-bar launch behavior, task-spooler handling, keyboard-layout
  fallback, image MIME declarations, and cron environment documentation.
- Reviewed display, mount, and brightness helpers. Android MTP mounting now
  retries only after the initial authorization failure, and `xlight` handles
  an absent saved-brightness file safely.
- Unified URL wallpaper selection in `dmenuhandler` with `setbg`; successful
  downloads now refresh the wallpaper and optional wal colors, while failed
  downloads preserve the current desktop state.
- Hardened URL file handling in `dmenuhandler` and `linkhandler` with unique
  temporary files and HTTP error handling before opening downloaded content.
- Completed the first-round review of general helper scripts: device and
  display control, file and MIME handling, RSS/download/torrent workflows,
  media tools, document helpers, system helpers, and system templates.
- Corrected edge cases in recording control, slideshow and audiobook timecode
  parsing, PeerTube/RSS handling, document compilation, and helper error
  reporting.
- Checked status modules in the current environment. CPU temperature stays
  blank because the system exposes no CPU thermal sensor; NVMe temperature is
  intentionally not shown as CPU temperature.

Known deferred items:

- Keep `sb-internet` configured for `nmtui`; install NetworkManager when its
  interactive connection menu is needed.
- Install `sxiv` before using the configured image MIME handler.
- Install `cal`/`calcurse` and `xbacklight` only if their status-bar click and
  scroll functions are wanted.
- Keep the existing ALSA configuration until the PipeWire setup has remained
  stable in normal use.

## TODO: Voidrice Inspiration Review

This repository began as a personal adaptation of
[voidrice](https://github.com/LukeSmithxyz/voidrice). The following items were
reviewed against Voidrice commit `0e8bd85`; they are candidates for focused
discussion, not planned changes. Work through them one at a time and preserve
the current cross-distribution, optional-dependency behavior.

- [x] Add `sysact` lock integration: when available, mute the PipeWire default
  sink and pause MPD/MPV while locked, then restore only a previously unmuted
  sink. Playback is deliberately not resumed; successful PipeWire changes
  refresh the DWMBlocks volume block, while an enabled music block refreshes
  itself through its existing MPD watcher.
- [ ] Improve `displayselect`: filter displays by exact output name and pass
  `--primary` to `xrandr` for the selected primary monitor. Test it on an
  actual multi-monitor X11 session before keeping the change.
- [ ] Improve `opout` PDF discovery: locate the compiled PDF when a document
  compiler writes outside the source directory or uses a root file. Define
  the search boundary and behavior for multiple matching PDFs first.
- [ ] Design an RSS feed discovery helper inspired by `rssget`: accept a URL
  or clipboard URL, discover declared feeds and offer a selection before
  calling `rssadd`. Implement a portable, bounded version rather than copying
  Voidrice's hard-coded Invidious instances and fixed temporary file.
- [ ] Evaluate optional `latexmk` support with an output directory, XeLaTeX,
  and SyncTeX. It must remain opt-in and agree with `compiler`, `opout`, and
  the existing direct TeX workflow.
- [ ] Evaluate selected LF preview additions from Voidrice, such as AVIF,
  DjVu, SVG, XCF, and EPUB. Add formats only when the preview command and its
  dependency are useful on this machine; retain the current `bat`/`batcat`/`sed`
  text-preview fallback.
- [ ] Evaluate migration from `sxiv` to `nsxiv`: compare the current MIME
  handler, key-handler behavior, desktop entry, and required package name;
  migrate them together only after interactive image-viewing tests pass.
- [ ] Evaluate asynchronous DWMBlocks modules only after inspecting the local
  DWMBlocks source at `~/src/dwmblocks` and its signal configuration. Voidrice's
  implementation relies on a compatible patched status-bar architecture and
  should not be copied into the current setup blindly.

Not adopting under the current configuration decisions:

- [x] Do not add Voidrice's PipeWire/WirePlumber X-session autostart. These
  services are owned by systemd user units here.
- [x] Do not replace the existing mount helpers with Voidrice's Bash-heavy
  `mounter`/`unmounter` scripts. Their LUKS assumptions and dependencies do
  not match every target system.
- [x] Do not restore Tor wrapping or Voidrice-specific Firefox, Neovim, and
  Python configuration. They are outside the current repository's intended
  scope.
- [x] Do not adopt Voidrice's `xdg-terminal-exec` unchanged. It only wraps
  `$TERMINAL -e` and provides no fallback or desktop-entry registration;
  revisit only when a concrete terminal-launch integration needs it.

## TODO: Resume the Review

Use this checklist to continue after an interruption. Do not make a change
before reviewing the affected tracked file and its runtime dependency.

- [x] Check bare repository operation, tracked links, shell startup, and `c`
  completion.
- [x] Check X11 startup, input method selection, wallpaper/pywal fallback,
  PipeWire interaction, fonts, GTK, and Xresources.
- [x] Check the status-bar modules for syntax and current environment issues.
- [x] Check cron documentation, MIME image association, and package manager
  portability.
- [x] Review display, mount, and brightness helpers: `displayselect`,
  `dmenumount*`, `dmenuumount`, and `xlight`.
- [x] Complete the first-round static and semantic review of tracked general
  helper scripts, including file/MIME, download/torrent, media, document, and
  system helper groups.
- [ ] Review remaining configuration files for obsolete settings and
  distribution-specific assumptions without removing trusted personal values.
- [ ] Test interactive X-session paths after installing deferred dependencies:
  `nmtui`, `sxiv`, calendar, brightness, screenshots, OTP, MTP/CIFS mounts,
  torrents, recording selection, and RSS download queue.
- [ ] Recheck feature dependencies after installation: `mpc`, NetworkManager,
  image and preview tools, task-spooler, Transmission, media metadata tools,
  and the required compiler toolchains.
- [ ] Decide whether ALSA fallback files can be removed after a sustained
  PipeWire-only test.
- [ ] Recheck cron scheduling and the sudo policy before enabling unattended
  package checks.
- [ ] Update this dependency list whenever a tracked feature or its required
  command changes.

## Repositories

1. LukeSmithxyz/voidrice
2. ohmyzsh/ohmyzsh
3. gpakosz/.tmux
4. junegunn/fzf
5. nvbn/thef*ck
6. ggreer/the_silver_searcher
7. pulsemixer

## Thanks

[luke smith] Inspiration comes from him. This dotfiles based his LARBS.
I keep the folder: .local/share/larbs.

[Nicola Paolucci] The management of dotfiles comes from him.

[Gregory Pakosz] The tmux config comes from him. <https://github.com/gpakosz/.tmux>

[Oh My Zsh] The zsh config comes from them.

## License

The License file in .local/share/larbs
GPL3 © darkroam
