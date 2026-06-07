#!/usr/bin/env bash
# Boot a built kernel in QEMU with the verification initramfs, capture console,
# and decide pass/fail from harness markers. No KVM (nested/cloud safe): pure TCG.
#
# Usage: hardening/scripts/boot.sh <x86_64|arm64> <O-dir> [LKDTM_TEST]
set -euo pipefail
ARCH="${1:?arch}"; O="${2:?build dir}"; LKDTM="${3:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
bash "$HERE/mkinitramfs.sh" "$O"
INITRD="$O/initramfs.cpio.gz"
LOG="$O/boot-console.log"
TIMEOUT="${TIMEOUT:-180}"

case "$ARCH" in
  x86_64)
    KIMG="$O/arch/x86/boot/bzImage"
    QEMU=qemu-system-x86_64
    MACHINE=(-machine q35 -cpu max -m 2048)
    CON="console=ttyS0"
    ;;
  arm64)
    KIMG="$O/arch/arm64/boot/Image"
    QEMU=qemu-system-aarch64
    # cpu max => exposes PAuth/BTI/MTE so the mitigations are actually active.
    MACHINE=(-machine virt,mte=on -cpu max -m 2048)
    CON="console=ttyAMA0"
    ;;
  *) echo "bad arch"; exit 1 ;;
esac

CMDLINE="$CON panic=-1 oops=panic ${LKDTM:+}"
[ -n "$LKDTM" ] && export LKDTM
echo ">> booting $ARCH ($KIMG) timeout=${TIMEOUT}s lkdtm='${LKDTM:-none}'"
# busybox init reads LKDTM from env? No - pass via kernel cmdline -> /init can't
# see env. So bake it into cmdline as a var the init script greps. Simpler:
# regenerate initramfs already embeds behavior; pass LKDTM through 'lkdtm=' arg.
set +e
timeout "$TIMEOUT" "$QEMU" "${MACHINE[@]}" -nographic -no-reboot \
  -kernel "$KIMG" -initrd "$INITRD" \
  -append "$CMDLINE ${LKDTM:+LKDTM=$LKDTM}" 2>&1 | tee "$LOG"
set -e

echo "==================== VERDICT ===================="
grep -q "===HARNESS-BOOT-OK===" "$LOG"  && echo "BOOT:    PASS (reached userspace)" || { echo "BOOT: FAIL"; exit 3; }
grep -q "===HARNESS-DONE===" "$LOG"     && echo "SHUTDOWN: clean" || echo "SHUTDOWN: did not reach clean poweroff"
if [ -n "$LKDTM" ]; then
  if grep -q "===LKDTM-SURVIVED:$LKDTM===" "$LOG"; then
    echo "LKDTM $LKDTM: FAIL (mitigation did NOT trap)"
  else
    echo "LKDTM $LKDTM: PASS (kernel trapped before survive marker)"
  fi
fi
