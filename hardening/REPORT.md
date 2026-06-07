# Always-On Kernel Memory-Safety Hardening — Report

**Baseline kernel (pinned):** Linux **7.1.0-rc6**, commit
`979c294509f9248fe1e7c358d582fb37dd5ca12d`
**Toolchain:** Clang/LLVM 18.1.3, GNU ld/lld 2.42, GCC 13.3 (LLVM=1 used for all
hardened builds — required for kCFI and arm64 kernel PAC/BTI).
**Build host:** 4 vCPU, 15 GiB RAM. **Boot test:** QEMU 8.2 (TCG, no KVM).

> Scope honesty: "always-on whatever the arch" is implemented as **one common
> arch-neutral fragment (Tier A) that is always on**, plus **per-arch fragments
> (Tier C) that enable each hardware feature only where its Kconfig dependency
> is satisfied**. Hardware features are not — and cannot be — forced on arches
> that lack the silicon; the Kconfig dependency system makes them unselectable
> there, and they degrade to a clean no-op at runtime where the CPU lacks the
> feature (e.g. MTE/PAC/BTI gated on CPU ID registers).

## Deliverables

```
hardening/
  configs/
    hardening-common.config     # Tier A, arch-neutral, always on
    hardening-x86_64.config     # Tier C, x86_64
    hardening-arm64.config      # Tier C, arm64
    harness-support.config      # verification-only (IKCONFIG/debugfs); not hardening
  scripts/
    build.sh                    # out-of-tree (O=) hardened/baseline build, LLVM=1
    mkinitramfs.sh              # busybox initramfs that self-verifies + powers off
    boot.sh                     # QEMU boot, console capture, pass/fail verdict
    verify-config.sh            # reports actual =y/=n/absent state per symbol
  patches/
    README.md                   # Tier B outcome (SLAB_VIRTUAL: blocked)
    slab_virtual-thread.mbox.gz # archived LKML thread
    series/slab_virtual-01..14-*.patch
  REPORT.md                     # this file
```

## Reproduction

```sh
# x86_64 hardened
hardening/scripts/build.sh x86_64
hardening/scripts/verify-config.sh /home/user/build/x86_64-hardened/.config x86_64
hardening/scripts/boot.sh x86_64 /home/user/build/x86_64-hardened

# arm64 hardened (cross via clang/LLVM)
hardening/scripts/build.sh arm64
hardening/scripts/boot.sh arm64 /home/user/build/arm64-hardened

# clean baseline (harness sanity)
BASELINE=1 hardening/scripts/build.sh x86_64
hardening/scripts/boot.sh x86_64 /home/user/build/x86_64-baseline
```

---

## Symbol-drift corrections vs. the original spec (verified against 7.1-rc6)

| Spec symbol | Reality in 7.1-rc6 | Action |
|---|---|---|
| `CFI_CLANG` | now a **transitional** alias; live symbol is `CONFIG_CFI` | set `CONFIG_CFI=y` |
| `X86_SMAP` | **removed**; SMEP/SMAP unconditional on capable HW | dropped (nothing to set) |
| `X86_KERNEL_SHADOW_STACK` | **does not exist**; only `X86_USER_SHADOW_STACK` is merged; `X86_CET` is an auto-selected umbrella | user shadow stack only; noted |
| `STACKLEAK_RUNTIME_DISABLE` | boot/sysctl knob, **not** a Kconfig symbol | excluded |
| `GCC_PLUGIN_STACKLEAK` | GCC-plugin only; conflicts with the Clang/CFI build | excluded from common (note) |
| `FINEIBT` | auto-selected by `CFI` + `X86_KERNEL_IBT`; `CFI_AUTO_DEFAULT=y` | confirmed `=y` |

---

## Per-arch feature matrix

Legend: **Sym** = symbol exists in tree · **Set** = `=y` in produced .config ·
**Built** = compiled into image · **Booted** = reached userspace in QEMU ·
**Test** = runtime evidence (dmesg / lkdtm / sysfs).

