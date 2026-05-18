#!/usr/bin/env bash
# clean.sh — wipe all generated output from sweeps and single runs.
#
# Usage:
#   ./tools/clean.sh           # clears everything
#   ./tools/clean.sh --dry-run # shows what would be deleted

set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

DIRS=(
    "tmp/sweep"
    "Output/Sweep"
    "Output/Videos"
    "Output/Images"
    "Output/Logs"
    "Output/Saves"
    "Output/Profiling"
    "Output/analysis_panels"
)
FILES=(
    "Output/analysis.png"
    "Output/analysis_report.md"
)
ZIPS="sweep_*.zip"

echo "Cleaning generated output..."

for d in "${DIRS[@]}"; do
    if [[ -d "$d" ]]; then
        echo "  rm -rf $d/*"
        [[ $DRY_RUN -eq 0 ]] && rm -rf "${d:?}"/* 2>/dev/null || true
    fi
done

for f in "${FILES[@]}"; do
    if [[ -f "$f" ]]; then
        echo "  rm $f"
        [[ $DRY_RUN -eq 0 ]] && rm -f "$f"
    fi
done

for z in $ZIPS; do
    if [[ -f "$z" ]]; then
        echo "  rm $z"
        [[ $DRY_RUN -eq 0 ]] && rm -f "$z"
    fi
done

echo "Done."
