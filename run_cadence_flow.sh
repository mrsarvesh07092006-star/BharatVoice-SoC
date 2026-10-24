#!/usr/bin/env bash
# =============================================================================
# BharatVoice SoC — Master 5-Tool Cadence ASIC Implementation Flow
# Flow:
#   [1/5] XCELIUM   : RTL Simulation & Testbench Verification
#   [2/5] GENUS     : Logic Synthesis, Optimization & SDC Generation
#   [3/5] CONFORMAL : Logic Equivalence Checking (RTL vs. Netlist)
#   [4/5] TEMPUS    : Static Timing Analysis & Signoff Setup/Hold Checks
#   [5/5] INNOVUS   : Floorplanning, PDN, Placement, CTS, NanoRoute to GDSII
#
# Features:
#   - Automated stage-by-stage checkpointing (.cadence_state)
#   - Error extraction & auto-push to GitHub for Antigravity self-repair
#   - Auto-sensing watch loop (detects fixes and resumes from failed stage)
# =============================================================================

set -e

PRJ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PRJ_ROOT"

STATE_FILE="$PRJ_ROOT/.cadence_state"
ERR_LOG="$PRJ_ROOT/cadence_flow_error.log"

# Initialize flow state or accept manual stage override
STAGE_ARG=$(echo "$1" | tr '[:lower:]' '[:upper:]')
if [ "$1" == "--clean" ] || [ "$1" == "--all" ]; then
    echo "STAGE=XCELIUM" > "$STATE_FILE"
    echo "STATUS=NOT_STARTED" >> "$STATE_FILE"
    echo "ATTEMPTS=0" >> "$STATE_FILE"
    rm -f "$ERR_LOG"
    echo "[INFO] Initialized flow state at Stage 1 (XCELIUM)."
elif [ "$STAGE_ARG" == "CONFORMAL" ] || [ "$STAGE_ARG" == "TEMPUS" ] || [ "$STAGE_ARG" == "INNOVUS" ] || [ "$STAGE_ARG" == "GENUS" ] || [ "$STAGE_ARG" == "XCELIUM" ]; then
    echo "STAGE=$STAGE_ARG" > "$STATE_FILE"
    echo "STATUS=NOT_STARTED" >> "$STATE_FILE"
    echo "ATTEMPTS=0" >> "$STATE_FILE"
    rm -f "$ERR_LOG"
    echo "[INFO] Overriding flow state to Stage: $STAGE_ARG."
elif [ ! -f "$STATE_FILE" ]; then
    if [ -f "syn/netlists/bharatvoice_top_netlist.v" ]; then
        echo "STAGE=CONFORMAL" > "$STATE_FILE"
        echo "[INFO] Synthesized netlist detected. Resuming flow at Stage 3 (CONFORMAL)."
    else
        echo "STAGE=XCELIUM" > "$STATE_FILE"
        echo "[INFO] Initialized flow state at Stage 1 (XCELIUM)."
    fi
    echo "STATUS=NOT_STARTED" >> "$STATE_FILE"
    echo "ATTEMPTS=0" >> "$STATE_FILE"
    rm -f "$ERR_LOG"
fi

get_state() {
    grep "^$1=" "$STATE_FILE" | cut -d'=' -f2
}

set_state() {
    local key="$1"
    local val="$2"
    if grep -q "^${key}=" "$STATE_FILE"; then
        sed -i "s/^${key}=.*/${key}=${val}/" "$STATE_FILE"
    else
        echo "${key}=${val}" >> "$STATE_FILE"
    fi
}

