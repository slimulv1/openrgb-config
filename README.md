# OpenRGB — RGB Lighting Config (Core64)

Cấu hình RGB lighting cho máy Core64, sử dụng [OpenRGB](https://openrgb.org/) (version **0.9+**, git2453). Hệ thống này thay thế hoàn toàn việc phải mở OpenRGB UI và load profile `.orp` — giờ đổi màu chỉ bằng cách sửa file text `.rgb` rồi chạy một lệnh.

---

## 🖥️ Các thiết bị RGB đang dùng

| # | Device | Loại | OpenRGB tên hiển thị |
|---|--------|------|----------------------|
| 0 | **Kingston Fury DDR5 DRAM** | RAM | `Kingston Fury DDR5 DRAM` |
| 1 | **Sapphire RX 7800 XT Nitro+** | GPU | `Sapphire Radeon RX 7800 XT Nitro+` |
| 2 | **ASUS ROG STRIX Z690-A** | Mainboard | `ASUS ROG STRIX Z690-A GAMING WIFI` |

### Thiết bị RGB khác (không qua OpenRGB)

| Device | Cách điều khiển | Ghi chú |
|--------|-----------------|---------|
| **Deepcool LT720 AIO** (pump block) | Nối vào **ARGB Header 1** của mainboard → điều khiển qua zone ASUS (zone 1, cần resize `SIZE=22`) | Pump chỉ có RGB; **fan FK120 KHÔNG có RGB** |
| **Lian Li Uni Hub SL** (fan hub) | `lianli-daemon` riêng (USB `0cf2:a100`), **KHÔNG qua OpenRGB** | Hub cho fans |

---

## 📦 Cấu trúc repo

```
.
├── systemd/openrgb.service      # systemd user service → chạy wrapper lúc boot
├── local/lib/openrgb-wrapper.sh # wrapper: đợi ACL i2c → launch server → apply scheme
├── local/bin/apply-rgb          # script đổi màu (đọc file .rgb)
└── schemes/*.rgb                # các color scheme (dễ chỉnh bằng text editor)
```

### Vị trí cài đặt trên máy (mirror của repo)

| Repo path | Hệ thống |
|-----------|----------|
| `systemd/openrgb.service` | `~/.config/systemd/user/` |
| `local/lib/openrgb-wrapper.sh` | `~/.local/lib/` |
| `local/bin/apply-rgb` | `~/.local/bin/` |
| `schemes/*.rgb` | `~/.config/openrgb/schemes/` |

---

## 🎨 Cách dùng

### Đổi màu ngay

```bash
apply-rgb              # áp dụng scheme mặc định (white)
apply-rgb white        # toàn trắng: RAM 40%, GPU rainbow, pump/mainboard full
apply-rgb rainbow      # rainbow tất cả (GPU dùng "rainbow wave")
apply-rgb breath       # breathing xanh mint
apply-rgb red          # đỏ
apply-rgb xanhtim      # xanh dương
apply-rgb vangxanh     # cam
apply-rgb --list       # liệt kê các scheme
```

### Tạo/đổi scheme mới

Sửa file `.rgb` trong `schemes/` — format INI đơn giản:

```ini
# header: global (áp dụng mọi thiết bị)
MODE=static
COLORS=FFFFFF
BRIGHTNESS=80

# override per-device (tên section = substring của tên thiết bị)
[kingston]
BRIGHTNESS=40              # RAM chỉ 40%

[sapphire]
MODE=rainbow wave          # GPU chạy rainbow tự do

# per-zone trên cùng device (mainboard): [tên|zone-index]
[asus|0]                    # mainboard onboard
MODE=static
COLORS=FFFFFF
BRIGHTNESS=100

[asus|1]                    # ARGB Header 1 = Deepcool LT720 pump
SIZE=22                     # resize zone về 22 LED trước khi set
MODE=static
COLORS=FFFFFF
BRIGHTNESS=100
```

> ⚠️ **Lưu ý:** các key **global phải đặt TRƯỚC** section đầu tiên. Đổi màu trong section chỉ ảnh hưởng thiết bị/zone đó.

### Boot tự động

`openrgb.service` (user) chạy lúc log in:
1. `udevadm settle` — chờ udev
2. `openrgb-wrapper.sh` — đợi ACL i2c (race boot), launch `openrgb --server --noautoconnect`, chờ detect controller
3. Detect ≥1 controller → `apply-rgb white` → LED sáng theo scheme

Log xác nhận: `journalctl -b | grep openrgb-wrapper` → `OK: 3 controllers; applied scheme 'white'`

---

## 🔧 Các mode hoạt động trên từng thiết bị

Không phải device nào cũng hỗ trợ mọi mode — đây là lý do cần section per-device:

| Mode | DRAM | GPU | Mainboard |
|------|:----:|:---:|:---------:|
| `static` | ✅ | ✅ | ✅ |
| `Rainbow` | ✅ | ❌ (dùng `rainbow wave`) | ✅ |
| `breath`/`breathing` | `breath` | ❌ (fallback `static`) | `breathing` |
| `Spectrum` | ✅ | `spectrum cycle` | `spectrum cycle` |
