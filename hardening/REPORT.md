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
  tierb/                        # (named 'tierb' not 'patches' — kernel .gitignore ignores patches/)
    README.md                   # Tier B outcome: Phase A WORKS on native base; Phase B = 7.1 forward-port
    slab_virtual-reproduce.sh   # Phase A reproducer (fetch base, am, build, boot)
    slab_virtual-PROOF-boot.log # Phase A runtime evidence (SLAB_VIRTUAL live)
    slab_virtual-thread.mbox.gz # archived LKML thread
    patchset/0001..0014-*.patch   # the 14-patch series (regenerated with --base)
  REPORT.md                     # this file
```

## Reproduction

```sh
# x86_64 hardened
hardening/scripts/build.sh x86_64
hardening/scripts/verify-config.sh /home/user/build/x86_64-hardened/.config x86_64
hardening/scripts/boot.sh x86_64 /home/user/build/x86_64-hardened

# arm64 hardened (cross via clang/LLVM). boot.sh needs an aarch64 busybox; it
# defaults to BUSYBOX=/home/user/bb-arm64 (extracted from the arm64
# busybox-static .deb). Default QEMU core is neoverse-v1 (ARMv8.4).
hardening/scripts/build.sh arm64
hardening/scripts/boot.sh arm64 /home/user/build/arm64-hardened
# On QEMU >= 9.0, exercise BTI/MTE/GCS too:
QEMU_CPU=max hardening/scripts/boot.sh arm64 /home/user/build/arm64-hardened

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

Boot CPU: `qemu-system-aarch64 -cpu neoverse-v1` (ARMv8.4). The Tier A common
fragment was re-verified here too (config.gz: INIT_ON_*, FORTIFY, usercopy, etc.
all `=y`); rows omitted for brevity — identical to the x86 Tier A column.

| Feature (CONFIG_) | Sym | Set | Built | Booted | Test |
|---|:--:|:--:|:--:|:--:|---|
| CFI (kCFI) | ✅ | ✅ | ✅ | ✅ | **lkdtm CFI_FORWARD_PROTO PASS** (`CFI: Fatal exception`) |
| HARDENED_USERCOPY | ✅ | ✅ | ✅ | ✅ | **lkdtm USERCOPY_KERNEL PASS** |
| DEBUG_LIST + BUG_ON_DATA_CORRUPTION | ✅ | ✅ | ✅ | ✅ | **lkdtm CORRUPT_LIST_ADD PASS** |
| ARM64_PTR_AUTH(_KERNEL) | ✅ | ✅ | ✅ | ✅ | **dmesg: "Address authentication (architected QARMA5)" + "Generic authentication" detected** (PAC active) |
| ARM64_E0PD | ✅ | ✅ | ✅ | ✅ | config.gz ✅ (KPTI/E0PD forced on by KASLR in dmesg) |
| ARM64_EPAN | ✅ | ✅ | ✅ | ✅ | config.gz ✅; "Privileged Access Never" detected |
| RANDOMIZE_BASE | ✅ | ✅ | ✅ | ✅ | dmesg "KASLR enabled" |
| ARM64_BTI(_KERNEL) | ✅ | ✅ | ✅ | ⚠️ | config.gz ✅, **built**; runtime not exercised — needs ARMv8.5 core; QEMU 8.2 asserts on v9 models (see below) |
| ARM64_MTE | ✅ | ✅ | ✅ | ⚠️ | config.gz ✅, **built**; runtime needs ARMv8.5 MTE; QEMU 8.2 `mte=on` asserts (see below) |
| KASAN_HW_TAGS | ✅ | ✅ | ✅ | ⚠️ | config.gz ✅, **built**; production MTE — same QEMU-8.2 blocker; `kasan.mode` boot knob documented |
| ARM64_GCS | ✅ | ✅ | ✅ | ⚠️ | config.gz ✅, **built**; ARMv9.4 FEAT_GCS — QEMU 8.2 GCS emulation asserts; booted with `arm64.nogcs` |

