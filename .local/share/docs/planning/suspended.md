# Suspended Items

These items are deliberately not active. Resume only when the stated condition
is available; they are not defects in the normal configuration.

## X11 Display and Images

- [ ] `displayselect`: use exact output-name filtering and set the selected
  primary output with `xrandr --primary`. Test the complete layout flow in a
  real multi-monitor X11 session before keeping a change.

## Documents

- [ ] Improve `opout` PDF discovery only after deciding how compilers that use
  root files or external output directories should be searched.
- [ ] Evaluate optional `latexmk` only after installing the TeX toolchain and
  choosing an output-directory policy compatible with `compiler` and `opout`.

## Status and Hardware

- [ ] Consider asynchronous DWMBlocks network modules only if more network
  blocks are enabled or the current two-second forecast bound causes observed
  lag. Do not copy upstream indefinite retries.
- [ ] Unify brightness controls when a usable backend is selected. This machine
  exposes no standard `/sys/class/backlight` device; reconcile `xlight`,
  `xbacklight`, and status-bar actions then.
- [ ] Add global MPV IPC coverage only when pause control must include
  non-shell launches. Use a small tracked wrapper rather than the unreviewable
  upstream Lua submodule.
- [ ] Consider a market ticker only with selected symbols, a maintained source,
  and an acceptable network update policy.
