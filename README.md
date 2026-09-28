# mt7601u-clone-fix

**A patched Linux driver for buggy MT7601U (Ralink 148f:7601) USB WiFi clone dongles** — fixes the infamous *"probe of x-x:1.0 failed with error -110"* / *"Vendor request failed:-110"* failure that has plagued cheap MT7601U dongles for ~10 years ([Launchpad #1716301](https://bugs.launchpad.net/bugs/1716301), still open as of 2026).

```
mt7601u 1-3:1.0: ASIC revision: 76010001 MAC revision: 76010500
mt7601u 1-3:1.0: Firmware Version: 0.1.00 Build: 7640 ...
mt7601u 1-3:1.0: Vendor request req:02 off:0a44 failed:-110     <-- the bug
mt7601u 1-3:1.0: Vendor request req:02 off:0230 failed:-110
...
mt7601u: probe of 1-3:1.0 failed with error -110                 <-- no wlanX interface ever appears
```

With this patch the dongle initializes in **under 1 second** (stock driver: 60 s of timeouts, then failure):

```
mt7601u 1-3:1.0: Firmware Version: 0.1.00 Build: 7640 ...
mt7601u 1-3:1.0: EEPROM ver:0d fae:00
mt7601u 1-3:1.0: EEPROM country region 01 (channels 1-13)
mt7601u 1-3:1.0 wlx30b49e4b74f4: renamed from wlan0            <-- works!
```

## Symptoms of an affected dongle

* `lsusb` shows `148f:7601 Ralink MT7601U Wireless Adapter` (often after a 148f:2878 "driver CD" modeswitch)
* `dmesg` shows the firmware loading, then a wall of `Vendor request ... failed:-110` (`-ETIMEDOUT`) at offsets like `0x0a44, 0x0230, 0x0400, 0x0800, 0x0404, 0x09a0, 0x0a6c, 0x0080`
* No `wlan0`/`wlx…` interface appears
* After failed probes the dongle may wedge so badly that even USB enumeration fails (`device descriptor read/64, error -110`) — only a physical replug recovers it

## Root cause

During firmware load, `mt7601u_load_firmware()` in `mcu.c` issues a software reset (`mt7601u_vendor_reset()` → `MT_VEND_DEV_MODE_RESET`), waits only **5 ms**, and continues hammering the device with vendor control requests. On clone dongles the MCU never comes back from that reset — every subsequent request times out, and the device eventually wedges at the USB level.

## The fix

Two behavior changes + one optional knob (based on the stock `drivers/net/wireless/mediatek/mt7601u` driver from Linux 6.8):

1. **`0001-mcu-skip-vendor-reset-before-fw-load.patch`** — skip the fatal `mt7601u_vendor_reset()` call (new module parameter `fw_vnd_reset`, default **N** = skip) and extend the post-reset wait from 5 ms to 100 ms. This alone fixed our dongle.
2. **`0002-phy-add-fw_skip_cals-parameter.patch`** — new module parameter `fw_skip_cals` (default **N** = keep calibrations). Some clones die later, inside the MCU RF calibrations (`MCU_CAL_R/TXDCOC/LOFT/TXIQ/RXIQ/DPD`); this knob skips them, mirroring the community workaround from [kuba-moo/mt7601u#64](https://github.com/kuba-moo/mt7601u/issues/64). Only enable if needed:
   ```bash
   echo Y | sudo tee /sys/module/mt7601u/parameters/fw_skip_cals   # then replug
   ```

## Install

### Option A — one-shot script (Ubuntu/Debian, recommended)

```bash
git clone https://github.com/<you>/mt7601u-clone-fix.git
cd mt7601u-clone-fix
sudo bash install.sh
# then physically replug the dongle
```

The script prefers **DKMS** (`mt7601u-patched/1.0`, auto-rebuilds on kernel upgrades) and falls back to a manual build into `/lib/modules/$(uname -r)/updates/`.

### Option B — manual build

```bash
cd driver
make -C /lib/modules/$(uname -r)/build M=$PWD CC=gcc-12 modules
sudo cp mt7601u.ko /lib/modules/$(uname -r)/updates/
sudo depmod -a
# replug the dongle
```

### Option C — patch your own kernel source

Apply `patches/*.patch` (`patch -p1 < patches/0001-…`) against `drivers/net/wireless/mediatek/mt7601u/` in your kernel tree and build normally.

## ⚠️ Toolchain traps (both verified the hard way)

* **Build with gcc-12 on Ubuntu 22.04 HWE 6.8 kernels.** A gcc-11 build produces a `struct module` **64 bytes smaller** (`.gnu.linkonce.this_module` = `0x4c0` vs the required `0x500`) and is rejected with `Invalid module format`. Check with:
  ```bash
  readelf -SW mt7601u.ko | grep this_module   # want size 000500 on 6.8.0-13x-generic
  ```
* **Don't run `make prepare`-style steps inside the headers tree.** If Kbuild regenerates `include/generated/autoconf.h` / `include/config/auto.conf` there, *every* subsequently built module gets the wrong layout until you restore the tree:
  ```bash
  apt install --reinstall linux-headers-$(uname -r) linux-hwe-6.8-headers-$(uname -r)
  ```
* **Remove stale `mt7601u.ko` from `/lib/modules/$(uname -r)/updates/`** — `modprobe` prefers that path over the stock module, and a leftover broken build will shadow both.

## Verified environment

* Ubuntu 22.04 (jammy), HWE kernel **6.8.0-138-generic**, gcc 12.3, BIOS boot (no Secure Boot)
* Dongle: `148f:7601` clone (boot ROM presents as `148f:2878` mass-storage first, EEPROM ver `0d`)
* Driver source: vanilla Linux 6.8 `drivers/net/wireless/mediatek/mt7601u`

The driver itself has been essentially frozen upstream since 2015, so the patches apply cleanly across a wide range of kernels; adapt the gcc version to whatever built your kernel (`cat /proc/version`).

## Background & credits

* [Launchpad bug #1716301](https://bugs.launchpad.net/bugs/1716301) — 10 years of reports; workarounds in comments #52/#53 by users rebuilding the driver
* [kuba-moo/mt7601u issue #64](https://github.com/kuba-moo/mt7601u/issues/64) — original out-of-tree driver author & community debugging
* [AskUbuntu 1205254](https://askubuntu.com/questions/1205254/ralink-tech-mt7601u-wireless-adapter-on-xubuntu) — calibration-skip workaround write-up

## License

GPL-2.0 (see [LICENSE](LICENSE)). The driver is a derivative of the Linux kernel's `mt7601u` driver, Copyright Ralink Technology, Felix Fietkau, Jakub Kicinski, et al.
