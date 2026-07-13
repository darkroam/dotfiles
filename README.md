# dotfiles

Personal Linux configuration managed as a bare Git repository. Tracked files
are intended to work from `$HOME`; untracked files are deliberately outside the
repository.

Last reviewed: 2026-07-14.

## Repository Usage

The repository is `$HOME/.cfg`, with `$HOME` as its work tree:

```sh
alias c='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'
```

Use `c status`, `c diff`, `c add <path>`, and `c commit` for configuration
changes. Zsh and Bash provide completion for `c`; `c diff <Tab>` only offers
files that currently have diffs.

## Installation

Bootstrap tracking in `$HOME` with the existing installer:

```sh
curl -Lks https://github.com/darkroam/dotfiles/raw/master/.local/bin/install.sh | /bin/bash
```

It clones the bare repository into `$HOME/.cfg`, checks out tracked files into
`$HOME`, backs up checkout conflicts to `.config-backup`, and hides untracked
files from `c status`. Review the installer before using it on a machine with
existing configuration.

Install the required programs before expecting every optional feature to work:
[full dependency inventory](.local/share/docs/project/dependencies.md).

## Startup Flow

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

`.xinitrc` sources `.config/x11/xprofile` first and falls back to the root
`.xprofile` only if the canonical file is absent. The tracked `.xprofile` link
ensures display-manager logins use the same X11 startup configuration.

The tracked root entry points are links:

```text
.profile   -> .config/shell/profile
.zprofile  -> .config/shell/zprofile
.xinitrc   -> .config/x11/xinitrc
.xprofile  -> .config/x11/xprofile
.asoundrc  -> .config/alsa/asoundrc
.gtkrc-2.0 -> .config/gtk-2.0/gtkrc-2.0
```

## Documentation

Maintenance documentation lives in `.local/share/docs/`; retained LARBS
runtime resources remain in `.local/share/larbs/`:

- [Architecture and design](.local/share/docs/project/architecture.md): directory
  map, load order, optional-feature model, and ownership boundaries.
- [Display management analysis](.local/share/docs/project/display-management.md):
  current X11 display-switching relationships, system-service boundaries, and
  retained device-local hooks.
- [Dependencies](.local/share/docs/project/dependencies.md): complete
  command-oriented installation inventory for a new machine.
- [Maintenance policy](.local/share/docs/project/maintenance-policy.md): project
  constraints plus accepted and rejected design directions.
- [Current TODO](.local/share/docs/planning/todo.md): active work only.
- [Suspended items](.local/share/docs/planning/suspended.md): deferred work and the
  conditions required to resume it.
- [TODO history](.local/share/docs/planning/history.md): completed review and
  implementation record.
- [LARBS guide in Chinese](.local/share/docs/user/desktop-guide-zh.md): a
  localized guide based on this repository's current behavior.
- [Chinese keybinding cheat sheet](.local/share/docs/user/keybindings-zh.md):
  concise DWM and media-key reference.

The DWM `Mod+F1` binding still opens the upstream installed guide at
`/usr/local/share/dwm/larbs.mom`; the localized documents are maintained in
this repository and intentionally do not alter the separately built DWM source.

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
