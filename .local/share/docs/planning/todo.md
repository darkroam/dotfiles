# Current TODO

Only active work belongs here. Before changing a tracked file, inspect its
runtime dependency and preserve optional-dependency behavior.

- [ ] Review remaining configuration files for obsolete settings and
  distribution-specific assumptions without removing trusted personal values.
- [ ] Test the interactive X11 paths after installing their dependencies:
  `nmtui`, `sxiv`, calendar, brightness, screenshots, OTP, MTP/CIFS mounts,
  torrents, recording selection, and RSS download queue.
- [ ] Recheck dependencies after installation: `mpc`, NetworkManager, image
  and preview tools, task-spooler, Transmission, media metadata tools, and the
  required compiler toolchains.
- [ ] Decide whether retained ALSA fallback files can be removed after a
  sustained PipeWire-only test.
- [ ] Recheck cron scheduling and the sudo policy before enabling unattended
  package checks.
- [ ] Decide whether to rewrite published Git history to remove historical
  author/committer email metadata and the old tracked `.gitconfig` identity.
  This requires a coordinated force-push and must not be done casually.
- [ ] Update `dependencies.md` whenever a tracked feature or required command
  changes.

For intentionally paused work, see [suspended items](suspended.md). Completed
items are recorded in [TODO history](history.md).