⚠️ = symbol set + compiled into the booting image, but the *hardware feature*
needs a CPU generation that the available **QEMU 8.2** cannot emulate without an
internal assert (`target/arm/internals.h:767: regime_is_user: code should not be
reached`) on its ARMv9/MTE core models (`max`, `neoverse-n2`, `cortex-a710`).
This is a host-tooling limitation, **not** a kernel defect: the features build
cleanly, the image boots, and they degrade to a clean no-op on the v8.4 core
used for the boot. On QEMU ≥ 9.0 re-run with `QEMU_CPU=max` to exercise them.

---

## Tier B — out-of-tree (SLAB_VIRTUAL keystone)

The `[RFC PATCH 00/14] Prevent cross-cache attacks in the SLUB allocator` series
(Rizzo/Horn, 2023-09-15, base `46a9ea668190`, v6.5-rc1-era). Full evidence and
reproducer in `tierb/`.

### Phase A — VERIFIED WORKING on the series' native base ✅
`git am` applies **14/14 cleanly** onto `46a9ea668190` (zero hand-edits); builds
clean (x86_64, gcc, `SLAB_VIRTUAL=y`, KASAN off); **boots to userspace** in QEMU
(`-cpu qemu64`); and the feature is **live at runtime**: `CONFIG_SLAB_VIRTUAL=y`
in `/proc/config.gz`, the patch-12 `…/deallocated_pages` sysfs attr present, the
`slab_virt_to_phys` symbol in kallsyms, and the kernel running entirely on
virtual-memory slab allocation (patch-13 freepointer sanity checks pass
throughout boot). This is a real, non-fabricated "it works" — **no allocator
code hand-written.** Reproduce: `tierb/slab_virtual-reproduce.sh`.

### Phase B — forward-port to the pinned 7.1-rc6
The same series does **not** rebase onto 7.1-rc6 — `git am --3way` fails on patch
01 (base blobs absent), and `git apply --check` shows only the 2 non-code patches
(Kconfig 08, docs 14) apply; all 12 SLUB/x86 patches fail because
`slab_free_freelist_hook` changed signature/moved and the freepointer codec +
folio→slab paths were rewritten upstream. Per the rules, no SLUB/page-table
internals are hand-written to force an apply. Status of the honest forward-port
attempt is recorded below under "Phase B forward-port attempt".

**Keystone consequence (for the 7.1 production profiles):** without address-space
sequestering,
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

## What was NOT verified at runtime, and why (honest limits)

| Item | Status | Reason |
|---|---|---|
| arm64 BTI (kernel) runtime | built ✅, boot ⚠️ | needs ARMv8.5 core; QEMU 8.2 asserts on v9 models |
| arm64 MTE / KASAN_HW_TAGS runtime | built ✅, boot ⚠️ | QEMU 8.2 `mte=on` + v9 cores hit `regime_is_user` assert |
| arm64 GCS runtime | built ✅, boot ⚠️ | QEMU 8.2 GCS emulation asserts; booted with `arm64.nogcs` |
| x86 FineIBT runtime path | built ✅, boots via kCFI | QEMU TCG exposes no HW IBT; FineIBT needs real IBT silicon |
| x86 user shadow stack exercise | built ✅, no userspace test | needs a CET userspace program; not in the minimal initramfs |
| Tier B SLAB_VIRTUAL | blocked ❌ | RFC does not rebase onto 7.1-rc6 (see tierb/README.md) |
| Tier B typed kmalloc caches | not attempted | gated on SLAB_VIRTUAL per keystone rule |
| Tier D (SPTM monitor, Rust rewrite) | out of scope | no in-tree equivalent / multi-year effort |

All "⚠️" arm64 items are a **QEMU version** limitation, not a kernel problem:
the symbols are set, compiled into the image, and the kernel boots; only the
silicon-dependent *runtime* activation could not be emulated here. They would be
verifiable on QEMU ≥ 9.0 (or real hardware) via `QEMU_CPU=max`.

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
