#!/usr/bin/env bash
# Report whether each hardening symbol actually ended up set in a built .config.
# Distinguishes "=y", "=n / not set", and "absent" (symbol unknown to tree).
# Usage: hardening/scripts/verify-config.sh <path-to-.config> <x86_64|arm64>
set -euo pipefail
CFG="${1:?path to .config}"; ARCH="${2:?arch}"
common="INIT_ON_ALLOC_DEFAULT_ON INIT_ON_FREE_DEFAULT_ON INIT_STACK_ALL_ZERO \
 SLAB_FREELIST_HARDENED SLAB_FREELIST_RANDOM RANDOM_KMALLOC_CACHES SLAB_BUCKETS \
 HARDENED_USERCOPY FORTIFY_SOURCE SHUFFLE_PAGE_ALLOCATOR DEBUG_LIST \
 BUG_ON_DATA_CORRUPTION STACKPROTECTOR_STRONG ZERO_CALL_USED_REGS VMAP_STACK LKDTM"
case "$ARCH" in
  x86_64) extra="CFI X86_KERNEL_IBT X86_CET X86_USER_SHADOW_STACK FINEIBT X86_UMIP RANDOMIZE_BASE RANDOMIZE_MEMORY CFI_AUTO_DEFAULT" ;;
  arm64)  extra="CFI ARM64_PTR_AUTH ARM64_PTR_AUTH_KERNEL ARM64_BTI ARM64_BTI_KERNEL ARM64_E0PD ARM64_EPAN ARM64_MTE KASAN KASAN_HW_TAGS ARM64_GCS RANDOMIZE_BASE" ;;
esac
# SLAB_MERGE_DEFAULT must be =n
printf "%-28s %s\n" "SYMBOL" "STATE"
for s in $common $extra; do
  if grep -q "^CONFIG_$s=y" "$CFG"; then st="=y"
  elif grep -q "^CONFIG_$s=" "$CFG"; then st="$(grep "^CONFIG_$s=" "$CFG" | head -1 | cut -d= -f2)"
  elif grep -q "^# CONFIG_$s is not set" "$CFG"; then st="=n (not set)"
  else st="ABSENT (unknown to tree)"; fi
  printf "%-28s %s\n" "$s" "$st"
done
# inverted check
if grep -q "^# CONFIG_SLAB_MERGE_DEFAULT is not set" "$CFG"; then m="=n (correct)";
elif grep -q "^CONFIG_SLAB_MERGE_DEFAULT=y" "$CFG"; then m="=y (WRONG - merging enabled)";
else m="absent"; fi
printf "%-28s %s\n" "SLAB_MERGE_DEFAULT" "$m"
