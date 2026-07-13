# TODO History

## Recent Documented Changes

- [x] Rewrote `architecture.md` as the Codex/developer design document and
  `desktop-guide-zh.md` as the self-contained user operation guide. Both now
  use the ten dependency layouts; maintenance policy fixes their distinct
  audience and content boundaries. Repository-wide documentation checks passed
  for terminology, links, paths, layout coverage, and document relationships.

- [x] Static credential scanning found no private keys or high-confidence token
  patterns in the current tree or reachable history. The tracked Git identity
  and existing historical author metadata are intentionally retained.

- [x] `11b758e`: selected Microsoft Edge through `BROWSER` and removed the
  remaining Firefox-specific DWM rule.
- [x] `66846b6`: moved LF icons into `.config/lf/icons`.
- [x] `ac3e17b`: added the cache-aware `weath` helper.
- [x] `ddd0693`: made `samedir` handle the active terminal/LF process tree.
- [x] `f228040`, `f7c5cfd`, `a84bd30`: recorded brightness, graphical, and
  TeX proposals as deferred rather than changing untested behavior.
- [x] `f99558e`: added LF previews for additional image/document formats.
- [x] `342b643`: added RSS feed discovery through `rssget` and hardened
  `rssadd`.
- [x] `c1181c1`: integrated PipeWire-aware muting into lock handling.
- [x] `508d029`: made PATH initialization idempotent across shell and X11
  startup.
- [x] `89d9aa8`: hardened shell command configuration, including the bare Git
  command completion path.
- [x] `7deada6`: completed and recorded the first-round configuration review.

## First-Round Configuration Review

- [x] Verified bare-repository operation, root symbolic links, shell startup,
  and `c` completion.
- [x] Checked X11 startup, input-method selection, wallpaper/pywal fallback,
  PipeWire ownership, fonts, GTK, and Xresources.
- [x] Checked status modules for syntax and current-environment issues. CPU
  temperature remains blank when no CPU thermal sensor is exposed; NVMe
  temperature is intentionally not treated as CPU temperature.
- [x] Checked cron documentation, MIME image association, and package-manager
  portability.
- [x] Reviewed display, mount, and brightness helpers. Android MTP retry is
  limited to initial authorization failure; `xlight` tolerates no saved state.
- [x] Completed static and semantic review of general helpers: file/MIME,
  downloads/torrents, media, documents, system helpers, and templates.
- [x] Corrected recording control, slideshow/audiobook timecode parsing,
  PeerTube/RSS, document compilation, and helper error reporting edge cases.
- [x] Hardened optional helpers for absent dependencies and failed queues.

## Voidrice-Inspired Work Adopted

- [x] Added `sysact` lock integration: mute the PipeWire default sink and pause
  MPD/MPV while locked, restoring only a previously unmuted sink. Playback is
  not automatically resumed; volume refreshes DWMBlocks.
- [x] Added `rssget`: accept URL or clipboard URL, discover feeds, offer a
  selection, and call `rssadd` using bounded requests and unique temporary
  files.
- [x] Added LF previews for AVIF, DjVu, SVG, XCF, and NDJSON fallback.
- [x] Moved LF icons into `.config/lf/icons` so all LF launch paths agree.
- [x] Hardened `samedir` through active-window process-tree lookup while
  retaining shell/LF fallbacks.
- [x] Replaced the stale weather alias with `weath` using the shared XDG cache.

## Other Completed Decisions

- [x] Standardized package aliases with `p`, `pu`, `pi`, `pr`, `pse`, `pp`,
  `pl`, and `pc` across APT, pacman, XBPS, and Portage.
- [x] Switched status-volume actions to `wpctl` while retaining ALSA fallback
  configuration and the `pulsemixer` interface.
- [x] Made wallpaper/pywal behavior optional while preserving static defaults.
- [x] Kept PipeWire user-service ownership and removed duplicate X-session
  startup.
- [x] Unified URL wallpaper selection through `setbg`; successful downloads
  refresh optional wal colors and failed downloads preserve desktop state.
