# Known issues

## Font increase blanks the scrollback (parked)

**Symptom:** pressing cmd-+ (increase font size) when the terminal has more than one screen of
output blanks the scrollback — scrolling up shows empty lines, the data appears lost. Decreasing
the font (cmd--) is fine; it only happens on increase, and only when there is scrollback.

**Isolation:**
- Vanilla Ghostty.app: not affected.
- cmux (another libghostty embedder): not affected.
- macterm: affected.
- agt: affected — and agt's libghostty integration is adapted from macterm.

So this is the **macterm-style embedding**, not libghostty itself. agt holds a fixed-pixel pane and
only *records* the font change (`GHOSTTY_ACTION_CELL_SIZE` → `reportFontSize`); it does not resize
on a font change. A font increase therefore makes libghostty re-flow into a **shrinking grid**,
which blanks the scrollback. Vanilla avoids this by growing its window so the grid never shrinks;
cmux avoids it with a **custom NSScrollView scrollback architecture** (it reimplements scrollback
natively instead of using ghostty's built-in scrollback).

**Tried, did not fix:**
- Re-asserting `ghostty_surface_set_size` with the same pixel dims on `CELL_SIZE` — libghostty
  short-circuits an identical size, so no re-flow happens.
- Forcing a re-flow via an off-by-one `set_size(w, h-1)` → `set_size(w, h)` on `CELL_SIZE` — no
  change, so the blanking is not merely a stale-display issue a re-flow can repair.
- (2026-06-20) `ghostty_surface_refresh` on the font-change path (`reportFontSize`) — no repaint.
- (2026-06-20) the off-by-one `set_size` recompute above PLUS `ghostty_surface_refresh` — still no
  repaint. But a `ghostty_surface_read_text(GHOSTTY_POINT_SCREEN)` probe shows the full screen+scrollback
  is STILL in the buffer (~8k chars) while the pane is blank, so this is a render bug, not data loss.

**Leads for a real fix (future):** match the working embedders — either grow the surface on a font
change (hard in the fixed `NavigationSplitView` pane), or move to a cmux-style native scrollback;
or bump the pinned `thdxg/ghostty` build (a newer libghostty may fix the shrink-reflow). cmux uses an
absolute `set_font_size:<points>` binding action (note: an absolute set-font-size binding does
exist, contrary to an earlier assumption).

**Correction (2026-06-20): the buffer is intact — this is a render bug, not data loss.** A
`ghostty_surface_read_text(GHOSTTY_POINT_SCREEN)` probe in `reportFontSize` returns the full
screen+scrollback (~8k chars) after each font increase, while the pane shows blank. So the scrollback is
NOT re-flowed away — libghostty keeps the data; the Metal renderer just paints the scrollback region empty
once the grid shrinks. This is the SAME class as the split-toggle re-parent blank (also buffer-intact,
there fixed by `ghostty_surface_refresh`), but harder: neither `refresh` nor a forced grid recompute
(`set_size` jitter + `refresh`) repaints it, and a font change doesn't resize the view so the split-toggle
fix in `updateMetalLayerSize` never fires here. The real fix is still one of the leads above, but it
targets the RENDERER (the data is present), not buffer preservation.
