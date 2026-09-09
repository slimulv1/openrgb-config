#!/usr/bin/env python3
"""OpenRGB SDK client — Save To Device (EEPROM commit) via NET_PACKET_ID_RGBCONTROLLER_SAVEMODE (1102).
Echoes the device's current mode description back (validation-safe) for the active (Static) mode.
Reference: OpenRGB master — NetworkProtocol.h, NetworkServer.cpp, RGBController.cpp.
"""
import socket, struct, sys

HOST, PORT = "127.0.0.1", 6742
MAGIC = b"ORGB"
DEV_ASUS = 2            # ASUS ROG STRIX Z690-A (from `openrgb -ld`)
MODE_STATIC_IDX = 2     # modes order on ASUS: Direct Off [Static] Breathing Flashing ...

PKT_REQUEST_PROTOCOL_VERSION = 40
PKT_SET_CLIENT_NAME           = 50
PKT_REQUEST_CONTROLLER_DATA   = 1
PKT_SAVEMODE                  = 1102
PKT_ACK                       = 10
SDK_VERSION                   = 6

STATUS_OK = 0

def pkt(dev_id, pkt_id, payload=b""):
    return MAGIC + struct.pack("<III", dev_id, pkt_id, len(payload)) + payload

def recv_exact(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise EOFError("connection closed")
        buf += chunk
    return buf

def recv_pkt(sock):
    hdr = recv_exact(sock, 16)
    magic, dev_id, pkt_id, pkt_size = struct.unpack("<4sIII", hdr)
    payload = recv_exact(sock, pkt_size)
    return magic, dev_id, pkt_id, payload

def read_until(sock, want_pkt_id, max_pkts=100):
    for _ in range(max_pkts):
        magic, dev_id, pkt_id, payload = recv_pkt(sock)
        if pkt_id == want_pkt_id:
            return magic, dev_id, pkt_id, payload
    raise RuntimeError(f"timeout waiting for pkt {want_pkt_id}")

def read_ack_for(sock, target_pkt_id, max_pkts=100):
    """Read ACK packets until we get the ack for target_pkt_id (echoing target dev_id).
    Returns (acked_pkt_id, status)."""
    for _ in range(max_pkts):
        magic, adev, apid, apayload = recv_pkt(sock)
        if apid != PKT_ACK:
            continue  # skip non-ACK traffic (e.g. server info packets)
        acked_pkt_id, status = struct.unpack("<II", apayload[:8])
        if acked_pkt_id == target_pkt_id:
            return acked_pkt_id, status
    raise RuntimeError(f"timeout waiting for ACK of pkt {target_pkt_id}")

def walk_str(buf, off):
    (n,) = struct.unpack_from("<H", buf, off)
    off += 2
    s = buf[off:off + n]
    return s.rstrip(b"\0").decode("utf-8", "replace"), off + n

def parse_modes(buf, off, proto):
    """Walk device description until modes are read. Returns (off, raw_mode_bytes_list)."""
    # u32 type
    off += 4
    _,  off = walk_str(buf, off)  # name
    _,  off = walk_str(buf, off)  # vendor
    _,  off = walk_str(buf, off)  # description
    _,  off = walk_str(buf, off)  # version
    _,  off = walk_str(buf, off)  # serial
    _,  off = walk_str(buf, off)  # location
    (num_modes,) = struct.unpack_from("<H", buf, off); off += 2
    active_mode  = struct.unpack_from("<i", buf, off)[0]; off += 4
    raw_modes = []
    for _ in range(num_modes):
        mstart = off
        (name_len,) = struct.unpack_from("<H", buf, off); off += 2 + name_len
        if proto < 6:
            off += 4  # mode.value
        off += 4  # flags
        off += 4  # speed_min
        off += 4  # speed_max
        if proto >= 3:
            off += 4  # brightness_min
            off += 4  # brightness_max
        off += 4  # colors_min
        off += 4  # colors_max
        off += 4  # speed
        if proto >= 3:
            off += 4  # brightness
        off += 4  # direction
        off += 4  # color_mode
        (num_colors,) = struct.unpack_from("<H", buf, off); off += 2
        off += num_colors * 4
        raw_modes.append(buf[mstart:off])
    return off, raw_modes, active_mode

def main():
    sock = socket.create_connection((HOST, PORT), timeout=5)
    # 1) protocol version negotiation (must be >= 6 or server never ACKs)
    sock.sendall(pkt(0, PKT_REQUEST_PROTOCOL_VERSION, struct.pack("<I", SDK_VERSION)))
    # 2) client name (optional but polite)
    sock.sendall(pkt(0, PKT_SET_CLIENT_NAME, b"save-device\0"))
    # 3) request controller data for ASUS
    sock.sendall(pkt(DEV_ASUS, PKT_REQUEST_CONTROLLER_DATA, struct.pack("<I", SDK_VERSION)))
    magic, dev_id, pkt_id, payload = read_until(sock, PKT_REQUEST_CONTROLLER_DATA)
    assert magic == MAGIC, f"bad magic {magic!r}"

    # payload: [u32 reply_size] + device description
    (reply_size,) = struct.unpack_from("<I", payload, 0)
    desc = payload[4:4 + reply_size - 4] if reply_size > 4 else payload[4:]
    # desc may be exactly reply_size-4; fall back to remaining payload
    if len(desc) < 8:
        desc = payload[4:]
    off, raw_modes, active_mode = parse_modes(desc, 0, SDK_VERSION)
    print(f"[i] device {dev_id} active_mode={active_mode} modes={len(raw_modes)}")
    if MODE_STATIC_IDX >= len(raw_modes):
        print(f"[x] mode index {MODE_STATIC_IDX} out of range ({len(raw_modes)} modes)")
        sys.exit(2)
    mode_bytes = raw_modes[MODE_STATIC_IDX]
    print(f"[i] echo mode idx {MODE_STATIC_IDX} ({len(mode_bytes)} bytes)")

    # 4) SAVEMODE payload: [u32 data_size][i32 mode_idx][mode description bytes]
    payload_save = struct.pack("<I", 4 + 4 + len(mode_bytes))
    payload_save += struct.pack("<i", MODE_STATIC_IDX)
    payload_save += mode_bytes
    assert len(payload_save) == struct.unpack_from("<I", payload_save, 0)[0], "data_size mismatch"
    sock.sendall(pkt(DEV_ASUS, PKT_SAVEMODE, payload_save))
    print(f"[i] sent SAVEMODE to dev {DEV_ASUS} ({len(payload_save)} bytes)")

    # 5) read ACK for the SAVEMODE packet specifically
    acked_pkt_id, status = read_ack_for(sock, PKT_SAVEMODE)
    print(f"[i] ACK: acked_pkt_id={acked_pkt_id} status={status} ({'OK — SAVED' if status == STATUS_OK else 'FAILED'})")
    sock.close()
    sys.exit(0 if status == STATUS_OK else 3)

if __name__ == "__main__":
    main()