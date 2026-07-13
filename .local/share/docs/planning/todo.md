# Current TODO

Only active work belongs here. Before changing a tracked file, inspect its
runtime dependency and preserve optional-dependency behavior.

- [ ] Review remaining configuration files for obsolete settings and
  distribution-specific assumptions without removing trusted personal values.
- [ ] Rewrite the architecture and desktop guide by the ten dependency layouts.
  - Rewrite `project/architecture.md` for Codex/developers: canonical paths,
    file and runtime relationships, layout ownership and hierarchy, design
    decisions, extension boundaries, and maintenance constraints. Remove
    user-operation, shortcut, and troubleshooting instruction from this file.
  - Rewrite `user/desktop-guide-zh.md` for users: installation and first
    session, daily operations, shortcuts, personal customization, and
    troubleshooting within each layout. Remove implementation details that
    are unnecessary for normal use.
  - Add an explicit audience and content-boundary rule to
    `project/maintenance-policy.md`, then verify that both documents are
    self-contained, use the exact `dependencies.md` layout names, and do not
    require the other document to be understood.
  - Check README navigation, Markdown links, terminology, layout coverage,
    and user-visible behavior before requesting review.
- [ ] Test the interactive X11 paths after installing their dependencies:
  `nmtui`, `nsxiv`, calendar, brightness, screenshots, OTP, MTP/CIFS mounts,
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
