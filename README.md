# dotfiles

Personal Linux configuration managed as a bare Git repository. Tracked files
are intended to work from `$HOME`; untracked files are deliberately outside the
repository.

Last reviewed: 2026-07-18.

## Repository Usage

The repository is `$HOME/.cfg`, with `$HOME` as its work tree:

```sh
alias c='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'
```

Use `c status`, `c diff`, `c add <path>`, and `c commit` for configuration
changes. Zsh and Bash provide completion for `c`; `c diff <Tab>` only offers
files that currently have diffs.

## Installation

Before bootstrap, install `curl`, Git, an OpenSSH client, Bash, and the standard
GNU file utilities. Configure GitHub SSH access because the repository remote
uses `git@github.com`. Download and inspect the installer before running it:

```sh
installer=$(mktemp)
curl -fsSL https://github.com/darkroam/dotfiles/raw/master/.local/bin/install.sh -o "$installer"
sed -n '1,240p' "$installer"
/bin/bash "$installer"
rm -f "$installer"
unset installer
```

It first clones into a temporary private directory and preflights tracked targets,
including file or symlink ancestors that would block a nested path. It then backs
up conflicts to the Git-ignored, mode `0700` `.config-backup`, preserving their
directory structure; activates `$HOME/.cfg`; checks out into `$HOME`; and hides
untracked files from `c status`. It refuses to follow a symlinked backup root or
overwrite an existing repository, backup parent, or backup target.

Install the required programs before expecting every optional feature to work:
[full dependency inventory](.local/share/docs/project/dependencies.md).

The X11 desktop also uses four separately maintained source repositories. After
installing the compiler, headers, and target-platform packages listed in the
dependency inventory and platform profile, clone, build, and install them:

```sh
mkdir -p "$HOME/src"
for repo in dmenu st dwmblocks dwm; do
  git clone "https://github.com/darkroam/$repo" "$HOME/src/$repo"
  make -C "$HOME/src/$repo"
  sudo make -C "$HOME/src/$repo" install
done
```

They remain independent Git repositories; the bare dotfiles installer does not
clone, build, or commit them.

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
- [Display management design](.local/share/docs/project/display-management.md):
  shared X11 ownership, state model, layout policy, validation, and diagnostics.
- [Display device adapter guide](.local/share/docs/project/display-device-adapter.md):
  the planned single-file extension contract for nonstandard hardware.
- [Dependencies](.local/share/docs/project/dependencies.md): complete
  command-oriented, distribution-neutral capability inventory.
- [Platform profiles](.local/share/docs/platforms/index.md): per-device and
  per-distribution package mappings, system facts, validation, and recovery.
- [Cross-platform audit](.local/share/docs/planning/dependency-audit.md): reusable
  code, dependency, runtime, documentation, and platform-boundary checks.
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

The DWM `Mod+F1` binding opens the installed English guide generated from the
separately maintained DWM source. Localized documents remain in this repository.

## Repositories

1. LukeSmithxyz/voidrice
2. ohmyzsh/ohmyzsh
3. gpakosz/.tmux
4. junegunn/fzf
5. nvbn/thef*ck
6. ggreer/the_silver_searcher
7. pulsemixer
8. zx2c4/password-store

## Thanks

[luke smith] Inspiration comes from him. This dotfiles based his LARBS.
I keep the folder: .local/share/larbs.

[Nicola Paolucci] The management of dotfiles comes from him.

[Gregory Pakosz] The tmux config comes from him. <https://github.com/gpakosz/.tmux>

[Oh My Zsh] The zsh config comes from them.

[Password Store] The tracked X11 passmenu is adapted from its dmenu example and retains the
upstream GPL-2.0-or-later copyright notice. <https://www.passwordstore.org/>

## License

The License file in .local/share/larbs
GPL3 © darkroam
