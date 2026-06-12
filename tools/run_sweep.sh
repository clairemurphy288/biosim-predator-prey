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
RUN_GROUPS="${RUN_GROUPS:-C4}"

SEEDS=(1 2 3)

# ── CTRL: Control runs (predatorPreyEnabled=false) ───────────────────────────
# These are the no-predation baselines required for causal interpretation.
# Run with predatorPreyEnabled=false so all three statistical tests (OSC1,
# OSC2, RED-QUEEN) should FAIL — confirming that any passing results in
# treatment groups are genuinely caused by predation and not an artefact.
#
# CTRL1: environment sweep (matches B1) — most important control
# CTRL2: starvation sweep disabled (predatorStarvationSteps=0, matches C1 baseline)
CTRL1_CHALLENGES=(20 0 5 11)   # same environments as B1
CTRL2_CHALLENGES=(20)          # open arena only for starvation control

# ── B: Environment experiments (Bia) ─────────────────────────────────────────
B1_CHALLENGES=(20 0 5 11)          # open, circle, corner, wall

B2_MUTATION_RATES=(0.0001 0.0005 0.001)
B2_CHALLENGES=(20 0)               # open, circle

B3_PRED_FRACTIONS=(0.1 0.2 0.33 0.50)
B3_CHALLENGES=(20 0)               # open, circle

# ── Y: Speed experiments (Yannic) ────────────────────────────────────────────
# Y1: full predator × prey period grid, open arena (challenge=20)
Y1_PRED_PERIODS=(1 1 1 2 2)
Y1_PREY_PERIODS=(1 2 3 3 1)
Y1_CHALLENGE=20

# Y2/Y3: four representative combos — "label predPeriod preyPeriod"
#   lower period = faster (acts more often)
Y_SPEED_COMBOS=("pred_very_fast 1 3" "pred_fast 1 2" "balanced 1 1" "pred_slow 2 1")
Y2_CHALLENGES=(20 0)               # open, circle
Y3_MUTATION_RATES=(0.0001 0.0005 0.001)
Y3_CHALLENGE=20

# ── C: Predator selection pressure experiments (Claire) ──────────────────────
# All four groups use challenge=20 (open arena) to isolate predator dynamics.
# C2-C4 use a fixed starvation of 120 (mid-range) — update from C1 results.
C_CHALLENGE=20
C_FIXED_STARVATION=220   # from C1 results: st=220 gives 3/3 RED-QUEEN, healthy coevolution

# C1: Starvation pressure sweep — how tight is the predator survival deadline?
#   0 = starvation off (predators only die from age)
#   Low values = strong pressure (rapid predator die-off if no kills)
#   High values = weak pressure (close to no-starvation baseline)
C1_STARVATION=(0 60 120 220 400)

# C2: Reproduction threshold sweep — how many kills must a predator make to breed?
#   0 = any predator can reproduce regardless of hunting success
#   Higher values = stronger selection for hunting competence
C2_MIN_CAPTURES=(0 1 2 3 5)

# C3: Neural network capacity sweep — does expressiveness limit predator evolution?
#   Small nets (2-3): may lack capacity to evolve hunt + navigate simultaneously
#   Larger nets (5-8): more representational power but slower to evolve
C3_MAX_NEURONS=(2 3 5 8)

# C4: Predator perception radius sweep — how far can predators sense prey?
#   This is a predator-specific advantage: larger radius makes prey detectable
#   from farther away, directly benefiting predator hunting without affecting prey.
#   Fixed starvation = C_FIXED_STARVATION, challenge = C_CHALLENGE.
C4_PERCEPTION_RADII=(3.0 6.0 9.0 12.0 16.0)

# ── shared ────────────────────────────────────────────────────────────────────
MAX_GENERATIONS=400

# ── run mode ──────────────────────────────────────────────────────────────────
# HEADLESS=true  → no SFML window (safe for background/server runs)
# HEADLESS=false → shows SFML window during simulation
# SAVE_VIDEO is independent of HEADLESS — video writing does not need the window.
HEADLESS=true
SAVE_VIDEO=true        # true = save .avi frames regardless of HEADLESS

# SAVE_NETS=true  → save one predator + one prey neural net snapshot every
#                   NETS_STRIDE generations, stored in images/ alongside frames.
#                   Enables the SENSOR USAGE panel in analyse.py.
# SAVE_NETS=false → skip net snapshots (faster, less disk)
SAVE_NETS=true
NETS_STRIDE=10         # save a net snapshot every N generations

