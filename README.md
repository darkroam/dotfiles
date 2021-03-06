# dotfiles

## Relation

my dotfiles for linux

startx -- .xinitrc
             |------.profile  --> for bash
	     \------.zprofile --> for zsh

xorg -- .xprofile


## Repositories

1. LukeSmithxyz/voidrice
2. ohmyzsh/ohmyzsh
3. gpakosz/.tmux
4. junegunn/fzf
5. nvbn/thef*ck
6. ggreer/the_silver_searcher
7. pulsemixer

## Install

Install config tracking in your $HOME by runinng:

	`curl -Lks https://github.com/darkroam/dotfiles/raw/master/.local/bin/install.sh | /bin/bash`

## Thanks

[luke smith] Inspiration comes from him. This dotfiles based his LARBS.
	I keep the folder: .local/share/larbs.

[Nicola Paolucci] The management of dotfiles comes from him.

[Gregory Pakosz] The tmux config comes from him. <https://github.com/gpakosz/.tmux>

[Oh My Zsh] The zsh config comes from them.

## Others

[2020-02-29] I try to restart my dotfile config.
[2020-03-08] .config/mpd/mpd.conf does not modify.
	     I did not config the [sxiv vifm wget] app.
[2020-04-22] mv .xinitrc .xprofile to .config/, ln .profile -> .zprofile

## License

The License file in .local/share/larbs
GPL3 © darkroam
