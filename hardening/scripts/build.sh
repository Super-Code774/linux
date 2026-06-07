#!/usr/bin/env bash
# Build a hardened kernel for a given arch using the hardening fragments.
# Out-of-tree build (O=) so the source tree stays clean.
#
# Usage:  hardening/scripts/build.sh <x86_64|arm64> [extra-fragment ...]
#         BASELINE=1 hardening/scripts/build.sh x86_64   # plain defconfig, no fragments
set -euo pipefail

ARCH_IN="${1:?usage: build.sh <x86_64|arm64> [extra-fragment...]}"; shift || true
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$SRC"

case "$ARCH_IN" in
  x86_64) KARCH=x86_64; IMG=arch/x86/boot/bzImage; FRAG=hardening/configs/hardening-x86_64.config ;;
  arm64)  KARCH=arm64;  IMG=arch/arm64/boot/Image; FRAG=hardening/configs/hardening-arm64.config ;;
  *) echo "unknown arch $ARCH_IN" >&2; exit 1 ;;
esac

TAG="${TAG:-hardened}"
[ "${BASELINE:-0}" = 1 ] && TAG=baseline
O="${O:-/home/user/build/$KARCH-$TAG}"
JOBS="${JOBS:-$(nproc)}"
# Clang/LLVM is mandatory for CFI (both arches) and for arm64 PAC/BTI kernel.
MK=(make -C "$SRC" O="$O" ARCH="$KARCH" LLVM=1 -j"$JOBS")

echo ">> SRC=$SRC  ARCH=$KARCH  O=$O  TAG=$TAG  JOBS=$JOBS"
rm -rf "$O"; mkdir -p "$O"
"${MK[@]}" defconfig

if [ "${BASELINE:-0}" != 1 ]; then
  FRAGS=(hardening/configs/hardening-common.config "$FRAG" hardening/configs/harness-support.config "$@")
  echo ">> merging fragments: ${FRAGS[*]}"
  ARCH="$KARCH" ./scripts/kconfig/merge_config.sh -m -O "$O" "$O/.config" "${FRAGS[@]}"
  "${MK[@]}" olddefconfig
fi

echo ">> building kernel image"
"${MK[@]}" "$(basename "$IMG")" 2> >(tee "$O/build.stderr" >&2) || { echo "BUILD FAILED"; exit 2; }
echo ">> built: $O/$IMG"
ls -la "$O/$IMG"
