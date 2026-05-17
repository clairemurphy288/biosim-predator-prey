#!/usr/bin/env bash
# tools/run_sweep.sh
# Complete parameter sweep — Bia (B1-B3), Yannic (Y1-Y3), Claire (C1-C4).
#
# Output layout:
#   Output/Sweep/run_<timestamp>/
#     Bia/
#       B1_environment/<run>/seed_<N>/{logs,videos,analysis,run.ini,simulator.stdout}
#       B2_mutation_x_env/...
#       B3_fraction_x_env/...
#     Yannic/
#       Y1_speed_grid/...
#       Y2_speed_x_env/...
#       Y3_speed_x_mutation/...
#     Claire/
#       C1_starvation/...
#       C2_starvation_x_env/...
#       C3_starvation_x_mutation/...
#       C4_regeneration/...          (WIP — set C4_STARVATION from C1 results first)
#     sweep_summary.md
#   Output/Sweep/sweep_<timestamp>.zip
#
# Usage:
#   ./tools/run_sweep.sh                    # run all groups
#   ./tools/run_sweep.sh --dry-run          # preview only, no files created
#   RUN_GROUPS="B1 B2 B3" ./tools/run_sweep.sh # Bia's experiments only
#   RUN_GROUPS="Y1 Y2 Y3" ./tools/run_sweep.sh # Yannic's experiments only
#   RUN_GROUPS="C1 C2 C3" ./tools/run_sweep.sh # Claire's (skip C4 until it's ready)
#   RUN_GROUPS="B1 Y1 C1" ./tools/run_sweep.sh # any combination

set -euo pipefail

# =============================================================================
#  EXPERIMENT MATRIX  ← edit this block
# =============================================================================

# Which groups to run.  Override from the environment or edit here.
#   "all"          → every group below
#   "Bia"          → B1 B2 B3
#   "Yannic"       → Y1 Y2 Y3
#   "Claire"       → C1 C2 C3 C4
#   "B1 Y2 C3"     → any explicit list
RUN_GROUPS="${RUN_GROUPS:-B1}"

SEEDS=(1 2 3)

# ── B: Environment experiments (Bia) ─────────────────────────────────────────
B1_CHALLENGES=(20 0 5 11)          # open, circle, corner, wall

B2_MUTATION_RATES=(0.0001 0.001 0.01)
B2_CHALLENGES=(20 0)               # open, circle

B3_PRED_FRACTIONS=(0.25 0.50 0.75)
B3_CHALLENGES=(20 0)               # open, circle

# ── Y: Speed experiments (Yannic) ────────────────────────────────────────────
# Y1: full predator × prey period grid, open arena (challenge=20)
Y1_PRED_PERIODS=(1 1 1 2 2 2 3 3 3)
Y1_PREY_PERIODS=(1 2 3 1 2 3 1 2 3)
Y1_CHALLENGE=20

# Y2/Y3: three representative combos — "label predPeriod preyPeriod"
#   lower period = faster (acts more often)
Y_SPEED_COMBOS=("pred_fast 1 2" "balanced 1 1" "prey_fast 2 1")
Y2_CHALLENGES=(20 0)               # open, circle
Y3_MUTATION_RATES=(0.0001 0.001 0.01)
Y3_CHALLENGE=20

# ── C: Starvation & regeneration experiments (Claire) ────────────────────────
C1_STARVATION=(0 60 120 220 400)   # 0 = starvation disabled
C1_CHALLENGE=20

C2_STARVATION=(60 120 220)
C2_CHALLENGES=(20 0)

C3_STARVATION=(60 120 220)
C3_MUTATION_RATES=(0.0001 0.001 0.01)
C3_CHALLENGE=20

# C4 — Regeneration schemes (WIP — update C4_STARVATION from C1 results)
# Four schemes tested at one fixed starvation level:
#   fixed        predatorRatioMode=0: fixed fraction every generation
#   proportional predatorRatioMode=1: fitness-proportional from gen 0
#   switch_200   mode=0 for gens 0-199, switches to mode=1 at gen 200
#   harsh_prey   proportional + preyTopFractionToReproduce=0.30 (baseline=0.70)
C4_STARVATION=120                  # ← update this from C1 before running C4
C4_CHALLENGE=20

