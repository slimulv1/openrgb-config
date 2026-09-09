#!/usr/bin/env bash
# Wait until BOTH critical paths are ready — the I801 SMBus where the
# Kingston DRAM lives (probed with i2cdetect, not guessed from ACLs) AND the
# /dev/hidraw* node of the ASUS Aura USB controller (0b05:19af), which needs
# the udev uaccess ACL that is only granted when the GUI session opens.
# Then launch OpenRGB and poll the SDK until the specific controllers are
# enumerated (not counting log files, which are flushed asynchronously and
# caused missed devices on boot). Then apply the color scheme and VERIFY the
# controllers are still alive. Exit 1 on failure → systemd Restart=always
# retries until hardware is ready.
set -u

BIN="${OPENRGB_BIN:-/usr/bin/openrgb}"
SCHEME="${OPENRGB_SCHEME:-white}"
APPLY_RGB="${APPLY_RGB:-$HOME/.local/bin/apply-rgb}"
I2C_WAIT_S="${I2C_WAIT_S:-120}"
DETECT_WAIT_S="${DETECT_WAIT_S:-60}"
POLL_MIN_S="${OPENRGB_POLL_MIN_S:-18}"   # detection finishes ~13s; start stall check after
STALL_POLLS="${OPENRGB_STALL_POLLS:-2}"  # N unchanged polls after POLL_MIN_S → give up early
EXPECT_CONTROLLERS="${EXPECT_CONTROLLERS:-3}"
EXPECT_NAME="${OPENRGB_EXPECT_NAME:-Kingston}"
CMD_TIMEOUT="${OPENRGB_TIMEOUT:-15}"
AURA_HID="${AURA_HID:-0b05:19af}"        # ASUS AURA LED Controller (Z690-A)

# I801 SMBus adapter number where the RAM is reachable. Detect it dynamically
# (the /dev/i2c-N number can shift if the board populates buses differently).
i801_bus() {
    local d
    for d in /dev/i2c-*; do
        [ -e "$d" ] || continue
        name="$(cat "/sys/class/i2c-dev/${d#/dev/}/name" 2>/dev/null)" || continue
        case "$name" in
            "SMBus I801 adapter"*) printf '%s' "${d#/dev/i2c-}"; return 0 ;;
        esac
    done
    return 1
}

# Probe the I801 bus for the SPD / RGB controller addresses of the DDR5 kit.
# i2cdetect only ACKs addresses that answer; any of the 0x5x/0x6x addresses
# means the bus is alive AND Kingston is reachable through this /dev node.
# (If i2c-tools is absent, fall back to the ACL check only.)
kingston_probe() {
    local bus="$1" out
    command -v i2cdetect >/dev/null 2>&1 || return 0
    out="$(timeout 5 i2cdetect -y -r "$bus" 2>/dev/null)" || return 1
    grep -qE '^.* (5[1357]|6[137])' <<<"$out"
}

# /dev/hidraw* node of the ASUS Aura USB controller. The mainboard's RGB is
# detected by OpenRGB via the AURA LED Controller (USB 0b05:19af), NOT via
# an i2c bus — so the gate must wait for its uaccess ACL, same as the Lian Li
# wrapper does for its own hub.
aura_hidraw() {
    local dev sys
    for dev in /dev/hidraw*; do
        [ -e "$dev" ] || continue
        sys="$(udevadm info -q property -n "$dev" 2>/dev/null | grep -E '^ID_VENDOR_ID=' | cut -d= -f2)"
        [ "$(printf '%s:%s' "$sys" "$(udevadm info -q property -n "$dev" 2>/dev/null | grep -E '^ID_MODEL_ID=' | cut -d= -f2)")" = "$AURA_HID" ] && { printf '%s' "$dev"; return 0; }
    done
    return 1
}