### Tier A — arch-neutral software (common fragment)

| Feature (CONFIG_) | Sym | Set | Built (x86) | Booted (x86) | Test (x86) |
|---|:--:|:--:|:--:|:--:|---|
| INIT_ON_ALLOC_DEFAULT_ON | ✅ | ✅ | ✅ | ✅ | config.gz ✅ |
| INIT_ON_FREE_DEFAULT_ON | ✅ | ✅ | ✅ | ✅ | config.gz ✅ |
| INIT_STACK_ALL_ZERO | ✅ | ✅ | ✅ | ✅ | config.gz ✅ |
| SLAB_FREELIST_HARDENED | ✅ | ✅ | ✅ | ✅ | config.gz ✅ |
| SLAB_FREELIST_RANDOM | ✅ | ✅ | ✅ | ✅ | config.gz ✅ |
| RANDOM_KMALLOC_CACHES ⚠ | ✅ | ✅ | ✅ | ✅ | config.gz ✅ (keystone-gated) |
| SLAB_BUCKETS ⚠ | ✅ | ✅ | ✅ | ✅ | config.gz ✅ (keystone-gated) |
| SLAB_MERGE_DEFAULT=n | ✅ | ✅(n) | ✅ | ✅ | config.gz ✅ |
| HARDENED_USERCOPY | ✅ | ✅ | ✅ | ✅ | **lkdtm USERCOPY_KERNEL PASS** |
| FORTIFY_SOURCE | ✅ | ✅ | ✅ | ✅ | **lkdtm FORTIFY_STR_MEMBER PASS** |
| SHUFFLE_PAGE_ALLOCATOR | ✅ | ✅ | ✅ | ✅ | config.gz ✅ |
| DEBUG_LIST | ✅ | ✅ | ✅ | ✅ | **lkdtm CORRUPT_LIST_ADD PASS** |
| BUG_ON_DATA_CORRUPTION | ✅ | ✅ | ✅ | ✅ | **lkdtm CORRUPT_LIST_ADD PASS** |
| STACKPROTECTOR(_STRONG) | ✅ | ✅ | ✅ | ✅ | config.gz ✅ |
| ZERO_CALL_USED_REGS | ✅ | ✅ | ✅ | ✅ | config.gz ✅ |
| VMAP_STACK | ✅ | ✅ | ✅ | ✅ | config.gz ✅ |

⚠ keystone-gated — see Tier B. "config.gz ✅" = symbol confirmed `=y` in the
running kernel via `/proc/config.gz`; **bold lkdtm** = active enforcement
observed (kernel trapped the injected violation and panicked).

### Tier C — x86_64

| Feature (CONFIG_) | Sym | Set | Built | Booted | Test |
|---|:--:|:--:|:--:|:--:|---|
| CFI (kCFI) | ✅ | ✅ | ✅ | ✅ | **lkdtm CFI_FORWARD_PROTO PASS** (`CFI failure ... expected type 0x990a1c0a`); dmesg `CFI: Using rehashed retpoline kCFI` |
| X86_KERNEL_IBT | ✅ | ✅ | ✅ | ✅ | config.gz ✅ (HW IBT not exposed by QEMU TCG → kCFI path used; degrades cleanly) |
| FINEIBT (auto) | ✅ | ✅ | ✅ | ✅ | config.gz ✅ (selected; runtime uses kCFI as TCG lacks HW IBT) |
| X86_USER_SHADOW_STACK | ✅ | ✅ | ✅ | ✅ | config.gz ✅ |
| X86_UMIP | ✅ | ✅ | ✅ | ✅ | config.gz ✅ |
| RANDOMIZE_BASE / _MEMORY | ✅ | ✅ | ✅ | ✅ | config.gz ✅ |

### Tier C — arm64

