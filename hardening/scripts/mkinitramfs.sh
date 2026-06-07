#!/usr/bin/env bash
# Build a minimal busybox initramfs whose /init verifies the running kernel's
# hardening state, optionally fires an lkdtm test, and powers off cleanly.
# Output: <outdir>/initramfs.cpio.gz
set -euo pipefail
OUT="${1:?usage: mkinitramfs.sh <outdir>}"
# BUSYBOX must match the *target* arch of the kernel under test. Defaults to the
# host busybox (fine for native x86_64); set BUSYBOX=/path/to/aarch64-busybox
# when building an arm64 initramfs.
BB="${BUSYBOX:-$(command -v busybox)}"
[ -x "$BB" ] || { echo "busybox '$BB' not found/executable" >&2; exit 1; }
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT"/{bin,proc,sys,dev}
cp "$BB" "$ROOT/bin/busybox"
for a in sh mount cat grep zcat dmesg poweroff ls echo sleep head; do ln -sf busybox "$ROOT/bin/$a"; done

cat > "$ROOT/init" <<'INIT'
#!/bin/sh
export PATH=/bin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t debugfs none /sys/kernel/debug 2>/dev/null
LKDTM=$(cat /proc/cmdline | tr ' ' '\n' | grep '^LKDTM=' | cut -d= -f2)
echo "===HARNESS-BOOT-OK==="
echo "--- uname ---"; cat /proc/version
echo "--- hardening config evidence (/proc/config.gz) ---"
if [ -e /proc/config.gz ]; then
  zcat /proc/config.gz | grep -E "^CONFIG_(INIT_ON_ALLOC_DEFAULT_ON|INIT_ON_FREE_DEFAULT_ON|INIT_STACK_ALL_ZERO|SLAB_FREELIST_HARDENED|RANDOM_KMALLOC_CACHES|SLAB_BUCKETS|HARDENED_USERCOPY|FORTIFY_SOURCE|SHUFFLE_PAGE_ALLOCATOR|BUG_ON_DATA_CORRUPTION|ZERO_CALL_USED_REGS|VMAP_STACK|CFI|X86_KERNEL_IBT|X86_USER_SHADOW_STACK|FINEIBT|RANDOMIZE_BASE|RANDOMIZE_MEMORY|ARM64_PTR_AUTH_KERNEL|ARM64_BTI_KERNEL|ARM64_MTE|KASAN_HW_TAGS|ARM64_GCS)=" | sort
else
  echo "config.gz absent (IKCONFIG_PROC not set)"
fi
echo "--- runtime mitigation dmesg lines ---"
dmesg | grep -iE "kCFI|FineIBT|IBT|shadow stack|cet|pointer authentication|BTI|MTE|kasan|KASLR|init_on_alloc|randomiz|kernel control flow" || echo "(no matching dmesg lines)"
echo "--- vulnerabilities sysfs ---"
for f in /sys/devices/system/cpu/vulnerabilities/*; do [ -e "$f" ] && echo "$(basename $f): $(cat $f)"; done 2>/dev/null
if [ -n "$LKDTM" ] && [ -e /sys/kernel/debug/provoke-crash/DIRECT ]; then
  echo "===LKDTM-FIRE:$LKDTM==="
  echo "$LKDTM" > /sys/kernel/debug/provoke-crash/DIRECT
  sleep 2
  echo "===LKDTM-SURVIVED:$LKDTM==="   # only prints if the mitigation did NOT trap
fi
echo "===HARNESS-DONE==="
poweroff -f
INIT
chmod +x "$ROOT/init"
( cd "$ROOT" && find . | cpio -o -H newc 2>/dev/null | gzip -9 ) > "$OUT/initramfs.cpio.gz"
echo "wrote $OUT/initramfs.cpio.gz ($(du -h "$OUT/initramfs.cpio.gz" | cut -f1))"