handle_error() {
    local stage="$1"
    local raw_log="$2"
    echo ""
    echo "======================================================================="
    echo " [ERROR] Cadence Flow FAILED in stage: $stage"
    echo "======================================================================="

    echo "--- CADENCE ERROR SUMMARY ---" > "$ERR_LOG"
    echo "Timestamp: $(date -u)" >> "$ERR_LOG"
    echo "Failed Stage: $stage" >> "$ERR_LOG"
    echo "Host: $(hostname)" >> "$ERR_LOG"
    echo "" >> "$ERR_LOG"
    echo "--- EXTRACTED TOOL ERRORS ---" >> "$ERR_LOG"
    
    if [ -f "$raw_log" ]; then
        grep -E "Error |ERROR|FATAL|\*\* Error|Cannot open|Unsupported|FAIL" "$raw_log" | head -n 40 >> "$ERR_LOG" || true
        echo "" >> "$ERR_LOG"
        echo "--- LAST 30 LINES OF EXECUTION LOG ---" >> "$ERR_LOG"
        tail -n 30 "$raw_log" >> "$ERR_LOG"
    else
        echo "Log file $raw_log not found." >> "$ERR_LOG"
    fi

    set_state "STATUS" "FAILED"
    set_state "STAGE" "$stage"

    echo "[INFO] Pushing error diagnostic to GitHub for Antigravity..."
    git add "$ERR_LOG" "$STATE_FILE" "$raw_log" 2>/dev/null || git add "$ERR_LOG" "$STATE_FILE"
    git commit -m "[Auto-Report] Failure in Cadence stage: $stage - awaiting Antigravity fix" || true
    
    if git push origin main; then
        echo "[INFO] Error log successfully pushed to GitHub."
    else
        echo "[WARNING] git push failed. Please verify git credentials or push manually."
    fi

    echo ""
    echo "======================================================================="
    echo " [WATCH] Listening for Antigravity fix on branch 'main'..."
    echo " Antigravity will detect the error, apply the fix, and commit to GitHub."
    echo " This script will automatically resume as soon as the commit is pushed."
    echo " (Press Ctrl+C to abort at any time)"
    echo "======================================================================="

    while true; do
        sleep 5
        git fetch origin main > /dev/null 2>&1 || true
        LOCAL_REV=$(git rev-parse HEAD)
        REMOTE_REV=$(git rev-parse origin/main)

        if [ "$LOCAL_REV" != "$REMOTE_REV" ]; then
            echo ""
            echo ">>> [DETECTED] New fix commit received from Antigravity ($REMOTE_REV)!"
            git pull origin main
            echo ">>> Resuming pipeline from stage: $stage..."
            rm -f "$ERR_LOG"
            set_state "STATUS" "RUNNING"
            exec "$0"
            exit 0
        fi
        echo -n "."
    done
}

# =============================================================================
# Stage 1: Cadence Xcelium Logic Simulation
# =============================================================================
run_xcelium() {
    echo ""
    echo "======================================================================="
    echo " [STAGE 1/5] Running Cadence Xcelium Logic Simulation"
    echo "======================================================================="
    mkdir -p sim/logs
    local log="sim/logs/xrun_master.log"

    if [ -x "./sim/run_xcelium.sh" ]; then
        if ./sim/run_xcelium.sh > "$log" 2>&1; then
            echo "[SUCCESS] Xcelium RTL simulation verified 100% PASS!"
            set_state "STAGE" "GENUS"
            set_state "STATUS" "PASS"
            return 0
        else
            handle_error "XCELIUM" "$log"
            return 1
        fi
    else
        chmod +x ./sim/run_xcelium.sh
        if ./sim/run_xcelium.sh > "$log" 2>&1; then
            echo "[SUCCESS] Xcelium RTL simulation verified 100% PASS!"
            set_state "STAGE" "GENUS"
            set_state "STATUS" "PASS"
            return 0
        else
            handle_error "XCELIUM" "$log"
            return 1
        fi
    fi
}

# =============================================================================
# Stage 2: Cadence Genus Logic Synthesis
# =============================================================================
run_genus() {
    echo ""
    echo "======================================================================="
    echo " [STAGE 2/5] Running Cadence Genus Logic Synthesis"
    echo "======================================================================="
    mkdir -p syn/reports syn/netlists
    local log="syn/reports/genus_flow.log"

    if genus -f syn/scripts/genus_synth.tcl -log "$log"; then
        if [ -f "syn/netlists/bharatvoice_top_netlist.v" ]; then
            echo "[SUCCESS] Genus synthesis completed successfully!"
            set_state "STAGE" "CONFORMAL"
            set_state "STATUS" "PASS"
            return 0
        else
            echo "[ERROR] Netlist not generated despite clean exit." > "$log"
            handle_error "GENUS" "$log"
            return 1
        fi
    else
        handle_error "GENUS" "$log"
        return 1
    fi
}

# =============================================================================
# Stage 3: Cadence Conformal Logic Equivalence Checking (LEC)
# =============================================================================
run_conformal() {
    echo ""
    echo "======================================================================="
    echo " [STAGE 3/5] Running Cadence Conformal Logic Equivalence Checking"
    echo "======================================================================="
    mkdir -p lec
    local log="lec/conformal.log"

    if [ -x "./lec/run_conformal.sh" ]; then
        if ./lec/run_conformal.sh > "$log" 2>&1; then
            echo "[SUCCESS] Conformal LEC verified 100% Equivalent!"
            set_state "STAGE" "TEMPUS"
            set_state "STATUS" "PASS"
            return 0
        else
            handle_error "CONFORMAL" "$log"
            return 1
        fi
    else
        chmod +x ./lec/run_conformal.sh
        if ./lec/run_conformal.sh > "$log" 2>&1; then
            echo "[SUCCESS] Conformal LEC verified 100% Equivalent!"
            set_state "STAGE" "TEMPUS"
            set_state "STATUS" "PASS"
            return 0
        else
            handle_error "CONFORMAL" "$log"
            return 1
        fi
    fi
}

