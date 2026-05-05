#!/usr/bin/env bash
# run_sweep.sh — sweep biosim4 across the experiment matrix and analyse each run.
#
# What it does
# ------------
# For every combination of the parameter arrays defined below, it:
#   1. Copies biosim4.ini → tmp/<run-name>.ini
#   2. Overwrites the swept parameters in that copy
#   3. Runs ./bin/Release/biosim4 <tmp ini> --headless
#   4. Moves the resulting epoch log to Output/Logs/<run-name>.txt
#   5. Runs tools/analyse.py on it, producing
#        Output/Sweep/<run-name>/analysis.png
#        Output/Sweep/<run-name>/analysis_report.md
#
# Edit the four arrays below to define your experiment matrix.  Total runs
# = product of array sizes.  Keep the matrix small until you trust the run!
#
# Usage:
#   ./tools/run_sweep.sh
#   ./tools/run_sweep.sh --dry-run     # just print what would be run

set -euo pipefail

# =============================================================================
#  EXPERIMENT MATRIX  ← edit this block
# =============================================================================
CHALLENGES=(20 0 5)             # environment       (0=circle, 5=corner, 20=open)
PRED_FRACTIONS=(0.3 0.5 0.7)    # size              (initial predator share)
PRED_SPEEDS=(1 2)               # speed             (predator action stride)
PREY_SPEEDS=(1 2)               # speed             (prey action stride)
STARVATION=(60 100 160)         # starvation        (steps without a kill)
MAX_GENERATIONS=400             # short runs while exploring; bump for final
# =============================================================================

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

BASE_INI="biosim4.ini"
TMP_DIR="tmp/sweep"
SWEEP_OUT="Output/Sweep"
LOGS_DIR="Output/Logs"

mkdir -p "$TMP_DIR" "$SWEEP_OUT" "$LOGS_DIR"

PYTHON=".venv/bin/python3"
BIO="./bin/Release/biosim4"

# helper: set or insert a "key = value" line in an ini file (BSD sed compatible)
set_kv() {
    local file="$1" key="$2" value="$3"
    if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
        # macOS BSD sed needs '' after -i; this works on both BSD and GNU since
        # we always provide an extension argument.
        sed -i.bak -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$file"
        rm -f "$file.bak"
    else
        printf '\n%s = %s\n' "$key" "$value" >> "$file"
    fi
}

total=$(( ${#CHALLENGES[@]} * ${#PRED_FRACTIONS[@]} * \
         ${#PRED_SPEEDS[@]}  * ${#PREY_SPEEDS[@]}    * \
         ${#STARVATION[@]} ))
echo "Sweeping ${total} configurations  (challenges=${#CHALLENGES[@]}, "\
"predFrac=${#PRED_FRACTIONS[@]}, predSpeed=${#PRED_SPEEDS[@]}, "\
"preySpeed=${#PREY_SPEEDS[@]}, starv=${#STARVATION[@]})"
echo

i=0
for ch in "${CHALLENGES[@]}"; do
for pf in "${PRED_FRACTIONS[@]}"; do
for ps in "${PRED_SPEEDS[@]}"; do
for ys in "${PREY_SPEEDS[@]}"; do
for st in "${STARVATION[@]}"; do
    i=$((i + 1))
    name=$(printf "ch%02d_pf%s_ps%d_ys%d_st%d" "$ch" "$pf" "$ps" "$ys" "$st")
    ini="$TMP_DIR/$name.ini"
    log="$LOGS_DIR/$name.txt"
    out_dir="$SWEEP_OUT/$name"

    echo "[${i}/${total}]  ${name}"
    if [[ $DRY_RUN -eq 1 ]]; then continue; fi

    cp "$BASE_INI" "$ini"
    set_kv "$ini" "predatorPreyEnabled"     "true"
    set_kv "$ini" "challenge"               "$ch"
    set_kv "$ini" "predatorFraction"        "$pf"
    set_kv "$ini" "predatorActionPeriod"    "$ps"
    set_kv "$ini" "preyActionPeriod"        "$ys"
    set_kv "$ini" "predatorStarvationSteps" "$st"
    set_kv "$ini" "maxGenerations"          "$MAX_GENERATIONS"
    set_kv "$ini" "saveVideo"               "false"
    set_kv "$ini" "updateGraphLog"          "false"

    rm -f "$LOGS_DIR/epoch-log.txt"
    "$BIO" "$ini" --headless > "$TMP_DIR/$name.stdout" 2>&1 || {
        echo "  ! simulator failed — see $TMP_DIR/$name.stdout"
        continue
    }
    if [[ ! -f "$LOGS_DIR/epoch-log.txt" ]]; then
        echo "  ! no epoch log produced; skipping analysis"
        continue
    fi
    mv "$LOGS_DIR/epoch-log.txt" "$log"

    mkdir -p "$out_dir"
    "$PYTHON" tools/analyse.py \
        --log "$log" \
        --out "$out_dir/analysis.png" \
        --report "$out_dir/analysis_report.md" \
        --title "$name" >"$out_dir/analyse.stdout" 2>&1 || true
done
done
done
done
done

echo
echo "Done.  Per-run figures and reports are in $SWEEP_OUT/<name>/"
echo "Logs are in $LOGS_DIR/<name>.txt"
