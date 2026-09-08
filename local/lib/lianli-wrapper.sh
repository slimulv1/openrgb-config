#!/usr/bin/env bash
# Wait for Lian Li hub (0cf2:a100) hidraw ACL before launching daemon.
# Fixes race: session restart → udev uaccess not yet granted → "Permission denied".
set -e

MAX_WAIT="${LIANLI_WAIT_S:-40}"
VENDOR="0cf2"
MODEL="a100"

find_node() {
    local node info
    for node in /dev/hidraw*; do
        [ -e "$node" ] || continue
        info="$(udevadm info -q property -n "$node" 2>/dev/null)" || continue
        if echo "$info" | grep -q "ID_VENDOR_ID=${VENDOR}" && echo "$info" | grep -q "ID_MODEL_ID=${MODEL}"; then
            echo "$node"; return 0
        fi
    done
    return 1
}

# Wait for device + ACL
NODE=""
for ((i = 1; i <= MAX_WAIT; i++)); do
    NODE="$(find_node || true)"
    if [ -n "$NODE" ] && getfacl -cp "$NODE" 2>/dev/null | grep -q "^user:$(id -un):rw" 2>/dev/null; then
        echo "lianli wrapper: $NODE ready (after ${i}s)" >&2
        break
    fi
    NODE=""
    sleep 1
done

[ -z "$NODE" ] && echo "lianli wrapper: device not ready after ${MAX_WAIT}s — proceeding" >&2

exec /usr/bin/lianli-daemon
