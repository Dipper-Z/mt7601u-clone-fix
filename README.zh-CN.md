# mt7601u-clone-fix(中文说明)

**修复山寨版 MT7601U(Ralink 148f:7601)USB 无线网卡在 Linux 下无法识别的补丁驱动。** 解决著名的 `probe of x-x:1.0 failed with error -110` / `Vendor request failed:-110` 问题([Launchpad #1716301](https://bugs.launchpad.net/bugs/1716301),挂了约十年至今未修)。

## 症状

* `lsusb` 能看到 `148f:7601 MT7601U Wireless Adapter`(常先以 `148f:2878` "驱动光盘"模式出现)
* `dmesg`:固件加载成功后,一串 `Vendor request req:0x off:xxxx failed:-110` 超时(偏移如 `0x0a44/0x0230/0x0400/0x0800/0x0080`)
* 不出现 `wlan0`/`wlx…` 接口
* 反复失败后网卡可能在 USB 层卡死(`device descriptor read/64, error -110`),只能拔插恢复

## 根因

`mcu.c` 的 `mt7601u_load_firmware()` 在加载固件前发出软件复位指令(`mt7601u_vendor_reset()`),**只等 5 毫秒**就继续刷寄存器。克隆卡的 MCU 复位后永远不再应答,所有 vendor 请求超时,最终设备在 USB 层卡死。

## 修复内容(基于 Linux 6.8 原版驱动)

1. **跳过致命的 vendor reset**(参数 `fw_vnd_reset`,默认 N=跳过),等待 5ms→100ms —— 本卡只靠这一条就修好了
2. **可选跳过 MCU 射频校准**(参数 `fw_skip_cals`,默认 N=保留;部分克隆卡死在校准阶段,来自 kuba-moo issue #64 社区方案):
   ```bash
   echo Y | sudo tee /sys/module/mt7601u/parameters/fw_skip_cals   # 然后重新拔插
   ```

## 安装

```bash
git clone <本仓库>
cd mt7601u-clone-fix
sudo bash install.sh     # 优先 DKMS(内核升级自动重编),失败回退手动编译
# 然后把网卡拔下再插上(必须物理重新上电)
```

## ⚠️ 本机踩坑实录(Ubuntu 22.04 HWE 6.8)

| 坑 | 现象 | 解法 |
|---|---|---|
| 用 gcc-11 编译 | 模块 `struct module` 比 6.8 内核要求的小 64 字节(`0x4c0` vs `0x500`),`Invalid module format` | **必须 `CC=gcc-12`**;`readelf -SW x.ko \| grep this_module` 验证为 `000500` |
| headers 树被污染(跑过 make prepare 类步骤后 autoconf 被重生) | 之后编出的所有模块都被拒;DKMS 报缺 `syscall_32.tbl` | `apt install --reinstall linux-headers-$(uname -r) linux-hwe-6.8-headers-$(uname -r)` |
| updates/ 残留坏模块 | `modprobe mt7601u` 优先加载它,一直失败 | 删除/移走 `/lib/modules/$(uname -r)/updates/mt7601u.ko` 后 `depmod -a` |

## 验证过的环境

Ubuntu 22.04 + HWE 6.8.0-138-generic + gcc 12.3 + BIOS 启动(无 Secure Boot);克隆卡固件 Build 7640、EEPROM ver 0d。

## 许可

GPL-2.0。驱动衍生自 Linux 内核 `mt7601u` 驱动,版权归 Ralink Technology、Felix Fietkau、Jakub Kicinski 等。