| Feature (CONFIG_) | Sym | Set | Built | Booted | Test |
|---|:--:|:--:|:--:|:--:|---|
| CFI (kCFI) | ✅ | ✅ | _pending_ | _pending_ | _pending_ |
| ARM64_PTR_AUTH(_KERNEL) | ✅ | ✅ | _pending_ | _pending_ | dmesg "pointer authentication" |
| ARM64_BTI(_KERNEL) | ✅ | ✅ | _pending_ | _pending_ | dmesg BTI |
| ARM64_E0PD | ✅ | ✅ | _pending_ | _pending_ | _pending_ |
| ARM64_EPAN | ✅ | ✅ | _pending_ | _pending_ | _pending_ |
| ARM64_MTE | ✅ | ✅ | _pending_ | _pending_ | dmesg MTE (qemu cpu max,mte=on) |
| KASAN_HW_TAGS | ✅ | ✅ | _pending_ | _pending_ | kasan.mode boot knob |
| ARM64_GCS | ✅ | ✅ | _pending_ | _pending_ | _pending_ |
| RANDOMIZE_BASE | ✅ | ✅ | _pending_ | _pending_ | _pending_ |

---

## Tier B — out-of-tree (SLAB_VIRTUAL keystone): **BLOCKED**

See `patches/README.md` for the full table. Summary: the
`[RFC PATCH 00/14] Prevent cross-cache attacks in the SLUB allocator` series
(Rizzo/Horn, 2023-09-15, base `46a9ea668190` ≈ v6.6-rc1) does **not** rebase
onto 7.1-rc6 — `git am --3way` fails on patch 01, and `git apply --check` shows
only the 2 non-code patches (Kconfig 08, docs 14) apply; all 12 SLUB/x86 patches
fail because the freepointer codec and folio→slab paths were rewritten upstream.
Per the rules, no allocator internals were hand-written. **Not integrated.**

**Keystone consequence:** without address-space sequestering,
`RANDOM_KMALLOC_CACHES` + `SLAB_BUCKETS` are **not** a cross-cache mitigation on
their own and may be net-negative. They are shipped per spec but must not be
counted as a cross-cache win. Typed caches (Tier B step 2) were **not** enabled
(strictly gated on the keystone). Additional blocker: SLAB_VIRTUAL is documented
incompatible with KASAN/KFENCE, colliding with the arm64 `KASAN_HW_TAGS` profile.

---

## Tier D — out of scope (not fabricated)

- **SPTM/PPL-style higher-privilege monitor:** no in-tree equivalent. Adjacent
  real work: pKVM on supported arm64, and the Heki (hypervisor-enforced kernel
  integrity) patches. Requires a hypervisor layer outside a kernel build/patch
  task. Not implemented.
- **Rust migration of existing C subsystems:** `CONFIG_RUST` exists and new code
  may be written in Rust; rewriting the C allocators is a multi-year effort, not
  a config task. Not implemented.

---

## Performance / operational notes

- `init_on_alloc`/`init_on_free` impose a measurable allocation-path cost
  (single-digit % on alloc-heavy workloads); intentional, not dropped.
- arm64 MTE: `KASAN_HW_TAGS` ships built-in; runtime mode is an **operator boot
  decision** via `kasan=on|off` and `kasan.mode=sync|async|asymm`. Sync is the
  strongest (precise faults) but costliest; async is the typical prod default.
  Not hard-wired to sync.
- FineIBT is selected automatically and enabled by default at boot
  (`CFI_AUTO_DEFAULT=y`) **on IBT-capable hardware**. Under QEMU TCG (no HW IBT)
  the kernel cleanly falls back to plain kCFI (`CFI: Using rehashed retpoline
  kCFI` in dmesg) — a concrete demonstration of "enforce where present, degrade
  to a clean path where the silicon is absent." Forward-edge CFI enforcement is
  still active in that fallback (verified by lkdtm CFI_FORWARD_PROTO).