# ── shared ────────────────────────────────────────────────────────────────────
MAX_GENERATIONS=100

# ── run mode ──────────────────────────────────────────────────────────────────
# HEADLESS=true  → no GUI, no video (safe for background/server runs)
# HEADLESS=false → shows SFML window; SAVE_VIDEO controls video capture
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

set_kv() {
    local file="$1" key="$2" value="$3"
    if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
        sed -i.bak -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$file"
        rm -f "${file}.bak"
    else
        printf '\n%s = %s\n' "$key" "$value" >> "$file"
    fi
}

ch_name() {
    case "$1" in
        20) echo "open"   ;;
         0) echo "circle" ;;
         5) echo "corner" ;;
        11) echo "wall"   ;;
         *) echo "ch${1}" ;;
    esac
}

# Returns 0 (true) if the given group should run.
should_run() {
    local g="$1"
    [[ "$RUN_GROUPS" == "all" ]] && return 0
    [[ "$RUN_GROUPS" == *"Bia"*    && "$g" =~ ^B ]] && return 0
    [[ "$RUN_GROUPS" == *"Yannic"* && "$g" =~ ^Y ]] && return 0
    [[ "$RUN_GROUPS" == *"Claire"* && "$g" =~ ^C ]] && return 0
    [[ " $RUN_GROUPS " == *" $g "* ]] && return 0
    return 1
}

