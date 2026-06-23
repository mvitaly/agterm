#!/usr/bin/env bash
# agterm-agent-status — set the current agterm session's agent-status indicator.
#
#   agterm-agent-status.sh active            # agent is busy
#   agterm-agent-status.sh completed         # agent finished a turn
#   agterm-agent-status.sh blocked  --blink  # agent is waiting on you (pulse for attention)
#   agterm-agent-status.sh idle              # clear the indicator
#
# States: idle | active | completed | blocked. An optional --blink / --auto-reset
# (and any further args) is forwarded verbatim to `agtermctl session status`.
#
# Outside agterm this is a silent no-op, so it is safe to call from any hook.
#
# As a hook it must never interfere with the agent: stdout/stderr are suppressed
# (Claude Code injects a UserPromptSubmit/SessionStart hook's stdout into the
# prompt context) and it always exits 0 (a non-zero exit can block the turn).
#
# agtermctl resolution order (the binary that talks to the control socket):
#   1. $AGTERMCTL — an explicit override the caller set.
#   2. the absolute bundled-binary path the installer bakes in: the installer
#      rewrites the AGTERMCTL default below to agterm.app's Contents/MacOS/agtermctl,
#      so the hook fires even when the CLI was never symlinked into PATH.
#   3. `agtermctl` on PATH — the fallback when nothing above resolved.
set -u

[ -n "${AGTERM_SESSION_ID:-}" ] || exit 0   # not inside agterm: nothing to do

# --socket is a SUBCOMMAND option, so it must come AFTER `session status`, not before
# it. Pass it only when AGTERM_SOCKET is set (the app injects it alongside the id).
state=$1
shift
if [ -n "${AGTERM_SOCKET:-}" ]; then
  "${AGTERMCTL:-agtermctl}" session status "$state" \
    --target "$AGTERM_SESSION_ID" --socket "$AGTERM_SOCKET" "$@" >/dev/null 2>&1 || true
else
  "${AGTERMCTL:-agtermctl}" session status "$state" \
    --target "$AGTERM_SESSION_ID" "$@" >/dev/null 2>&1 || true
fi
exit 0
