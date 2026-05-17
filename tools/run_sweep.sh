#!/usr/bin/env bash
# run_sweep.sh — structured parameter sweep for biosim4 predator-prey experiments.
#
# Runs three experiment groups:
#   B1  environment alone            (4 challenges × 3 seeds = 12 runs)
#   B2  mutation rate × environment  (3 rates × 2 environments × 3 seeds = 18 runs)
#   B3  predator fraction × environment (3 fractions × 2 environments × 3 seeds = 18 runs)
#
# Output layout per run:
#   Output/Sweep_<timestamp>/
#     B1_environment/
#       ch20_open/
#         seed_1/
#           logs/epoch-log.txt
#           videos/                    (populated if saveVideo = true in biosim4.ini)
#           analysis/analysis.png
#           analysis/analysis_report.md
#           analysis/analysis_panels/
#           run.ini                    (exact ini used — fully reproducible)
#           simulator.stdout
#         seed_2/ ...
#         seed_3/ ...
#       ch00_circle/ ...
#     B2_mutation_x_env/ ...
#     B3_fraction_x_env/ ...
#     sweep_summary.md
#   sweep_<timestamp>.zip              (everything above, ready to hand off)
#
# Usage:
#   ./tools/run_sweep.sh
#   ./tools/run_sweep.sh --dry-run    # print what would run, no simulator calls

set -euo pipefail

# =============================================================================
#  EXPERIMENT MATRIX  ← edit this block
# =============================================================================

SEEDS=(1 2 3)

# B1 — environment alone (everything else at baseline from biosim4.ini)
B1_CHALLENGES=(20 0 5 11)          # open, circle, corner, wall

# B2 — mutation rate × environment
B2_MUTATION_RATES=(0.0001 0.001 0.01)
B2_CHALLENGES=(20 0)               # open, circle

# B3 — predator fraction × environment
B3_PRED_FRACTIONS=(0.25 0.50 0.75)
B3_CHALLENGES=(20 0)               # open, circle

MAX_GENERATIONS=10                # increase for final runs

# ── run mode ─────────────────────────────────────────────────────────────────
# HEADLESS=true   → no GUI window; safe to run on servers or in background.
#                   saveVideo is automatically forced off (nothing to capture).
# HEADLESS=false  → shows the SFML window; requires a display.
#                   saveVideo follows SAVE_VIDEO below.
HEADLESS=true
SAVE_VIDEO=false       # only used when HEADLESS=false

# =============================================================================

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

BASE_INI="biosim4.ini"
TMP_DIR="tmp/sweep"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SWEEP_DIR="Output/Sweep"
SWEEP_ROOT="${SWEEP_DIR}/run_${TIMESTAMP}"
PYTHON=".venv/bin/python3"
BIO="./bin/Release/biosim4"

mkdir -p "$TMP_DIR"

# =============================================================================
#  HELPERS
# =============================================================================

# Read a key from an ini file; strips inline comments and whitespace.
get_kv() {
    local file="$1" key="$2" default="${3:-}"
    local val
    val=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" 2>/dev/null \
          | tail -1 \
          | sed -E "s|^[[:space:]]*${key}[[:space:]]*=[[:space:]]*||" \
          | sed 's/[[:space:]]*#.*//' \
          | tr -d '[:space:]') || true
    echo "${val:-$default}"
}

# Set or insert "key = value" in an ini file (BSD + GNU sed compatible).
set_kv() {
    local file="$1" key="$2" value="$3"
    if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
        sed -i.bak -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$file"
        rm -f "${file}.bak"
    else
        printf '\n%s = %s\n' "$key" "$value" >> "$file"
    fi
}

# Human-readable name for a challenge number.
ch_name() {
    case "$1" in
        20) echo "open"   ;;
         0) echo "circle" ;;
         5) echo "corner" ;;
        11) echo "wall"   ;;
         *) echo "ch${1}" ;;
    esac
}