# --- Wait for I801 (Kingston) readiness + ASUS Aura hidraw ACL ---
# The i2c nodes and hidraw nodes are granted to the session by uaccess when
# the user logs in; launching before that is pointless — OpenRGB scans buses
# exactly once at startup, so a miss = unbootable color until we retry.
devices_ready() {
    local found=0 ok=1 dev i801=""
    for dev in /dev/i2c-*; do
        [ -e "$dev" ] || continue
        found=1
        [ "${dev#/dev/i2c-}" = "$(i801_bus)" ] && i801="$dev"
        # ready if effective read+write works (covers BOTH udev uaccess ACL
        # "user:USER:rw" AND i2c-group membership from i2c-tools 45-*.rules)
        if getfacl -p "$dev" 2>/dev/null | grep -qE "^user:${USER}:rw"; then continue; fi
        [ -r "$dev" ] && [ -w "$dev" ] || { ok=0; break; }
    done
    [ "$found" -eq 1 ] && [ "$ok" -eq 1 ] || return 1
    [ -n "$i801" ] || return 1
    kingston_probe "${i801#/dev/i2c-}" || return 1
    # ASUS Aura hidraw must exist AND be user-accessible (uaccess ACL)
    dev="$(aura_hidraw)" || return 1
    getfacl -p "$dev" 2>/dev/null | grep -qE "^user:${USER}:rw"
}

_i=0
while ! devices_ready; do
    ((_i++))
    ((_i >= I2C_WAIT_S)) && {
        logger -t openrgb-wrapper "TIMEOUT: Kingston I801 / ASUS Aura hidraw not ready after ${I2C_WAIT_S}s"
        exit 1   # do NOT launch blind — let systemd restart and re-probe
    }
    sleep 1
done
logger -t openrgb-wrapper "Kingston I801 (bus $(i801_bus)) + ASUS Aura $(aura_hidraw) ready after ${_i}s"

# --- Launch OpenRGB server (no profile; scheme applied after detection) ---
"$BIN" --server --noautoconnect &
PID=$!

# --- Poll the SDK device list until the expected controllers appear ---
# (openrgb -l talks to the running server; network protocol is deterministic,
#  unlike scraping OpenRGB log files which are flushed asynchronously)
sdk_list() {
    timeout "$CMD_TIMEOUT" "$BIN" -l 2>/dev/null | grep -E '^[0-9]+:'
}

devs=""
n=0
_last=-1
_stall=0
_end=$((SECONDS + DETECT_WAIT_S))
while ((SECONDS < _end)); do
    sleep 3
    devs="$(sdk_list)"
    n="$(printf '%s\n' "$devs" | grep -cE '^[0-9]+:')" || n=0
    ((n >= EXPECT_CONTROLLERS)) && grep -qi "$EXPECT_NAME" <<<"$devs" && break
    # Fail fast: once the detection window has passed and the device count
    # stays unchanged for consecutive polls, the list is final — waiting out
    # the full DETECT_WAIT_S only delays the systemd retry.
    if ((SECONDS >= POLL_MIN_S)); then
        if ((n == _last)); then
            ((_stall++))
            ((_stall >= STALL_POLLS)) && break
        else
            _stall=0
        fi
        _last="$n"
    fi
done

n="$(printf '%s\n' "$devs" | grep -cE '^[0-9]+:')" || n=0
if ((n >= EXPECT_CONTROLLERS)) && grep -qi "$EXPECT_NAME" <<<"$devs"; then
    if ! "$APPLY_RGB" "$SCHEME" >/dev/null 2>&1; then
        logger -t openrgb-wrapper "FAIL apply-rgb '$SCHEME' after ${n} controllers"
        kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null
        exit 1
    fi
    # Verify controllers still alive AND Kingston still present after apply
    after="$(sdk_list)"
    logger -t openrgb-wrapper "OK: ${n} controllers (${EXPECT_NAME} present); applied scheme '$SCHEME'"
    a="$(printf '%s\n' "$after" | grep -cE '^[0-9]+:')" || a=0
    ((a >= EXPECT_CONTROLLERS)) && grep -qi "$EXPECT_NAME" <<<"$after" && exit 0
    logger -t openrgb-wrapper "WARN: only ${a} controllers after apply: $(printf '%s' "$after" | tr '\n' ';')"
    kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null
    exit 1
fi

logger -t openrgb-wrapper "FAIL: ${n}/${EXPECT_CONTROLLERS} controllers (need '${EXPECT_NAME}'). Detected: $(printf '%s' "$devs" | tr '\n' ';')"
kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null
exit 1
