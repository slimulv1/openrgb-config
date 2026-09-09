#!/usr/bin/env bash
# Wait for I2C ACL readiness, launch OpenRGB server, then POLL the SDK until
# ALL expected controllers are enumerated (not counting from log files, which
# are written asynchronously and caused missed devices on boot). Then apply
# the color scheme and VERIFY the controllers are still alive.
# Exit 1 on failure → systemd Restart=always retries until hardware is ready.
set -u

BIN="${OPENRGB_BIN:-/usr/bin/openrgb}"
SCHEME="${OPENRGB_SCHEME:-white}"
APPLY_RGB="${APPLY_RGB:-$HOME/.local/bin/apply-rgb}"
I2C_WAIT_S="${I2C_WAIT_S:-30}"
DETECT_WAIT_S="${DETECT_WAIT_S:-60}"
EXPECT_CONTROLLERS="${EXPECT_CONTROLLERS:-3}"
CMD_TIMEOUT="${OPENRGB_TIMEOUT:-15}"

# --- Wait for /dev/i2c-* ACL (race after session restart) ---
i2c_ready() {
    local d
    for d in /dev/i2c-*; do
        [ -e "$d" ] || continue
        # ready if effective read+write works (covers BOTH udev uaccess ACL
        # "user:USER:rw" AND i2c-group membership from i2c-tools 45-*.rules)
        if getfacl -p "$d" 2>/dev/null | grep -qE "^user:${USER}:rw"; then continue; fi
        [ -r "$d" ] && [ -w "$d" ] || return 1
    done
}

_i=0
while ! i2c_ready; do
    ((_i++))
    ((_i >= I2C_WAIT_S)) && { logger -t openrgb-wrapper "TIMEOUT i2c ACL after ${I2C_WAIT_S}s"; break; }
    sleep 1
done
((_i > 0)) && logger -t openrgb-wrapper "i2c ACL ready after ${_i}s"

# --- Launch OpenRGB server (no profile; scheme applied after detection) ---
"$BIN" --server --noautoconnect &
PID=$!

# --- Poll the SDK device list until all expected controllers appear ---
# (openrgb -l talks to the running server; network protocol is deterministic,
#  unlike scraping OpenRGB log files which are flushed asynchronously)
sdk_list() {
    timeout "$CMD_TIMEOUT" "$BIN" -l 2>/dev/null | grep -E '^[0-9]+:'
}
controller_count() { sdk_list | sed -n 's/^\([0-9]\+\):.*/\1/p' | wc -l; }

devs=""
_end=$((SECONDS + DETECT_WAIT_S))
while ((SECONDS < _end)); do
    sleep 3
    devs="$(sdk_list)"
    n="$(printf '%s\n' "$devs" | grep -cE '^[0-9]+:')" || n=0
    ((n >= EXPECT_CONTROLLERS)) && break
done

n="$(printf '%s\n' "$devs" | grep -cE '^[0-9]+:')" || n=0
if ((n >= EXPECT_CONTROLLERS)); then
    if ! "$APPLY_RGB" "$SCHEME" >/dev/null 2>&1; then
        logger -t openrgb-wrapper "FAIL apply-rgb '$SCHEME' after ${n} controllers"
        kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null
        exit 1
    fi
    # Verify controllers still alive after scheme application
    after="$(controller_count)"
    logger -t openrgb-wrapper "OK: ${n} controllers; applied scheme '$SCHEME'"
    ((after >= EXPECT_CONTROLLERS)) && exit 0
    logger -t openrgb-wrapper "WARN: only ${after} controllers after apply"
    kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null
    exit 1
fi

logger -t openrgb-wrapper "Only ${n} controllers (need >= ${EXPECT_CONTROLLERS})"
kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null
exit 1