# run_one <group_dir> <run_label> <seed> [key value ...]
#
# Runs a single (label, seed) combination.
#   - Builds a per-run ini from biosim4.ini, applies all overrides
#   - Points logDir / imageDir at per-run subdirs so outputs land in the right place
#   - Propagates saveVideo from biosim4.ini (does NOT force it off)
#   - Runs the simulator, then analyse.py
run_one() {
    local group_dir="$1"
    local run_label="$2"
    local seed="$3"
    shift 3
    # $@ = key value key value ... (experiment-specific overrides)

    local run_dir="${group_dir}/${run_label}/seed_${seed}"
    local log_dir="${run_dir}/logs"
    local vid_dir="${run_dir}/videos"
    local ana_dir="${run_dir}/analysis"
    local ini="${TMP_DIR}/${run_label}_seed${seed}.ini"

    echo "  seed=${seed}  →  ${run_dir}"
    if [[ $DRY_RUN -eq 1 ]]; then return; fi

    mkdir -p "$log_dir" "$vid_dir" "$ana_dir"

    # ── build ini ────────────────────────────────────────────────────────────
    cp "$BASE_INI" "$ini"

    # Mandatory structural settings
    set_kv "$ini" "predatorPreyEnabled"  "true"
    set_kv "$ini" "maxGenerations"       "$MAX_GENERATIONS"
    set_kv "$ini" "deterministic"        "true"
    set_kv "$ini" "RNGSeed"              "$seed"
    set_kv "$ini" "updateGraphLog"       "false"   # skip per-step graph logs in sweep

    # Per-run output dirs — simulator writes epoch-log.txt to logDir,
    # and video frames/mp4 to imageDir.
    set_kv "$ini" "logDir"   "$log_dir"
    set_kv "$ini" "imageDir" "$vid_dir"

    # Video: headless can't capture frames (no window to render into).
    if [[ "$HEADLESS" == "true" ]]; then
        set_kv "$ini" "saveVideo" "false"
    else
        set_kv "$ini" "saveVideo" "$SAVE_VIDEO"
    fi

    # Apply experiment-specific overrides passed as arguments
    while (( $# >= 2 )); do
        set_kv "$ini" "$1" "$2"
        shift 2
    done

    # Save an exact copy of what was used (for reproducibility)
    cp "$ini" "${run_dir}/run.ini"

    # ── run simulator ─────────────────────────────────────────────────────────
    local headless_flag=""
    [[ "$HEADLESS" == "true" ]] && headless_flag="--headless"
    "$BIO" "$ini" $headless_flag > "${run_dir}/simulator.stdout" 2>&1 || {
        echo "    ! simulator failed — see ${run_dir}/simulator.stdout"
        return
    }

    if [[ ! -f "${log_dir}/epoch-log.txt" ]]; then
        echo "    ! no epoch log produced; skipping analysis"
        return
    fi

    # ── run analysis ──────────────────────────────────────────────────────────
    "$PYTHON" tools/analyse.py \
        --log    "${log_dir}/epoch-log.txt" \
        --nets   "${vid_dir}" \
        --out    "${ana_dir}/analysis.png" \
        --report "${ana_dir}/analysis_report.md" \
        --split-figures \
        --title  "${run_label} | seed ${seed}" \
        > "${ana_dir}/analyse.stdout" 2>&1 || {
        echo "    ! analysis failed — see ${ana_dir}/analyse.stdout"
    }
}

# =============================================================================
#  RUN COUNTS
# =============================================================================
b1_total=$(( ${#B1_CHALLENGES[@]} * ${#SEEDS[@]} ))
b2_total=$(( ${#B2_MUTATION_RATES[@]} * ${#B2_CHALLENGES[@]} * ${#SEEDS[@]} ))
b3_total=$(( ${#B3_PRED_FRACTIONS[@]} * ${#B3_CHALLENGES[@]} * ${#SEEDS[@]} ))
total=$(( b1_total + b2_total + b3_total ))

echo "======================================================================"
echo "  biosim4 parameter sweep  —  ${TIMESTAMP}"
echo "  Output root : ${SWEEP_ROOT}"
if [[ "$HEADLESS" == "true" ]]; then
    echo "  mode        : headless (saveVideo forced off)"
else
    echo "  mode        : windowed (saveVideo = ${SAVE_VIDEO})"
fi
echo "  B1 environment             : ${b1_total} runs"
echo "  B2 mutation × environment  : ${b2_total} runs"
echo "  B3 fraction × environment  : ${b3_total} runs"
echo "  Total                      : ${total} runs"
echo "======================================================================"
echo

[[ $DRY_RUN -eq 1 ]] && echo "[DRY RUN — simulator will not be called]" && echo

[[ $DRY_RUN -eq 0 ]] && mkdir -p "$SWEEP_ROOT"

# =============================================================================
#  B1 — ENVIRONMENT ALONE
# =============================================================================
echo "── B1  Environment alone ──────────────────────────────────────────────"
B1_DIR="${SWEEP_ROOT}/B1_environment"
[[ $DRY_RUN -eq 0 ]] && mkdir -p "$B1_DIR"
run_i=0

for ch in "${B1_CHALLENGES[@]}"; do
    label="ch$(printf '%02d' "$ch")_$(ch_name "$ch")"
    for seed in "${SEEDS[@]}"; do
        run_i=$(( run_i + 1 ))
        echo "[B1 ${run_i}/${b1_total}]  ${label}"
        run_one "$B1_DIR" "$label" "$seed" \
            "challenge" "$ch"
    done
done

# =============================================================================
#  B2 — MUTATION RATE × ENVIRONMENT
# =============================================================================
echo
echo "── B2  Mutation rate × environment ────────────────────────────────────"
B2_DIR="${SWEEP_ROOT}/B2_mutation_x_env"
[[ $DRY_RUN -eq 0 ]] && mkdir -p "$B2_DIR"
run_i=0

for mut in "${B2_MUTATION_RATES[@]}"; do
    mut_tag="${mut//./_}"            # 0.001 → 0_001
    for ch in "${B2_CHALLENGES[@]}"; do
        label="ch$(printf '%02d' "$ch")_$(ch_name "$ch")_mut${mut_tag}"
        for seed in "${SEEDS[@]}"; do
            run_i=$(( run_i + 1 ))
            echo "[B2 ${run_i}/${b2_total}]  ${label}"
            run_one "$B2_DIR" "$label" "$seed" \
                "challenge"         "$ch" \
                "pointMutationRate" "$mut"
        done
    done
done

# =============================================================================
#  B3 — PREDATOR FRACTION × ENVIRONMENT
# =============================================================================
echo
echo "── B3  Predator fraction × environment ────────────────────────────────"
B3_DIR="${SWEEP_ROOT}/B3_fraction_x_env"
[[ $DRY_RUN -eq 0 ]] && mkdir -p "$B3_DIR"
run_i=0

for pf in "${B3_PRED_FRACTIONS[@]}"; do
    pf_tag="${pf//./_}"              # 0.25 → 0_25
    for ch in "${B3_CHALLENGES[@]}"; do
        label="ch$(printf '%02d' "$ch")_$(ch_name "$ch")_pf${pf_tag}"
        for seed in "${SEEDS[@]}"; do
            run_i=$(( run_i + 1 ))
            echo "[B3 ${run_i}/${b3_total}]  ${label}"
            run_one "$B3_DIR" "$label" "$seed" \
                "challenge"        "$ch" \
                "predatorFraction" "$pf"
        done
    done
done

# =============================================================================
#  SWEEP SUMMARY
# =============================================================================
if [[ $DRY_RUN -eq 0 ]]; then
    SUMMARY="${SWEEP_ROOT}/sweep_summary.md"
    {
        echo "# Sweep Summary — ${TIMESTAMP}"
        echo ""
        echo "Generated by \`tools/run_sweep.sh\` on $(date)."
        echo ""
        echo "## Configuration"
        echo ""
        echo "| Parameter | Value |"
        echo "|-----------|-------|"
        echo "| Base ini | \`${BASE_INI}\` |"
        echo "| Max generations | ${MAX_GENERATIONS} |"
        echo "| Seeds | ${SEEDS[*]} |"
        echo "| saveVideo | $(get_kv "$BASE_INI" "saveVideo" "false") |"
        echo ""
        echo "## B1 — Environment alone"
        echo ""
        echo "| Folder | Challenge | Description |"
        echo "|--------|-----------|-------------|"
        for ch in "${B1_CHALLENGES[@]}"; do
            echo "| ch$(printf '%02d' "$ch")_$(ch_name "$ch") | ${ch} | $(ch_name "$ch") arena |"
        done
        echo ""
        echo "## B2 — Mutation rate × environment"
        echo ""
        echo "| Folder | Mutation rate | Challenge |"
        echo "|--------|--------------|-----------|"
        for mut in "${B2_MUTATION_RATES[@]}"; do
            mut_tag="${mut//./_}"
            for ch in "${B2_CHALLENGES[@]}"; do
                echo "| ch$(printf '%02d' "$ch")_$(ch_name "$ch")_mut${mut_tag} | ${mut} | $(ch_name "$ch") |"
            done
        done
        echo ""
        echo "## B3 — Predator fraction × environment"
        echo ""
        echo "| Folder | Predator fraction | Challenge |"
        echo "|--------|------------------|-----------|"
        for pf in "${B3_PRED_FRACTIONS[@]}"; do
            pf_tag="${pf//./_}"
            for ch in "${B3_CHALLENGES[@]}"; do
                echo "| ch$(printf '%02d' "$ch")_$(ch_name "$ch")_pf${pf_tag} | ${pf} | $(ch_name "$ch") |"
            done
        done
        echo ""
        echo "## Output structure per run"
        echo ""
        echo "\`\`\`"
        echo "<group>/<run_label>/seed_<N>/"
        echo "  logs/"
        echo "    epoch-log.txt        population counts + fitness per generation"
        echo "  videos/                simulation frames / mp4 (if saveVideo = true)"
        echo "  analysis/"
        echo "    analysis.png         composite 5-panel figure"
        echo "    analysis_report.md   OSC1 / OSC2 / RED-QUEEN verdicts"
        echo "    analysis_panels/     per-panel figures (populations, autocorr, ...)"
        echo "    analyse.stdout       stdout/stderr from analyse.py"
        echo "  run.ini                exact ini used — re-run with: biosim4 run.ini"
        echo "  simulator.stdout       simulator stdout/stderr"
        echo "\`\`\`"
    } > "$SUMMARY"
    echo
    echo "Wrote summary: ${SUMMARY}"
fi

# =============================================================================
#  ZIP ARCHIVE
# =============================================================================
if [[ $DRY_RUN -eq 0 ]]; then
    ZIP_NAME="${SWEEP_DIR}/sweep_${TIMESTAMP}.zip"
    echo "Creating archive: ${ZIP_NAME} ..."
    zip -r "$ZIP_NAME" "$SWEEP_ROOT" -x "*.DS_Store" -x "__MACOSX/*" \
        > /dev/null
    SIZE=$(du -sh "$ZIP_NAME" | cut -f1)
    echo "Archive ready: ${ZIP_NAME}  (${SIZE})"
fi

# =============================================================================
#  CLEANUP
# =============================================================================
if [[ $DRY_RUN -eq 0 ]]; then
    rm -rf "${TMP_DIR:?}"/*
    echo "Cleaned up: ${TMP_DIR}/"
fi

echo
echo "Done."
echo "  Results : ${SWEEP_ROOT}/"
if [[ $DRY_RUN -eq 0 ]]; then
    echo "  Archive : ${ZIP_NAME}"
fi