# =============================================================================
# Stage 4: Cadence Tempus STA (Timing Signoff)
# =============================================================================
run_tempus() {
    echo ""
    echo "======================================================================="
    echo " [STAGE 4/5] Running Cadence Tempus Static Timing Analysis"
    echo "======================================================================="
    local log="syn/reports/tempus_flow.log"

    if tempus -f syn/scripts/tempus_sta.tcl -log "$log"; then
        echo "[SUCCESS] Tempus timing signoff completed successfully!"
        set_state "STAGE" "INNOVUS"
        set_state "STATUS" "PASS"
        return 0
    else
        handle_error "TEMPUS" "$log"
        return 1
    fi
}

# =============================================================================
# Stage 5: Cadence Innovus Physical Design (PnR to GDSII)
# =============================================================================
run_innovus() {
    echo ""
    echo "======================================================================="
    echo " [STAGE 5/5] Running Cadence Innovus Place & Route (PnR to GDSII)"
    echo "======================================================================="
    mkdir -p pnr/reports output
    local log="pnr/reports/innovus_flow.log"

    if innovus -files pnr/scripts/innovus_pnr.tcl -log "$log"; then
        if [ -f "output/bharatvoice_top.gds" ]; then
            echo "[SUCCESS] Innovus PnR and GDSII generation completed successfully!"
            set_state "STAGE" "COMPLETED"
            set_state "STATUS" "PASS"
            return 0
        else
            echo "[ERROR] GDSII file not found in ./output/" > "$log"
            handle_error "INNOVUS" "$log"
            return 1
        fi
    else
        handle_error "INNOVUS" "$log"
        return 1
    fi
}

# =============================================================================
# Pipeline Dispatcher (Resumes from current STAGE in .cadence_state)
# =============================================================================
CURRENT_STAGE=$(get_state "STAGE")

echo "======================================================================="
echo " BharatVoice SoC 5-Tool Cadence ASIC Workflow"
echo " Pipeline: XCELIUM -> GENUS -> CONFORMAL -> TEMPUS -> INNOVUS"
echo " Current Stage Resume Point: $CURRENT_STAGE"
echo "======================================================================="

case "$CURRENT_STAGE" in
    XCELIUM)
        run_xcelium
        run_genus
        run_conformal
        run_tempus
        run_innovus
        ;;
    GENUS)
        run_genus
        run_conformal
        run_tempus
        run_innovus
        ;;
    CONFORMAL)
        run_conformal
        run_tempus
        run_innovus
        ;;
    TEMPUS)
        run_tempus
        run_innovus
        ;;
    INNOVUS)
        run_innovus
        ;;
    COMPLETED)
        echo ""
        echo "======================================================================="
        echo " ALL 5 CADENCE STAGES COMPLETED SUCCESSFULLY!"
        echo " 1. Simulation Logs    : sim/logs/"
        echo " 2. Synthesized Netlist: syn/netlists/bharatvoice_top_netlist.v"
        echo " 3. LEC Report         : lec/lec_verification.rpt"
        echo " 4. Timing Reports     : syn/reports/"
        echo " 5. Final Tapeout GDS  : output/bharatvoice_top.gds"
        echo " 6. DRC & LVS Reports  : pnr/reports/"
        echo "======================================================================="
        exit 0
        ;;
    *)
        echo "[WARNING] Unknown state '$CURRENT_STAGE'. Resetting to XCELIUM."
        set_state "STAGE" "XCELIUM"
        run_xcelium
        run_genus
        run_conformal
        run_tempus
        run_innovus
        ;;
esac

echo ""
echo "======================================================================="
echo " COMPLETE 5-TOOL CADENCE ASIC FLOW FINISHED WITH 100% SUCCESS!"
echo " Tapeout GDSII generated at: output/bharatvoice_top.gds"
echo "======================================================================="

git add sim/logs/ syn/reports/ syn/netlists/ lec/ pnr/reports/ output/ .cadence_state 2>/dev/null || true
git commit -m "[Cadence-Signoff] 5-Tool Cadence workflow (Xcelium->Genus->Conformal->Tempus->Innovus) verified cleanly" || true
git push origin main || true
