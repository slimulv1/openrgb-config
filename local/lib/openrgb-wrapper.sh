#!/usr/bin/env bash
# Wait for I2C ACL readiness, launch OpenRGB, verify controller detection.
# Exit 1 if 0 controllers → systemd Restart=retries until hardware is ready.
set -u

BIN="${OPENRGB_BIN:-/usr/bin/openrgb}"
LOGDIR="${XDG_CONFIG_HOME:-$HOME/.config}/OpenRGB/logs"
SCHEME="${OPENRGB_SCHEME:-white}"
APPLY_RGB="${APPLY_RGB:-$HOME/.local/bin/apply-rgb}"
I2C_WAIT_S="${I2C_WAIT_S:-30}"
DETECT_WAIT_S="${DETECT_WAIT_S:-15}"
MIN_CONTROLLERS="${MIN_CONTROLLERS:-1}"

# --- Wait for /dev/i2c-* ACL (race after session restart) ---
i2c_ready() {
    local d
    for d in /dev/i2c-*; do
        [ -e "$d" ] || continue
        getfacl -p "$d" 2>/dev/null | grep -qE "^user:${USER}:rw" || return 1
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
sleep "$DETECT_WAIT_S"

# Count detected controllers from latest log
LATEST_LOG="$(ls -1t "$LOGDIR"/OpenRGB_*.log 2>/dev/null | head -1)"
CONTROLLERS=0
[ -n "$LATEST_LOG" ] && CONTROLLERS="$(grep -c 'Registering RGB controller' "$LATEST_LOG" 2>/dev/null || true)"

if ((CONTROLLERS >= MIN_CONTROLLERS)); then
    # Detection OK → apply default color scheme via apply-rgb
    "$APPLY_RGB" "$SCHEME" >/dev/null 2>&1
    logger -t openrgb-wrapper "OK: ${CONTROLLERS} controllers; applied scheme '$SCHEME'"
    exit 0
fi

logger -t openrgb-wrapper "Only ${CONTROLLERS} controllers (need >= ${MIN_CONTROLLERS})"
kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null
exit 1