# BURN_IN: number of generations to skip at the start of each run when
#   computing statistical tests (OSC1, OSC2, RED-QUEEN) and plotting.
#   Early generations are dominated by random/bootstrap behaviour before
#   meaningful evolutionary dynamics emerge — excluding them avoids noise
#   contaminating the signal.
#   Set to 0 to analyse all generations.
#   Typical values: 50–100 (about 10–25% of a 400-gen run)
BURN_IN=50

# CHECKPOINTS: run the full statistical analysis at each of these generation
#   cutoffs in addition to the full run. Useful for seeing whether tests pass
#   before a certain point (e.g. does OSC2 pass at gen 100 but fail by gen 400?).
#   Set to an empty string to skip checkpoint analysis.
CHECKPOINTS="100 200 300 400"

# OSC2_ALPHA: p-value threshold for the OSC2 phase-lag test.
#   0.05 = strict (standard significance)
#   0.10 = relaxed (easier to pass, recommended for exploratory sweeps)
OSC2_ALPHA=0.1

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
    [[ "$RUN_GROUPS" == *"Bia"*    && "$g" =~ ^B    ]] && return 0
    [[ "$RUN_GROUPS" == *"Yannic"* && "$g" =~ ^Y   ]] && return 0
    [[ "$RUN_GROUPS" == *"Claire"* && "$g" =~ ^C   ]] && return 0
    [[ "$RUN_GROUPS" == *"Control"* && "$g" =~ ^CTRL ]] && return 0
    [[ " $RUN_GROUPS " == *" $g "* ]] && return 0
    return 1
}

# run_one <group_dir> <run_label> <seed> [key value ...]
run_one() {
    local group_dir="$1" run_label="$2" seed="$3"
    shift 3

    local run_dir="${group_dir}/${run_label}/seed_${seed}"
    local log_dir="${run_dir}/logs"
    local images_dir="${run_dir}/images"   # video frames + neural net snapshots
    local ana_dir="${run_dir}/analysis"
    local ini="${TMP_DIR}/${run_label}_seed${seed}.ini"

    echo "  seed=${seed}  →  ${run_dir}"
    [[ $DRY_RUN -eq 1 ]] && return

    mkdir -p "$log_dir" "$images_dir" "$ana_dir"

    cp "$BASE_INI" "$ini"
    set_kv "$ini" "predatorPreyEnabled"  "true"
    set_kv "$ini" "maxGenerations"       "$MAX_GENERATIONS"
    set_kv "$ini" "deterministic"        "true"
    set_kv "$ini" "RNGSeed"              "$seed"
    set_kv "$ini" "updateGraphLog"       "false"
    set_kv "$ini" "logDir"    "$log_dir"
    set_kv "$ini" "imageDir"  "$images_dir"

    set_kv "$ini" "saveVideo" "$SAVE_VIDEO"

    if [[ "$SAVE_NETS" == "true" ]]; then
        set_kv "$ini" "autoSavePredatorNetsPerGeneration" "1"
        set_kv "$ini" "autoSavePreyNetsPerGeneration"     "1"
        set_kv "$ini" "autoSaveNetStride"                 "$NETS_STRIDE"
        # autoSaveNetEpochs gates saving: 0 disables it entirely,
        # and saving also stops once generation >= this value.
        # Set it above maxGenerations so nets are saved for the full run.
        set_kv "$ini" "autoSaveNetEpochs" "$(( MAX_GENERATIONS + 1 ))"
    else
        set_kv "$ini" "autoSavePredatorNetsPerGeneration" "0"
        set_kv "$ini" "autoSavePreyNetsPerGeneration"     "0"
        set_kv "$ini" "autoSaveNetEpochs"                 "0"
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
        echo "    ! simulator exited non-zero (early termination?) — checking for log"
    }

    if [[ ! -f "${log_dir}/epoch-log.txt" ]]; then
        echo "    ! no epoch log produced; skipping analysis"
        return
    fi

    local ckpt_args=""
    [[ -n "$CHECKPOINTS" ]] && ckpt_args="--checkpoints ${CHECKPOINTS}"

    # shellcheck disable=SC2086
    "$PYTHON" tools/analyse.py \
        --log        "${log_dir}/epoch-log.txt" \
        --nets       "${images_dir}" \
        --out        "${ana_dir}/analysis.png" \
        --report     "${ana_dir}/analysis_report.md" \
        --burn-in    "${BURN_IN}" \
        --osc2-alpha "${OSC2_ALPHA}" \
        --split-figures \
        --title      "${run_label} | seed ${seed}" \
        $ckpt_args \
        > "${ana_dir}/analyse.stdout" 2>&1 || {
        echo "    ! analysis failed — see ${ana_dir}/analyse.stdout"
    }
}