# run_one <group_dir> <run_label> <seed> [key value ...]
run_one() {
    local group_dir="$1" run_label="$2" seed="$3"
    shift 3

    local run_dir="${group_dir}/${run_label}/seed_${seed}"
    local log_dir="${run_dir}/logs"
    local vid_dir="${run_dir}/videos"
    local ana_dir="${run_dir}/analysis"
    local ini="${TMP_DIR}/${run_label}_seed${seed}.ini"

    echo "  seed=${seed}  →  ${run_dir}"
    [[ $DRY_RUN -eq 1 ]] && return

    mkdir -p "$log_dir" "$vid_dir" "$ana_dir"

    cp "$BASE_INI" "$ini"
    set_kv "$ini" "predatorPreyEnabled"  "true"
    set_kv "$ini" "maxGenerations"       "$MAX_GENERATIONS"
    set_kv "$ini" "deterministic"        "true"
    set_kv "$ini" "RNGSeed"              "$seed"
    set_kv "$ini" "updateGraphLog"       "false"
    set_kv "$ini" "logDir"               "$log_dir"
    set_kv "$ini" "imageDir"             "$vid_dir"

    if [[ "$HEADLESS" == "true" ]]; then
        set_kv "$ini" "saveVideo" "false"
    else
        set_kv "$ini" "saveVideo" "$SAVE_VIDEO"
    fi

    while (( $# >= 2 )); do
        set_kv "$ini" "$1" "$2"
        shift 2
    done

    cp "$ini" "${run_dir}/run.ini"

    local headless_flag=""
    [[ "$HEADLESS" == "true" ]] && headless_flag="--headless"
    # shellcheck disable=SC2086
    "$BIO" "$ini" $headless_flag > "${run_dir}/simulator.stdout" 2>&1 || {
        echo "    ! simulator failed — see ${run_dir}/simulator.stdout"
        return
    }

    if [[ ! -f "${log_dir}/epoch-log.txt" ]]; then
        echo "    ! no epoch log produced; skipping analysis"
        return
    fi

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
#  COUNT RUNS
# =============================================================================
b1_n=$(( ${#B1_CHALLENGES[@]} * ${#SEEDS[@]} ))
b2_n=$(( ${#B2_MUTATION_RATES[@]} * ${#B2_CHALLENGES[@]} * ${#SEEDS[@]} ))
b3_n=$(( ${#B3_PRED_FRACTIONS[@]} * ${#B3_CHALLENGES[@]} * ${#SEEDS[@]} ))
y1_n=$(( ${#Y1_PRED_PERIODS[@]} * ${#SEEDS[@]} ))
y2_n=$(( ${#Y_SPEED_COMBOS[@]} * ${#Y2_CHALLENGES[@]} * ${#SEEDS[@]} ))
y3_n=$(( ${#Y_SPEED_COMBOS[@]} * ${#Y3_MUTATION_RATES[@]} * ${#SEEDS[@]} ))
c1_n=$(( ${#C1_STARVATION[@]} * ${#SEEDS[@]} ))
c2_n=$(( ${#C2_STARVATION[@]} * ${#C2_CHALLENGES[@]} * ${#SEEDS[@]} ))
c3_n=$(( ${#C3_STARVATION[@]} * ${#C3_MUTATION_RATES[@]} * ${#SEEDS[@]} ))
c4_n=$(( 4 * ${#SEEDS[@]} ))
total_n=$(( b1_n + b2_n + b3_n + y1_n + y2_n + y3_n + c1_n + c2_n + c3_n + c4_n ))

echo "======================================================================"
echo "  biosim4 parameter sweep  —  ${TIMESTAMP}"
echo "  Output root : ${SWEEP_ROOT}"
if [[ "$HEADLESS" == "true" ]]; then
    echo "  mode        : headless (saveVideo forced off)"
else
    echo "  mode        : windowed (saveVideo = ${SAVE_VIDEO})"
fi
echo "  Groups      : ${RUN_GROUPS}"
echo "  ── Bia ──────────────────────────────────────"
should_run B1 && echo "  B1 environment            : ${b1_n} runs" || echo "  B1 environment            : skipped"
should_run B2 && echo "  B2 mutation × env         : ${b2_n} runs" || echo "  B2 mutation × env         : skipped"
should_run B3 && echo "  B3 fraction × env         : ${b3_n} runs" || echo "  B3 fraction × env         : skipped"
echo "  ── Yannic ───────────────────────────────────"
should_run Y1 && echo "  Y1 speed grid             : ${y1_n} runs" || echo "  Y1 speed grid             : skipped"
should_run Y2 && echo "  Y2 speed × env            : ${y2_n} runs" || echo "  Y2 speed × env            : skipped"
should_run Y3 && echo "  Y3 speed × mutation       : ${y3_n} runs" || echo "  Y3 speed × mutation       : skipped"
echo "  ── Claire ───────────────────────────────────"
should_run C1 && echo "  C1 starvation             : ${c1_n} runs" || echo "  C1 starvation             : skipped"
should_run C2 && echo "  C2 starvation × env       : ${c2_n} runs" || echo "  C2 starvation × env       : skipped"
should_run C3 && echo "  C3 starvation × mutation  : ${c3_n} runs" || echo "  C3 starvation × mutation  : skipped"
should_run C4 && echo "  C4 regeneration (WIP)     : ${c4_n} runs" || echo "  C4 regeneration (WIP)     : skipped"
echo "  ─────────────────────────────────────────────"
echo "  Total (selected groups)   : ${total_n} runs"
echo "======================================================================"
echo

[[ $DRY_RUN -eq 1 ]] && echo "[DRY RUN — simulator will not be called]" && echo

[[ $DRY_RUN -eq 0 ]] && mkdir -p "$SWEEP_ROOT"

# =============================================================================
#  B1 — ENVIRONMENT ALONE  (Bia)
# =============================================================================
if should_run B1; then
    echo "── B1  Environment alone (Bia) ────────────────────────────────────────"
    B1_DIR="${SWEEP_ROOT}/Bia/B1_environment"
    [[ $DRY_RUN -eq 0 ]] && mkdir -p "$B1_DIR"
    i=0
    for ch in "${B1_CHALLENGES[@]}"; do
        label="ch$(printf '%02d' "$ch")_$(ch_name "$ch")"
        for seed in "${SEEDS[@]}"; do
            i=$(( i + 1 ))
            echo "[B1 ${i}/${b1_n}]  ${label}"
            run_one "$B1_DIR" "$label" "$seed" \
                "challenge" "$ch"
        done
    done
    echo
fi

# =============================================================================
#  B2 — MUTATION RATE × ENVIRONMENT  (Bia)
# =============================================================================
if should_run B2; then
    echo "── B2  Mutation rate × environment (Bia) ──────────────────────────────"
    B2_DIR="${SWEEP_ROOT}/Bia/B2_mutation_x_env"
    [[ $DRY_RUN -eq 0 ]] && mkdir -p "$B2_DIR"
    i=0
    for mut in "${B2_MUTATION_RATES[@]}"; do
        mut_tag="${mut//./_}"
        for ch in "${B2_CHALLENGES[@]}"; do
            label="ch$(printf '%02d' "$ch")_$(ch_name "$ch")_mut${mut_tag}"
            for seed in "${SEEDS[@]}"; do
                i=$(( i + 1 ))
                echo "[B2 ${i}/${b2_n}]  ${label}"
                run_one "$B2_DIR" "$label" "$seed" \
                    "challenge"         "$ch" \
                    "pointMutationRate" "$mut"
            done
        done
    done
    echo
fi

# =============================================================================
#  B3 — PREDATOR FRACTION × ENVIRONMENT  (Bia)
# =============================================================================
if should_run B3; then
    echo "── B3  Predator fraction × environment (Bia) ──────────────────────────"
    B3_DIR="${SWEEP_ROOT}/Bia/B3_fraction_x_env"
    [[ $DRY_RUN -eq 0 ]] && mkdir -p "$B3_DIR"
    i=0
    for pf in "${B3_PRED_FRACTIONS[@]}"; do
        pf_tag="${pf//./_}"
        for ch in "${B3_CHALLENGES[@]}"; do
            label="ch$(printf '%02d' "$ch")_$(ch_name "$ch")_pf${pf_tag}"
            for seed in "${SEEDS[@]}"; do
                i=$(( i + 1 ))
                echo "[B3 ${i}/${b3_n}]  ${label}"
                run_one "$B3_DIR" "$label" "$seed" \
                    "challenge"        "$ch" \
                    "predatorFraction" "$pf"
            done
        done
    done
    echo
fi

# =============================================================================
#  Y1 — FULL SPEED GRID  (Yannic)
# =============================================================================
if should_run Y1; then
    echo "── Y1  Full speed grid — open arena (Yannic) ──────────────────────────"
    Y1_DIR="${SWEEP_ROOT}/Yannic/Y1_speed_grid"
    [[ $DRY_RUN -eq 0 ]] && mkdir -p "$Y1_DIR"
    i=0
    for idx in "${!Y1_PRED_PERIODS[@]}"; do
        ps="${Y1_PRED_PERIODS[$idx]}"
        ys="${Y1_PREY_PERIODS[$idx]}"
        label="ps${ps}_ys${ys}"
        for seed in "${SEEDS[@]}"; do
            i=$(( i + 1 ))
            echo "[Y1 ${i}/${y1_n}]  ${label}"
            run_one "$Y1_DIR" "$label" "$seed" \
                "challenge"           "$Y1_CHALLENGE" \
                "predatorActionPeriod" "$ps" \
                "preyActionPeriod"     "$ys"
        done
    done
    echo
fi

# =============================================================================
#  Y2 — SPEED × ENVIRONMENT  (Yannic)
# =============================================================================
if should_run Y2; then
    echo "── Y2  Speed × environment (Yannic) ───────────────────────────────────"
    Y2_DIR="${SWEEP_ROOT}/Yannic/Y2_speed_x_env"
    [[ $DRY_RUN -eq 0 ]] && mkdir -p "$Y2_DIR"
    i=0
    for combo in "${Y_SPEED_COMBOS[@]}"; do
        read -r clabel ps ys <<< "$combo"
        for ch in "${Y2_CHALLENGES[@]}"; do
            label="ch$(printf '%02d' "$ch")_$(ch_name "$ch")_${clabel}"
            for seed in "${SEEDS[@]}"; do
                i=$(( i + 1 ))
                echo "[Y2 ${i}/${y2_n}]  ${label}"
                run_one "$Y2_DIR" "$label" "$seed" \
                    "challenge"            "$ch" \
                    "predatorActionPeriod" "$ps" \
                    "preyActionPeriod"     "$ys"
            done
        done
    done
    echo
fi

# =============================================================================
#  Y3 — SPEED × MUTATION RATE  (Yannic)
# =============================================================================
if should_run Y3; then
    echo "── Y3  Speed × mutation rate (Yannic) ─────────────────────────────────"
    Y3_DIR="${SWEEP_ROOT}/Yannic/Y3_speed_x_mutation"
    [[ $DRY_RUN -eq 0 ]] && mkdir -p "$Y3_DIR"
    i=0
    for combo in "${Y_SPEED_COMBOS[@]}"; do
        read -r clabel ps ys <<< "$combo"
        for mut in "${Y3_MUTATION_RATES[@]}"; do
            mut_tag="${mut//./_}"
            label="${clabel}_mut${mut_tag}"
            for seed in "${SEEDS[@]}"; do
                i=$(( i + 1 ))
                echo "[Y3 ${i}/${y3_n}]  ${label}"
                run_one "$Y3_DIR" "$label" "$seed" \
                    "challenge"            "$Y3_CHALLENGE" \
                    "predatorActionPeriod" "$ps" \
                    "preyActionPeriod"     "$ys" \
                    "pointMutationRate"    "$mut"
            done
        done
    done
    echo
fi

# =============================================================================
#  C1 — STARVATION ALONE  (Claire)
# =============================================================================
if should_run C1; then
    echo "── C1  Starvation alone (Claire) ──────────────────────────────────────"
    C1_DIR="${SWEEP_ROOT}/Claire/C1_starvation"
    [[ $DRY_RUN -eq 0 ]] && mkdir -p "$C1_DIR"
    i=0
    for st in "${C1_STARVATION[@]}"; do
        label="st${st}"
        for seed in "${SEEDS[@]}"; do
            i=$(( i + 1 ))
            echo "[C1 ${i}/${c1_n}]  ${label}"
            run_one "$C1_DIR" "$label" "$seed" \
                "challenge"                "$C1_CHALLENGE" \
                "predatorStarvationSteps"  "$st"
        done
    done
    echo
fi

# =============================================================================
#  C2 — STARVATION × ENVIRONMENT  (Claire)
# =============================================================================
if should_run C2; then
    echo "── C2  Starvation × environment (Claire) ──────────────────────────────"
    C2_DIR="${SWEEP_ROOT}/Claire/C2_starvation_x_env"
    [[ $DRY_RUN -eq 0 ]] && mkdir -p "$C2_DIR"
    i=0
    for st in "${C2_STARVATION[@]}"; do
        for ch in "${C2_CHALLENGES[@]}"; do
            label="ch$(printf '%02d' "$ch")_$(ch_name "$ch")_st${st}"
            for seed in "${SEEDS[@]}"; do
                i=$(( i + 1 ))
                echo "[C2 ${i}/${c2_n}]  ${label}"
                run_one "$C2_DIR" "$label" "$seed" \
                    "challenge"               "$ch" \
                    "predatorStarvationSteps" "$st"
            done
        done
    done
    echo
fi

# =============================================================================
#  C3 — STARVATION × MUTATION RATE  (Claire)
# =============================================================================
if should_run C3; then
    echo "── C3  Starvation × mutation rate (Claire) ────────────────────────────"
    C3_DIR="${SWEEP_ROOT}/Claire/C3_starvation_x_mutation"
    [[ $DRY_RUN -eq 0 ]] && mkdir -p "$C3_DIR"
    i=0
    for st in "${C3_STARVATION[@]}"; do
        for mut in "${C3_MUTATION_RATES[@]}"; do
            mut_tag="${mut//./_}"
            label="st${st}_mut${mut_tag}"
            for seed in "${SEEDS[@]}"; do
                i=$(( i + 1 ))
                echo "[C3 ${i}/${c3_n}]  ${label}"
                run_one "$C3_DIR" "$label" "$seed" \
                    "challenge"               "$C3_CHALLENGE" \
                    "predatorStarvationSteps" "$st" \
                    "pointMutationRate"       "$mut"
            done
        done
    done
    echo
fi

# =============================================================================
#  C4 — REGENERATION SCHEMES  (Claire — WIP)
#  Update C4_STARVATION from C1 results before running this group.
# =============================================================================
if should_run C4; then
    echo "── C4  Regeneration schemes (Claire — WIP) ────────────────────────────"
    echo "    Using starvation = ${C4_STARVATION}  (set C4_STARVATION from C1 results)"
    C4_DIR="${SWEEP_ROOT}/Claire/C4_regeneration"
    [[ $DRY_RUN -eq 0 ]] && mkdir -p "$C4_DIR"
    i=0

    for seed in "${SEEDS[@]}"; do
        i=$(( i + 1 ))
        echo "[C4 ${i}/${c4_n}]  fixed_ratio"
        run_one "$C4_DIR" "fixed_ratio" "$seed" \
            "challenge"               "$C4_CHALLENGE" \
            "predatorStarvationSteps" "$C4_STARVATION" \
            "predatorRatioMode"       "0"
    done

    for seed in "${SEEDS[@]}"; do
        i=$(( i + 1 ))
        echo "[C4 ${i}/${c4_n}]  proportional"
        run_one "$C4_DIR" "proportional" "$seed" \
            "challenge"               "$C4_CHALLENGE" \
            "predatorStarvationSteps" "$C4_STARVATION" \
            "predatorRatioMode"       "1"
    done

    for seed in "${SEEDS[@]}"; do
        i=$(( i + 1 ))
        echo "[C4 ${i}/${c4_n}]  switch_at_200"
        run_one "$C4_DIR" "switch_at_200" "$seed" \
            "challenge"                  "$C4_CHALLENGE" \
            "predatorStarvationSteps"    "$C4_STARVATION" \
            "predatorRatioMode"          "0" \
            "predatorRatioMode@200"      "1"
    done

    for seed in "${SEEDS[@]}"; do
        i=$(( i + 1 ))
        echo "[C4 ${i}/${c4_n}]  harsh_prey"
        run_one "$C4_DIR" "harsh_prey" "$seed" \
            "challenge"                  "$C4_CHALLENGE" \
            "predatorStarvationSteps"    "$C4_STARVATION" \
            "predatorRatioMode"          "1" \
            "preyTopFractionToReproduce" "0.30"
    done
    echo
fi

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
        echo "| Groups run | ${RUN_GROUPS} |"
        echo "| Headless | ${HEADLESS} |"
        echo ""
        echo "## Bia — Environment experiments"
        echo ""
        echo "### B1 Environment alone"
        echo "| Folder | Challenge |"
        echo "|--------|-----------|"
        for ch in "${B1_CHALLENGES[@]}"; do
            echo "| ch$(printf '%02d' "$ch")_$(ch_name "$ch") | ${ch} ($(ch_name "$ch")) |"
        done
        echo ""
        echo "### B2 Mutation rate × environment"
        echo "| Folder | Mutation rate | Challenge |"
        echo "|--------|--------------|-----------|"
        for mut in "${B2_MUTATION_RATES[@]}"; do
            for ch in "${B2_CHALLENGES[@]}"; do
                echo "| ch$(printf '%02d' "$ch")_$(ch_name "$ch")_mut${mut//./_} | ${mut} | $(ch_name "$ch") |"
            done
        done
        echo ""
        echo "### B3 Predator fraction × environment"
        echo "| Folder | Predator fraction | Challenge |"
        echo "|--------|------------------|-----------|"
        for pf in "${B3_PRED_FRACTIONS[@]}"; do
            for ch in "${B3_CHALLENGES[@]}"; do
                echo "| ch$(printf '%02d' "$ch")_$(ch_name "$ch")_pf${pf//./_} | ${pf} | $(ch_name "$ch") |"
            done
        done
        echo ""
        echo "## Yannic — Speed experiments"
        echo ""
        echo "### Y1 Full speed grid (challenge=${Y1_CHALLENGE})"
        echo "| Folder | predatorActionPeriod | preyActionPeriod |"
        echo "|--------|---------------------|-----------------|"
        for idx in "${!Y1_PRED_PERIODS[@]}"; do
            echo "| ps${Y1_PRED_PERIODS[$idx]}_ys${Y1_PREY_PERIODS[$idx]} | ${Y1_PRED_PERIODS[$idx]} | ${Y1_PREY_PERIODS[$idx]} |"
        done
        echo ""
        echo "### Y2 Speed × environment"
        echo "| Folder | Speed combo | Challenge |"
        echo "|--------|------------|-----------|"
        for combo in "${Y_SPEED_COMBOS[@]}"; do
            read -r clabel ps ys <<< "$combo"
            for ch in "${Y2_CHALLENGES[@]}"; do
                echo "| ch$(printf '%02d' "$ch")_$(ch_name "$ch")_${clabel} | pred=${ps} prey=${ys} | $(ch_name "$ch") |"
            done
        done
        echo ""
        echo "### Y3 Speed × mutation rate (challenge=${Y3_CHALLENGE})"
        echo "| Folder | Speed combo | Mutation rate |"
        echo "|--------|------------|--------------|"
        for combo in "${Y_SPEED_COMBOS[@]}"; do
            read -r clabel ps ys <<< "$combo"
            for mut in "${Y3_MUTATION_RATES[@]}"; do
                echo "| ${clabel}_mut${mut//./_} | pred=${ps} prey=${ys} | ${mut} |"
            done
        done
        echo ""
        echo "## Claire — Starvation & regeneration experiments"
        echo ""
        echo "### C1 Starvation alone (challenge=${C1_CHALLENGE})"
        echo "| Folder | predatorStarvationSteps |"
        echo "|--------|------------------------|"
        for st in "${C1_STARVATION[@]}"; do
            echo "| st${st} | ${st}$([ "$st" -eq 0 ] && echo " (disabled)") |"
        done
        echo ""
        echo "### C2 Starvation × environment"
        echo "| Folder | Starvation | Challenge |"
        echo "|--------|-----------|-----------|"
        for st in "${C2_STARVATION[@]}"; do
            for ch in "${C2_CHALLENGES[@]}"; do
                echo "| ch$(printf '%02d' "$ch")_$(ch_name "$ch")_st${st} | ${st} | $(ch_name "$ch") |"
            done
        done
        echo ""
        echo "### C3 Starvation × mutation rate (challenge=${C3_CHALLENGE})"
        echo "| Folder | Starvation | Mutation rate |"
        echo "|--------|-----------|--------------|"
        for st in "${C3_STARVATION[@]}"; do
            for mut in "${C3_MUTATION_RATES[@]}"; do
                echo "| st${st}_mut${mut//./_} | ${st} | ${mut} |"
            done
        done
        echo ""
        echo "### C4 Regeneration schemes (WIP — starvation=${C4_STARVATION}, challenge=${C4_CHALLENGE})"
        echo "| Folder | predatorRatioMode | preyTopFractionToReproduce | Notes |"
        echo "|--------|------------------|---------------------------|-------|"
        echo "| fixed_ratio    | 0 | 0.70 (baseline) | fixed fraction every gen |"
        echo "| proportional   | 1 | 0.70 (baseline) | fitness-proportional from gen 0 |"
        echo "| switch_at_200  | 0→1 at gen 200 | 0.70 (baseline) | baseline then proportional |"
        echo "| harsh_prey     | 1 | 0.30 | proportional + strong prey selection |"
    } > "$SUMMARY"
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
