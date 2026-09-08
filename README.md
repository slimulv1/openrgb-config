# OpenRGB — RGB Lighting Config (Core64)

Cấu hình RGB lighting cho máy **Core64** dành cho hai hệ: **OpenRGB** (điều khiển RAM / GPU / mainboard / AIO pump) và **Lian Li daemon** (fan hub). Hệ thống này thay thế việc phải mở OpenRGB GUI và load profile `.orp` — đổi màu chỉ bằng cách sửa file text `.rgb` rồi chạy một lệnh.

---

## 🖥️ Các thiết bị RGB đang dùng

### Qua OpenRGB

| # | Thiết bị | Loại | Tên OpenRGB |
|---|----------|------|-------------|
| 0 | **Kingston Fury DDR5** | RAM | `Kingston Fury DDR5 DRAM` |
| 1 | **Sapphire RX 7800 XT Nitro+** | GPU | `Sapphire Radeon RX 7800 XT Nitro+` |
| 2 | **ASUS ROG STRIX Z690-A** | Mainboard | `ASUS ROG STRIX Z690-A GAMING WIFI` |

### Thiết bị khác

| Thiết bị | Điều khiển | Ghi chú |
|----------|------------|---------|
| **Deepcool LT720 AIO** (pump) | Nối **ARGB Header 1** mainboard → qua zone ASUS (zone 1, cần resize `SIZE=22`) | Pump có RGB; **fan FK120 KHÔNG có RGB** |
| **Lian Li Uni Hub SL** | `lianli-daemon` (USB `0cf2:a100`, hidraw) | Điều khiển fan hub, KHÔNG qua OpenRGB |

---

## 📦 Cấu trúc repo

```
.
├── README.md
├── systemd/
│   ├── openrgb.service                          # OpenRGB boot service
│   └── lianli-daemon.service.d/
│       └── retry-open-acl.conf                  # Lian Li drop-in → wrapper
├── local/
│   ├── bin/
│   │   └── apply-rgb                            # script đổi màu
│   └── lib/
│       ├── openrgb-wrapper.sh                   # đợi ACL i2c → launch server → apply
│       └── lianli-wrapper.sh                    # đợi ACL hidraw → launch daemon
├── lianli/
│   ├── config.json                              # config Lian Li (machine-specific)
│   └── rgb_presets.json                         # preset màu Lian Li
└── schemes/
    ├── white.rgb (default)   ├── rainbow.rgb
    ├── breath.rgb            ├── red.rgb
    ├── daquang2.rgb          ├── xanhtim.rgb
    └── vangxanh.rgb
```

### Ánh xạ file → vị trí hệ thống

| Repo path | Vị trí cài đặt |
|-----------|----------------|
| `systemd/openrgb.service` | `~/.config/systemd/user/openrgb.service` |
| `systemd/lianli-daemon.service.d/retry-open-acl.conf` | `~/.config/systemd/user/lianli-daemon.service.d/retry-open-acl.conf` |
| `local/lib/openrgb-wrapper.sh` | `~/.local/lib/openrgb-wrapper.sh` |
| `local/lib/lianli-wrapper.sh` | `~/.local/lib/lianli-wrapper.sh` |
| `local/bin/apply-rgb` | `~/.local/bin/apply-rgb` |
| `lianli/config.json` | `~/.config/lianli/config.json` |
| `lianli/rgb_presets.json` | `~/.config/lianli/rgb_presets.json` |
| `schemes/*.rgb` | `~/.config/openrgb/schemes/` |

---

## 🛠️ Cài đặt

> ✅ **Đã sẵn sàng** trên Core64 (máy tham chiếu). Các bước dưới đây dành cho máy mới / cài lại.

### Bước 1 — Cài đặt phần mềm

```bash
# OpenRGB
yay -S openrgb                # hoặc: paru -S openrgb

# Lian Li daemon (bản Linux thay thế L-Connect 3)
git clone https://github.com/slimulv1/lian-li-linux
cd lian-li-linux && make      # build → cài binary lianli-daemon vào /usr/bin/
```

> ⚠️ `lianli-daemon` phải có trong `PATH` (`which lianli-daemon`). Repo này là fork của `lian-li-linux`.

### Bước 2 — Sao chép file vào đúng vị trí

```bash
git clone https://github.com/slimulv1/openrgb-config && cd openrgb-config

# tạo thư mục đích
mkdir -p ~/.config/systemd/user/lianli-daemon.service.d \
         ~/.local/lib ~/.local/bin ~/.config/openrgb/schemes

# OpenRGB
cp systemd/openrgb.service        ~/.config/systemd/user/openrgb.service
cp local/lib/openrgb-wrapper.sh   ~/.local/lib/openrgb-wrapper.sh
cp local/bin/apply-rgb            ~/.local/bin/apply-rgb
cp schemes/*.rgb                  ~/.config/openrgb/schemes/

# Lian Li — script + drop-in
cp local/lib/lianli-wrapper.sh                     ~/.local/lib/lianli-wrapper.sh
cp systemd/lianli-daemon.service.d/retry-open-acl.conf \
   ~/.config/systemd/user/lianli-daemon.service.d/retry-open-acl.conf

# Lian Li — config + presets (máy tham chiếu)
mkdir -p ~/.config/lianli
cp lianli/config.json         ~/.config/lianli/config.json
cp lianli/rgb_presets.json    ~/.config/lianli/rgb_presets.json
```

### Bước 3 — Phân quyền

```bash
chmod +x ~/.local/bin/apply-rgb
chmod +x ~/.local/lib/openrgb-wrapper.sh
chmod +x ~/.local/lib/lianli-wrapper.sh
```

