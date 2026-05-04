#!/usr/bin/env bash
# postrun.sh — run after a biosim4 simulation to:
#   1. Convert all Output/Images/*.txt edge-lists → .svg
#   2. Run the analysis pipeline  → Output/analysis.png
#   3. (optional) Remove the .txt and .svg source files to keep things tidy
#
# Usage:
#   ./tools/postrun.sh            # convert + analyse, keep all files
#   ./tools/postrun.sh --clean    # convert + analyse, then delete .txt + .svg
#   ./tools/postrun.sh --wipe     # delete EVERYTHING in Output/ (fresh slate)

set -euo pipefail

PYTHON=".venv/bin/python3"
IMAGES_DIR="Output/Images"
LOG_FILE="Output/Logs/epoch-log.txt"
ANALYSIS_OUT="Output/analysis.png"
SMOOTH=5

MODE="${1:-}"

# ── helpers ───────────────────────────────────────────────────────────────────
count_files() { ls "$1" 2>/dev/null | wc -l | tr -d ' '; }

# ── --wipe: blow away all output and exit ─────────────────────────────────────
if [[ "$MODE" == "--wipe" ]]; then
    echo "Wiping Output/Images (*.txt, *.svg) and Output/Logs/epoch-log.txt ..."
    rm -f "$IMAGES_DIR"/*.txt "$IMAGES_DIR"/*.svg
    rm -f "$LOG_FILE"
    rm -f "$ANALYSIS_OUT"
    echo "Done. Output directory is clean."
    exit 0
fi

# ── Step 1: convert .txt → .svg ───────────────────────────────────────────────
txt_files=("$IMAGES_DIR"/*.txt)
if [[ ! -e "${txt_files[0]}" ]]; then
    echo "No .txt files found in $IMAGES_DIR — nothing to convert."
else
    total=${#txt_files[@]}
    echo "Converting $total edge-list file(s) to SVG ..."
    ok=0
    for f in "${txt_files[@]}"; do
        out="${f%.txt}.svg"
        if $PYTHON tools/graph-nnet.py -i "$f" -o "$out" 2>/dev/null; then
            (( ok++ )) || true
        else
            echo "  WARNING: failed to convert $f"
        fi
    done
    echo "  $ok / $total converted successfully."
fi

# ── Step 2: run analysis pipeline ────────────────────────────────────────────
if [[ -f "$LOG_FILE" ]]; then
    echo "Running analysis pipeline ..."
    $PYTHON tools/analyse.py \
        --log  "$LOG_FILE" \
        --nets "$IMAGES_DIR" \
        --out  "$ANALYSIS_OUT" \
        --smooth "$SMOOTH"
else
    echo "No epoch log found at $LOG_FILE — skipping analysis."
fi

# ── Step 3 (--clean): remove .txt and .svg files ─────────────────────────────
if [[ "$MODE" == "--clean" ]]; then
    n_txt=$(count_files "$IMAGES_DIR/*.txt")
    n_svg=$(count_files "$IMAGES_DIR/*.svg")
    echo "Cleaning up: removing $n_txt .txt and $n_svg .svg files from $IMAGES_DIR ..."
    rm -f "$IMAGES_DIR"/*.txt "$IMAGES_DIR"/*.svg
    echo "Done."
fi

echo ""
echo "All done. Analysis saved to: $ANALYSIS_OUT"
