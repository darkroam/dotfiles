# Important Note

These cronjobs have components that require information about your current display to display notifications correctly.

When you add them as cronjobs, I recommend you precede the command with commands as those below:

```
export DBUS_SESSION_BUS_ADDRESS="unix:path/$XDG_RUNTIME_DIR/bus"; export DISPLAY="$DISPLAY"; . "$HOME/.profile"; then_command_goes_here
```

This ensures that notifications will display, xdotool commands will function and environmental variables will work as well.

Put this in the graphical session when creating the crontab, so `$XDG_RUNTIME_DIR` and `$DISPLAY` are that session's values. Do not hard-code `:0`.

`sb-forecast2` already refreshes when the status bar starts and the cache is not from today. Add this so the cache is fetched four times a day. It does not need `DISPLAY`.

```
0 */6 * * * "$HOME/.local/bin/statusbar/sb-forecast2" --refresh
```