# =============================================================================
#  COUNT RUNS
# =============================================================================
ctrl1_n=$(( ${#CTRL1_CHALLENGES[@]} * ${#SEEDS[@]} ))
ctrl2_n=$(( ${#CTRL2_CHALLENGES[@]} * ${#SEEDS[@]} ))
b1_n=$(( ${#B1_CHALLENGES[@]} * ${#SEEDS[@]} ))
b2_n=$(( ${#B2_MUTATION_RATES[@]} * ${#B2_CHALLENGES[@]} * ${#SEEDS[@]} ))
b3_n=$(( ${#B3_PRED_FRACTIONS[@]} * ${#B3_CHALLENGES[@]} * ${#SEEDS[@]} ))
y1_n=$(( ${#Y1_PRED_PERIODS[@]} * ${#SEEDS[@]} ))
y2_n=$(( ${#Y_SPEED_COMBOS[@]} * ${#Y2_CHALLENGES[@]} * ${#SEEDS[@]} ))
y3_n=$(( ${#Y_SPEED_COMBOS[@]} * ${#Y3_MUTATION_RATES[@]} * ${#SEEDS[@]} ))
c1_n=$(( ${#C1_STARVATION[@]}    * ${#SEEDS[@]} ))
c2_n=$(( ${#C2_MIN_CAPTURES[@]}  * ${#SEEDS[@]} ))
c3_n=$(( ${#C3_MAX_NEURONS[@]}   * ${#SEEDS[@]} ))
c4_n=$(( ${#C4_PERCEPTION_RADII[@]} * ${#SEEDS[@]} ))
total_n=$(( ctrl1_n + ctrl2_n + b1_n + b2_n + b3_n + y1_n + y2_n + y3_n + c1_n + c2_n + c3_n + c4_n ))

echo "======================================================================"
echo "  biosim4 parameter sweep  —  ${TIMESTAMP}"
echo "  Output root : ${SWEEP_ROOT}"
if [[ "$HEADLESS" == "true" ]]; then
    echo "  mode        : headless (saveVideo = ${SAVE_VIDEO})"
else
    echo "  mode        : windowed (saveVideo = ${SAVE_VIDEO})"
fi
if [[ "$SAVE_NETS" == "true" ]]; then
    echo "  nets        : enabled (1 pred + 1 prey snapshot every ${NETS_STRIDE} gens)"
else
    echo "  nets        : disabled"
fi
echo "  Groups      : ${RUN_GROUPS}"
echo "  ── Control (predatorPreyEnabled=false) ──────"
should_run CTRL1 && echo "  CTRL1 env (no predation)  : ${ctrl1_n} runs" || echo "  CTRL1 env (no predation)  : skipped"
should_run CTRL2 && echo "  CTRL2 starv (no predation): ${ctrl2_n} runs" || echo "  CTRL2 starv (no predation): skipped"
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
should_run C2 && echo "  C2 min captures           : ${c2_n} runs" || echo "  C2 min captures           : skipped"
should_run C3 && echo "  C3 max neurons            : ${c3_n} runs" || echo "  C3 max neurons            : skipped"
should_run C4 && echo "  C4 perception radius      : ${c4_n} runs" || echo "  C4 perception radius      : skipped"
echo "  ─────────────────────────────────────────────"
echo "  Total (selected groups)   : ${total_n} runs"
echo "======================================================================"
echo

[[ $DRY_RUN -eq 1 ]] && echo "[DRY RUN — simulator will not be called]" && echo

[[ $DRY_RUN -eq 0 ]] && mkdir -p "$SWEEP_ROOT"

# =============================================================================
#  CTRL1 — ENVIRONMENT, NO PREDATION  (control)
#  Same challenge sweep as B1 but predatorPreyEnabled=false.
#  All three statistical tests should FAIL here — confirms any passing results
#  in treatment groups are caused by predation, not an artefact.
# =============================================================================
if should_run CTRL1; then
    echo "── CTRL1  Environment, no predation (control) ─────────────────────────"
    CTRL1_DIR="${SWEEP_ROOT}/Control/CTRL1_env_no_predation"
    [[ $DRY_RUN -eq 0 ]] && mkdir -p "$CTRL1_DIR"
    i=0
    for ch in "${CTRL1_CHALLENGES[@]}"; do
        label="ch$(printf '%02d' "$ch")_$(ch_name "$ch")_nopred"
        for seed in "${SEEDS[@]}"; do
            i=$(( i + 1 ))
            echo "[CTRL1 ${i}/${ctrl1_n}]  ${label}"
            run_one "$CTRL1_DIR" "$label" "$seed" \
                "predatorPreyEnabled" "false" \
                "challenge"           "$ch"
        done
    done
    echo
fi

# =============================================================================
#  CTRL2 — OPEN ARENA, NO PREDATION  (control)
#  Baseline with no predation and no starvation in the open arena.
#  Isolates pure evolutionary learning from predation effects.
# =============================================================================
if should_run CTRL2; then
    echo "── CTRL2  Open arena, no predation (control) ──────────────────────────"
    CTRL2_DIR="${SWEEP_ROOT}/Control/CTRL2_open_no_predation"
    [[ $DRY_RUN -eq 0 ]] && mkdir -p "$CTRL2_DIR"
    i=0
    for ch in "${CTRL2_CHALLENGES[@]}"; do
        label="ch$(printf '%02d' "$ch")_$(ch_name "$ch")_nopred"
        for seed in "${SEEDS[@]}"; do
            i=$(( i + 1 ))
            echo "[CTRL2 ${i}/${ctrl2_n}]  ${label}"
            run_one "$CTRL2_DIR" "$label" "$seed" \
                "predatorPreyEnabled"     "false" \
                "challenge"               "$ch" \
                "predatorStarvationSteps" "0"
        done
    done
    echo
fi

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
#  C1 — STARVATION PRESSURE SWEEP  (Claire)
#  How tight is the predator survival deadline?
#  Run this first — use results to pick C_FIXED_STARVATION for C2/C3/C4.
# =============================================================================
if should_run C1; then
    echo "── C1  Starvation pressure (Claire) ───────────────────────────────────"
    C1_DIR="${SWEEP_ROOT}/Claire/C1_starvation"
    [[ $DRY_RUN -eq 0 ]] && mkdir -p "$C1_DIR"
    i=0
    for st in "${C1_STARVATION[@]}"; do
        label="st${st}"
        for seed in "${SEEDS[@]}"; do
            i=$(( i + 1 ))
            echo "[C1 ${i}/${c1_n}]  ${label}"
            run_one "$C1_DIR" "$label" "$seed" \
                "challenge"               "$C_CHALLENGE" \
                "predatorStarvationSteps" "$st"
        done
    done
    echo
fi

# =============================================================================
#  C2 — REPRODUCTION THRESHOLD SWEEP  (Claire)
#  How many kills must a predator make to be eligible to reproduce?
#  Fixed starvation = C_FIXED_STARVATION (update from C1 results).
# =============================================================================
if should_run C2; then
    echo "── C2  Reproduction threshold (Claire) ────────────────────────────────"
    echo "    Fixed starvation = ${C_FIXED_STARVATION}  (update C_FIXED_STARVATION from C1)"
    C2_DIR="${SWEEP_ROOT}/Claire/C2_min_captures"
    [[ $DRY_RUN -eq 0 ]] && mkdir -p "$C2_DIR"
    i=0
    for mc in "${C2_MIN_CAPTURES[@]}"; do
        label="mc${mc}"
        for seed in "${SEEDS[@]}"; do
            i=$(( i + 1 ))
            echo "[C2 ${i}/${c2_n}]  ${label}"
            run_one "$C2_DIR" "$label" "$seed" \
                "challenge"                      "$C_CHALLENGE" \
                "predatorStarvationSteps"         "$C_FIXED_STARVATION" \
                "predatorMinCapturesToReproduce"  "$mc"
        done
    done
    echo
fi

# =============================================================================
#  C3 — NEURAL NETWORK CAPACITY SWEEP  (Claire)
#  Does network expressiveness limit the emergence of predator-prey dynamics?
#  Fixed starvation = C_FIXED_STARVATION (update from C1 results).
# =============================================================================
if should_run C3; then
    echo "── C3  Neural network capacity (Claire) ───────────────────────────────"
    echo "    Fixed starvation = ${C_FIXED_STARVATION}  (update C_FIXED_STARVATION from C1)"
    C3_DIR="${SWEEP_ROOT}/Claire/C3_max_neurons"
    [[ $DRY_RUN -eq 0 ]] && mkdir -p "$C3_DIR"
    i=0
    for nn in "${C3_MAX_NEURONS[@]}"; do
        label="nn${nn}"
        for seed in "${SEEDS[@]}"; do
            i=$(( i + 1 ))
            echo "[C3 ${i}/${c3_n}]  ${label}"
            run_one "$C3_DIR" "$label" "$seed" \
                "challenge"               "$C_CHALLENGE" \
                "predatorStarvationSteps" "$C_FIXED_STARVATION" \
                "maxNumberNeurons"        "$nn"
        done
    done
    echo
fi

# =============================================================================
#  C4 — PREDATOR PERCEPTION RADIUS SWEEP  (Claire)
#  How far can predators sense prey? A predator-specific advantage.
#  Larger radius makes prey detectable from farther away, boosting hunting
#  effectiveness without changing prey dynamics.
#  Fixed starvation = C_FIXED_STARVATION, challenge = C_CHALLENGE.
# =============================================================================
if should_run C4; then
    echo "── C4  Predator perception radius (Claire) ────────────────────────────"
    echo "    Fixed starvation = ${C_FIXED_STARVATION}"
    C4_DIR="${SWEEP_ROOT}/Claire/C4_perception_radius"
    [[ $DRY_RUN -eq 0 ]] && mkdir -p "$C4_DIR"
    i=0
    for radius in "${C4_PERCEPTION_RADII[@]}"; do
        radius_tag="${radius//./p}"
        label="rad${radius_tag}"
        for seed in "${SEEDS[@]}"; do
            i=$(( i + 1 ))
            echo "[C4 ${i}/${c4_n}]  ${label}"
            run_one "$C4_DIR" "$label" "$seed" \
                "challenge"                    "$C_CHALLENGE" \
                "predatorStarvationSteps"      "$C_FIXED_STARVATION" \
                "predatorPreyPerceptionRadius" "$radius"
        done
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
        echo "## Control runs (predatorPreyEnabled=false)"
        echo ""
        echo "### CTRL1 Environment, no predation"
        echo "| Folder | Challenge |"
        echo "|--------|-----------|"
        for ch in "${CTRL1_CHALLENGES[@]}"; do
            echo "| ch$(printf '%02d' "$ch")_$(ch_name "$ch")_nopred | ${ch} ($(ch_name "$ch")) |"
        done
        echo ""
        echo "### CTRL2 Open arena, no predation"
        echo "| Folder | Challenge | Starvation |"
        echo "|--------|-----------|-----------|"
        for ch in "${CTRL2_CHALLENGES[@]}"; do
            echo "| ch$(printf '%02d' "$ch")_$(ch_name "$ch")_nopred | ${ch} ($(ch_name "$ch")) | 0 (disabled) |"
        done
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
        echo "## Claire — Predator selection pressure experiments"
        echo ""
        echo "All groups use challenge=${C_CHALLENGE}. C2/C3/C4 fix starvation at ${C_FIXED_STARVATION} (update from C1)."
        echo ""
        echo "### C1 Starvation pressure (challenge=${C_CHALLENGE})"
        echo "| Folder | predatorStarvationSteps |"
        echo "|--------|------------------------|"
        for st in "${C1_STARVATION[@]}"; do
            echo "| st${st} | ${st}$([ "$st" -eq 0 ] && echo " (disabled)") |"
        done
        echo ""
        echo "### C2 Reproduction threshold (starvation=${C_FIXED_STARVATION})"
        echo "| Folder | predatorMinCapturesToReproduce |"
        echo "|--------|-------------------------------|"
        for mc in "${C2_MIN_CAPTURES[@]}"; do
            echo "| mc${mc} | ${mc}$([ "$mc" -eq 0 ] && echo " (any predator breeds)") |"
        done
        echo ""
        echo "### C3 Neural network capacity (starvation=${C_FIXED_STARVATION})"
        echo "| Folder | maxNumberNeurons |"
        echo "|--------|-----------------|"
        for nn in "${C3_MAX_NEURONS[@]}"; do
            echo "| nn${nn} | ${nn} |"
        done
        echo ""
        echo "### C4 Predator perception radius (starvation=${C_FIXED_STARVATION})"
        echo "| Folder | predatorPreyPerceptionRadius |"
        echo "|--------|------------------------------|"
        for radius in "${C4_PERCEPTION_RADII[@]}"; do
            echo "| rad${radius//./p} | ${radius} |"
        done
    } > "$SUMMARY"
    echo "Wrote summary: ${SUMMARY}"
fi

# =============================================================================
#  SWEEP OVERVIEW
# =============================================================================
if [[ $DRY_RUN -eq 0 ]]; then
    echo "── Sweep overview ─────────────────────────────────────────────────────"
    "$PYTHON" tools/sweep_overview.py \
        --sweep      "$SWEEP_ROOT" \
        --burn-in    "$BURN_IN" \
        --osc2-alpha "$OSC2_ALPHA" \
        > "${SWEEP_ROOT}/overview.stdout" 2>&1 \
        && echo "Overview written to ${SWEEP_ROOT}/overview/" \
        || echo "! Overview failed — see ${SWEEP_ROOT}/overview.stdout"
    echo
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
