#!/usr/bin/env bash
# Install patched mt7601u driver (MT7601U clone-dongle fix)
# Usage: sudo bash install.sh
set -euo pipefail

KVER="$(uname -r)"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$BASE_DIR/driver"
DKMS_NAME="mt7601u-patched"
DKMS_VER="1.0"

if [[ $EUID -ne 0 ]]; then
	echo "Please run as root:  sudo bash install.sh" >&2
	exit 1
fi

# --- The compiler matters: gcc-11 produces a module whose struct module is
# --- 64 bytes smaller than what Ubuntu HWE 6.8 kernels expect -> rejected
# --- with "Invalid module format".
CC_BIN=""
for c in gcc-12 x86_64-linux-gnu-gcc-12 gcc; do
	if command -v "$c" >/dev/null 2>&1 && "$c" --version 2>/dev/null | head -1 | grep -q " 12\."; then
		CC_BIN="$c"; break
	fi
done
if [[ -z "$CC_BIN" ]]; then
	echo "ERROR: gcc-12 not found. Install it first:  apt install gcc-12" >&2
	echo "Ubuntu 22.04 HWE 6.8 kernels are built with gcc-12; a gcc-11 build" >&2
	echo "will be rejected with 'Invalid module format'." >&2
	exit 1
fi
echo "[*] Using compiler: $CC_BIN"

install_manual() {
	echo "[*] Building module manually (kernel $KVER)..."
	make -C "/lib/modules/$KVER/build" "M=$SRC_DIR" "CC=$CC_BIN" modules
	install -D -m 644 "$SRC_DIR/mt7601u.ko" "/lib/modules/$KVER/updates/mt7601u.ko"
	depmod -a "$KVER"
	echo "[*] Installed to /lib/modules/$KVER/updates/mt7601u.ko"
}

# --- Preferred path: DKMS (auto-rebuild on future kernel upgrades) ---
if command -v dkms >/dev/null 2>&1; then
	DEST="/usr/src/${DKMS_NAME}-${DKMS_VER}"
	mkdir -p "$DEST"
	cp "$SRC_DIR"/*.c "$SRC_DIR"/*.h "$SRC_DIR"/Makefile "$SRC_DIR"/dkms.conf "$DEST/"
	dkms add -m "$DKMS_NAME/$DKMS_VER" 2>/dev/null || true
	if dkms build -m "$DKMS_NAME/$DKMS_VER" && dkms install -m "$DKMS_NAME/$DKMS_VER"; then
		echo "[*] DKMS install OK (auto-rebuilds on kernel upgrades)."
	else
		echo "[!] DKMS build failed (common on an once-polluted headers tree)." >&2
		echo "[!] Falling back to manual build. If that also fails with" >&2
		echo "[!] 'No rule to make target syscall_32.tbl', reinstall headers first:" >&2
		echo "[!]   apt install --reinstall linux-headers-$KVER linux-hwe-6.8-headers-$KVER" >&2
		install_manual
	fi
else
	echo "[!] dkms not found, doing a manual install."
	install_manual
fi

echo
echo "[✓] Done. Now replug your MT7601U dongle (power-cycle is required)."
echo "    Watch it:   sudo dmesg -w | grep -i mt76"
echo "    Interface should appear (e.g. wlxXXXXXXXXXXXX) within ~2 seconds."
