#!/usr/bin/env bash
# Phase A reproducer: build + boot SLAB_VIRTUAL on the base the RFC targets.
# This is a CLEAN mechanical integration (git am, zero hand-edits) — the honest
# "it works" for the keystone. NOTE: base is v6.5-rc1-era; SLAB_VIRTUAL is x86-
# only and incompatible with KASAN/KFENCE (so it cannot combine with the 7.1
# arm64 MTE profile). For the 7.1-rc6 forward-port attempt see the
# slabvirtual-71-forwardport branch / REPORT.md Phase B.
set -euo pipefail
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
BASE=46a9ea6681907a3be6b6b0d43776dccc62cad6cf
WT=/home/user/sv-v66
O=/home/user/build/sv-v66

cd "$SRC"
git cat-file -t "$BASE" >/dev/null 2>&1 || \
  git fetch --depth 1 https://github.com/torvalds/linux.git "$BASE"
git worktree remove --force "$WT" 2>/dev/null || true; rm -rf "$WT"
git worktree add --detach "$WT" "$BASE"

cd "$WT"
git am --whitespace=nowarn "$SRC"/hardening/tierb/patchset/00*.patch   # applies 14/14

rm -rf "$O"; mkdir -p "$O"
make -C "$WT" O="$O" defconfig
# SLAB_VIRTUAL on; KASAN/KFENCE off (incompatible); harness support on.
"$WT"/scripts/config --file "$O/.config" -e SLAB_VIRTUAL -e IKCONFIG -e IKCONFIG_PROC -e DEBUG_FS -d KASAN -d KFENCE
make -C "$WT" O="$O" olddefconfig
make -C "$WT" O="$O" -j"$(nproc)" bzImage

# Boot: use -cpu qemu64 (v6.5 hangs under -cpu max in QEMU 8.2) and earlyprintk.
bash "$SRC"/hardening/scripts/mkinitramfs.sh "$O"
timeout 200 qemu-system-x86_64 -machine q35 -cpu qemu64 -m 2048 -nographic -no-reboot \
  -kernel "$O/arch/x86/boot/bzImage" -initrd "$O/initramfs.cpio.gz" \
  -append "console=ttyS0 earlyprintk=serial,ttyS0,115200 panic=-1 oops=panic" | tee "$O/boot-sv.log"
echo "==== verify ===="
grep -q "HARNESS-BOOT-OK" "$O/boot-sv.log" && echo "BOOT: PASS" || echo "BOOT: FAIL"
grep -q "CONFIG_SLAB_VIRTUAL=y" "$O/boot-sv.log" && echo "SLAB_VIRTUAL: live in running kernel"
