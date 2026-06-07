# Tier B out-of-tree series — SLAB_VIRTUAL (the keystone)

- **Series:** `[RFC PATCH 00/14] Prevent cross-cache attacks in the SLUB allocator`
- **Authors:** Matteo Rizzo, Jann Horn (Google) · **Posted:** 2023-09-15 (LKML)
- **Cover message-id:** `20230915105933.495735-1-matteorizzo@google.com`
- **Declared base-commit:** `46a9ea6681907a3be6b6b0d43776dccc62cad6cf` (v6.5-rc1-era)
- **Thread mbox:** `slab_virtual-thread.mbox.gz`
- **Series (14 patches, with `--base`):** `patchset/0001..0014-*.patch`

## Phase A — VERIFIED WORKING on the series' native base ✅

Reproducer: `slab_virtual-reproduce.sh`. Evidence: `slab_virtual-PROOF-boot.log`.

| Gate | Result |
|---|---|
| `git am` of all 14 patches onto `46a9ea668190` | **clean, 14/14, zero hand-edits** |
| Build (`x86_64`, gcc 13.3, `CONFIG_SLAB_VIRTUAL=y`, KASAN off) | **clean** |
| Boot in QEMU (`-cpu qemu64`) to userspace | **PASS** (`HARNESS-BOOT-OK` + clean power-down) |
| `CONFIG_SLAB_VIRTUAL=y` in running kernel (`/proc/config.gz`) | **confirmed** |
| Patch-12 sysfs attr `…/deallocated_pages` live | **present** (`/sys/kernel/slab/:d-0001024/deallocated_pages = 0`) |
| Virtual-slab allocator symbol `slab_virt_to_phys` in kallsyms | **present** |
| Kernel runs entirely on virtual-memory slab allocation | **yes** (boots; patch-13 freepointer sanity checks pass throughout) |

This is the honest "it works": the keystone applies, builds, boots, and the
feature is live at runtime — with **no allocator code written by hand**.

Caveats (inherent, not defects):
- Base is v6.5-rc1; **x86_64-only** (no arm64 slab-virtual in the series).
- SLAB_VIRTUAL is **incompatible with KASAN and KFENCE**, so it cannot be
  combined with the 7.1 arm64 `KASAN_HW_TAGS` (MTE) profile.
- QEMU 8.2 hangs this v6.5 kernel under `-cpu max`; boot with `-cpu qemu64`.

## Phase B — forward-port to the pinned 7.1-rc6: status

The same 14 patches do **not** rebase onto 7.1-rc6: `git am --3way` fails on
patch 01 (`sha1 information is lacking or useless (mm/slub.c)` — base blobs
absent), and `git apply --check` shows only the 2 non-code patches (Kconfig 08,
docs 14) apply; all 12 SLUB/x86 patches fail because `slab_free_freelist_hook`
changed signature and moved, and the freepointer codec + folio→slab paths were
rewritten upstream (mm/slub.c grew to ~9,950 lines). See REPORT.md "Phase B" for
the outcome of the honest, clearly-caveated forward-port attempt. Per the task
rules, no SLUB/page-table internals are hand-written to force an apply.

## Keystone consequence for Tier A separation features

Without address-space sequestering in the *production* (7.1) kernels,
`RANDOM_KMALLOC_CACHES` + `SLAB_BUCKETS` are **not** a cross-cache mitigation on
their own and may be net-negative. They ship per spec but are flagged, not
counted as a cross-cache win. Typed caches (Tier B step 2) remain gated on the
keystone and are not enabled in the 7.1 profiles.
