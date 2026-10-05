#!/usr/bin/env bash
# Verify the additive vendor tracepoint ABI in a final Image and optional vendor modules.
set -euo pipefail
IMG="${1:?usage: verify-vendor-hooks.sh <Image> [vendor-module-dir] [vmlinux|System.map] }"
MODDIR="${2:-${VENDOR_MODULE_DIR:-}}"
SYMSRC="${3:-${KERNEL_SYMBOL_SOURCE:-}}"
[ -f "$IMG" ] || { echo "::error::Image not found: $IMG"; exit 1; }
HOOKS=(
  android_rvh_do_madvise_bypass android_rvh_do_traversal_lruvec_ex
  android_rvh_kswapd_shrink_node android_rvh_perform_reclaim
  android_vh_check_set_ioprio android_vh_clear_reclaimed_folio
  android_vh_do_shrink_slab_ex android_vh_evict_folios_bypass
  android_vh_filemap_fault_pre_folio_locked android_vh_filemap_folio_mapped
  android_vh_filemap_pages android_vh_folio_add_lru_folio_activate
  android_vh_folio_remove_rmap_ptes android_vh_keep_reclaimed_folio
  android_vh_lru_gen_add_folio_skip android_vh_lru_gen_del_folio_skip
  android_vh_mmput_mm
)
# Prefer the uncompressed vmlinux/System.map symbol source.  A compressed Image
# may contain tokenized kallsyms, so a raw `strings` scan is only a fallback.
SYMFILE="$(mktemp)"
MODSYMFILE="$(mktemp)"
trap 'rm -f "$SYMFILE" "$MODSYMFILE"' EXIT
if [ -n "$SYMSRC" ]; then
  [ -f "$SYMSRC" ] || { echo "::error::symbol source not found: $SYMSRC"; exit 1; }
  magic="$(od -An -tx1 -N4 "$SYMSRC" | tr -d '[:space:]')"
  if [ "$magic" = "7f454c46" ]; then
    NM="${NM:-}"
    if [ -z "$NM" ]; then
      for candidate in llvm-nm nm; do
        if command -v "$candidate" >/dev/null 2>&1; then NM="$candidate"; break; fi
      done
    fi
    [ -n "$NM" ] || { echo "::error::llvm-nm/nm required for vmlinux ABI check"; exit 1; }
    "$NM" -a "$SYMSRC" | awk '{print $NF}' >"$SYMFILE"
    echo "==> checking symbols from ELF $SYMSRC"
  else
    awk '{print $NF}' "$SYMSRC" >"$SYMFILE"
    echo "==> checking symbols from map $SYMSRC"
  fi
else
  strings "$IMG" >"$SYMFILE"
  echo "::warning::no vmlinux/System.map supplied; falling back to Image strings (export names cannot be checked reliably)"
fi
CHECK_EXPORTS=0
[ -n "$SYMSRC" ] && CHECK_EXPORTS=1
for hook in "${HOOKS[@]}"; do
  grep -Fxq "__traceiter_${hook}" "$SYMFILE" \
    || { echo "::error::symbol source missing __traceiter_${hook}"; exit 1; }
  grep -Fxq "__tracepoint_${hook}" "$SYMFILE" \
    || { echo "::error::symbol source missing __tracepoint_${hook}"; exit 1; }
  if [ "$CHECK_EXPORTS" -eq 1 ]; then
    grep -Fxq "__ksymtab___tracepoint_${hook}" "$SYMFILE" \
      || { echo "::error::symbol source missing export __ksymtab___tracepoint_${hook}"; exit 1; }
  fi
done
if [ "$CHECK_EXPORTS" -eq 1 ]; then
  echo "==> symbol source contains all ${#HOOKS[@]} traceiter/tracepoint/export triplets"
else
  echo "==> Image contains all ${#HOOKS[@]} traceiter/tracepoint names"
fi

if [ -n "$MODDIR" ]; then
  [ -d "$MODDIR" ] || { echo "::error::vendor module directory not found: $MODDIR"; exit 1; }
  READelf="${READELF:-}"
  if [ -z "$READelf" ]; then
    for candidate in llvm-readelf readelf; do
      if command -v "$candidate" >/dev/null 2>&1; then READelf="$candidate"; break; fi
    done
  fi
  [ -n "$READelf" ] || { echo "::error::llvm-readelf/readelf required for module ABI check"; exit 1; }
  find "$MODDIR" -type f -name '*.ko' -print0 \
    | while IFS= read -r -d '' ko; do
        "$READelf" -Ws "$ko" 2>/dev/null \
          | awk '$7 == "UND" {print $8}' \
          | grep '^__tracepoint_android_' || true
      done | sort -u >"$MODSYMFILE"
  while IFS= read -r sym; do
    [ -n "$sym" ] || continue
    grep -Fxq "$sym" "$SYMFILE" \
      || { echo "::error::vendor module unresolved hook absent from Image: $sym"; exit 1; }
  done <"$MODSYMFILE"
  echo "==> vendor module tracepoint references are closed over Image exports"
else
  echo "::notice::vendor module directory not supplied; Image ABI check only"
fi
