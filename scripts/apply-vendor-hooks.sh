#!/usr/bin/env bash
# Apply Xiaomi/Android15-8 vendor trace hooks needed by the Mi15 vendor modules.
set -euo pipefail
KDIR="${1:?usage: apply-vendor-hooks.sh <kernel-dir> [patch-file]}"
PATCH="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../patches/vendor-hooks" && pwd)/001-mi15-android15-8-mm-vendor-hooks.patch}"
[ -d "$KDIR" ] || { echo "::error::kernel tree not found: $KDIR"; exit 1; }
[ -s "$PATCH" ] || { echo "::error::vendor hook patch not found: $PATCH"; exit 1; }
git -C "$KDIR" diff --quiet HEAD -- include/trace/hooks drivers/android/vendor_hooks.c kernel/sched/vendor_hooks.c \
  mm/madvise.c mm/memcontrol.c mm/page_alloc.c mm/vmscan.c mm/filemap.c mm/swap.c mm/rmap.c \
  block/blk-mq.c kernel/fork.c include/linux/mm_inline.h \
  || { echo "::error::vendor hook targets already modified; refusing a mixed apply"; exit 1; }
git -C "$KDIR" apply --check "$PATCH"
git -C "$KDIR" apply "$PATCH"
git -C "$KDIR" diff --check
for sym in \
  android_rvh_do_madvise_bypass android_rvh_do_traversal_lruvec_ex \
  android_rvh_kswapd_shrink_node android_rvh_perform_reclaim \
  android_vh_check_set_ioprio android_vh_clear_reclaimed_folio \
  android_vh_do_shrink_slab_ex android_vh_evict_folios_bypass \
  android_vh_filemap_fault_pre_folio_locked android_vh_filemap_folio_mapped \
  android_vh_filemap_pages android_vh_folio_add_lru_folio_activate \
  android_vh_folio_remove_rmap_ptes android_vh_keep_reclaimed_folio \
  android_vh_lru_gen_add_folio_skip android_vh_lru_gen_del_folio_skip \
  android_vh_mmput_mm; do
  grep -R -q -- "$sym" "$KDIR/include/trace/hooks" "$KDIR/drivers/android/vendor_hooks.c" \
    "$KDIR/kernel/sched/vendor_hooks.c" || { echo "::error::missing applied hook $sym"; exit 1; }
done
echo "==> 17 Mi15 vendor hooks applied"