> `~/.local/bin` cần nằm trong `PATH`: `echo $PATH | grep .local/bin`.
> Nếu chưa có, thêm vào `~/.bashrc` / `~/.zshrc`:
> ```bash
> export PATH="$HOME/.local/bin:$PATH"
> ```

### Bước 4 — Cấp quyền truy cập device

OpenRGB cần đọc `/dev/i2c-*`; Lian Li cần đọc/ghi `/dev/hidraw*`. Cho user vào nhóm `i2c` (nếu tồn tại):

```bash
sudo usermod -aG i2c $USER && sudo udevadm trigger
# đăng xuất / đăng nhập lại để áp dụng
```

**Kiểm tra OpenRGB nhận thiết bị:**

```bash
openrgb -l
# kỳ vọng:
#   0: Kingston Fury DDR5 DRAM
#   1: Sapphire Radeon RX 7800 XT Nitro+
#   2: ASUS ROG STRIX Z690-A GAMING WIFI
```

**Đổi màu nhanh (không cần boot service):**

```bash
apply-rgb white       # mặc định
apply-rgb --list      # liệt kê scheme
```

### Bước 5 — Cấu hình Lian Li (device + fan curve)

Cấu hình hiện tại (đã copy ở Bước 2 vào `~/.config/lianli/`):
- **`config.json`** — fan curve, tốc độ fan, backend `hidraw`, FPS…
- **`rgb_presets.json`** — các preset màu cho fan hub

> ⚠️ **Machine-specific**: cả 2 file chứa device ID (`hid:...`) và temp source (`acpitz_0`) của máy tham chiếu. **Không copy nguyên từ máy khác** — chỉ dùng làm tham chiếu. Với máy mới, nên để `lianli-daemon` tự sinh config rồi sửa theo phần cứng của bạn.

### Bước 6 — Bật service tự chạy lúc boot

```bash
systemctl --user daemon-reload

# OpenRGB
systemctl --user enable --now openrgb.service

# Lian Li
systemctl --user enable --now lianli-daemon.service

# kiểm tra
systemctl --user status openrgb.service
systemctl --user status lianli-daemon.service

# log xác nhận OpenRGB đã apply scheme
journalctl -b | grep openrgb-wrapper
# kỳ vọng: OK: 3 controllers; applied scheme 'white'
```

---

## 🎨 Cách dùng

### Đổi màu ngay

```bash
apply-rgb              # scheme mặc định (white)
apply-rgb white        # toàn trắng: RAM 40%, GPU rainbow, pump/mainboard full
apply-rgb rainbow      # rainbow tất cả (GPU "rainbow wave")
apply-rgb breath       # breathing xanh mint
apply-rgb red          # đỏ
apply-rgb xanhtim      # xanh dương
apply-rgb vangxanh     # cam
apply-rgb --list       # liệt kê scheme
```

### Tạo/đổi scheme mới

Sửa file `.rgb` trong `schemes/` — format INI:

```ini
# header: global (áp dụng mọi thiết bị)
MODE=static
COLORS=FFFFFF
BRIGHTNESS=80

[kingston]              # RAM
BRIGHTNESS=40

[sapphire]              # GPU — rainbow tự do
MODE=rainbow wave

[asus|0]                # mainboard onboard (zone 0)
MODE=static
COLORS=FFFFFF
BRIGHTNESS=100

[asus|1]                # ARGB Header 1 = Deepcool LT720 pump (zone 1)
SIZE=22                 # resize zone về 22 LED trước khi set
MODE=static
COLORS=FFFFFF
BRIGHTNESS=100
```

> ⚠️ **Key global phải đặt TRƯỚC** section đầu tiên. Tên section = substring của tên thiết bị (`[kingston]`, `[sapphire]`, `[asus]`); `[tên|zone-index]` để chỉ zone cụ thể.

---

## 🔧 Các mode hoạt động trên từng thiết bị

Không phải device nào cũng hỗ trợ mọi mode — lý do cần section per-device:

| Mode | DRAM | GPU | Mainboard |
|------|:----:|:---:|:---------:|
| `static` | ✅ | ✅ | ✅ |
| `Rainbow` | ✅ | ❌ (dùng `rainbow wave`) | ✅ |
| `breath`/`breathing` | `breath` | ❌ (fallback `static`) | `breathing` |
| `Spectrum` | ✅ | `spectrum cycle` | `spectrum cycle` |

---

## 🔁 Cập nhật file từ repo sau khi sửa

Sửa file trên máy → copy đè vào repo → commit + push:

```bash
# OpenRGB
cp ~/.local/lib/openrgb-wrapper.sh ~/openrgb-config/local/lib/
cp ~/.local/lib/lianli-wrapper.sh  ~/openrgb-config/local/lib/
cp ~/.local/bin/apply-rgb          ~/openrgb-config/local/bin/
cp ~/.config/openrgb/schemes/*.rgb ~/openrgb-config/schemes/
cp ~/.config/systemd/user/openrgb.service        ~/openrgb-config/systemd/
cp ~/.config/systemd/user/lianli-daemon.service.d/retry-open-acl.conf \
   ~/openrgb-config/systemd/lianli-daemon.service.d/retry-open-acl.conf

# Lian Li config
cp ~/.config/lianli/config.json       ~/openrgb-config/lianli/
cp ~/.config/lianli/rgb_presets.json  ~/openrgb-config/lianli/

cd ~/openrgb-config
git commit -am "update: ..."
git push
```
