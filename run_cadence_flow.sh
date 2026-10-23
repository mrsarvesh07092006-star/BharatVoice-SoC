#!/usr/bin/env bash
# =============================================================================
# BharatVoice SoC — Automated Closed-Loop Cadence ASIC Flow & Self-Healing Loop
# Stages: Genus (Synthesis) -> Tempus (STA) -> Innovus (PnR to GDSII)
# Features:
#   1. Automatic Stage Execution & Checkpointing
#   2. Error Log Extraction on Failure
#   3. Automatic Git Commit & Push of Error Log
#   4. Live Polling/Auto-Sensing of Fixes from Antigravity
#   5. Resumption from Failed Stage (does not restart from beginning)
# =============================================================================

set -e

PRJ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PRJ_ROOT"

STATE_FILE="$PRJ_ROOT/.cadence_state"
ERR_LOG="$PRJ_ROOT/cadence_flow_error.log"

# Default state if not present
if [ ! -f "$STATE_FILE" ] || [ "$1" == "--clean" ]; then
    echo "STAGE=GENUS" > "$STATE_FILE"
    echo "STATUS=NOT_STARTED" >> "$STATE_FILE"
    echo "ATTEMPTS=0" >> "$STATE_FILE"
    rm -f "$ERR_LOG"
    echo "[INFO] Initialized fresh flow state at Stage 1 (GENUS)."
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
    
    # Extract error messages from log
    if [ -f "$raw_log" ]; then
        grep -E "Error |ERROR|FATAL|\*\* Error|Cannot open|Unsupported" "$raw_log" | head -n 40 >> "$ERR_LOG" || true
        echo "" >> "$ERR_LOG"
        echo "--- LAST 30 LINES OF EXECUTION LOG ---" >> "$ERR_LOG"
        tail -n 30 "$raw_log" >> "$ERR_LOG"
    else
        echo "Log file $raw_log not found." >> "$ERR_LOG"
    fi

    set_state "STATUS" "FAILED"
    set_state "STAGE" "$stage"

    # Stage error log and push to GitHub so Antigravity can analyze & fix
    echo "[INFO] Pushing error diagnostic to GitHub for Antigravity..."
    git add "$ERR_LOG" "$STATE_FILE" "$raw_log" 2>/dev/null || git add "$ERR_LOG" "$STATE_FILE"
    git commit -m "[Auto-Report] Failure in Cadence stage: $stage - awaiting Antigravity fix" || true
    
    if git push origin main; then
        echo "[INFO] Error log successfully pushed to GitHub."
    else
        echo "[WARNING] git push failed. Please verify git credentials or push manually."
    fi

    # Enter Watch/Listening Loop for Antigravity's Fix
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
# Stage 1: Cadence Genus Synthesis
# =============================================================================
run_genus() {
    echo ""
    echo "======================================================================="
    echo " [STAGE 1/3] Running Cadence Genus Logic Synthesis"
    echo "======================================================================="
    mkdir -p syn/reports syn/netlists
    local log="syn/reports/genus_flow.log"

    if genus -f syn/scripts/genus_synth.tcl -log "$log"; then
        # Check if netlist actually produced
        if [ -f "syn/netlists/bharatvoice_top_netlist.v" ]; then
            echo "[SUCCESS] Genus synthesis completed successfully!"
            set_state "STAGE" "TEMPUS"
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
# Stage 2: Cadence Tempus STA (Timing Signoff)
# =============================================================================
run_tempus() {
    echo ""
    echo "======================================================================="
    echo " [STAGE 2/3] Running Cadence Tempus Static Timing Analysis"
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
# Stage 3: Cadence Innovus Physical Design (PnR to GDSII)
# =============================================================================
run_innovus() {
    echo ""
    echo "======================================================================="
    echo " [STAGE 3/3] Running Cadence Innovus Place & Route (PnR to GDSII)"
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
# Main Pipeline Dispatcher (Resumes from current STAGE in .cadence_state)
# =============================================================================
CURRENT_STAGE=$(get_state "STAGE")

echo "======================================================================="
echo " BharatVoice SoC Cadence Automated ASIC Flow Runner"
echo " Current Stage Resume Point: $CURRENT_STAGE"
echo "======================================================================="

case "$CURRENT_STAGE" in
    GENUS)
        run_genus
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
        echo " ALL STAGES COMPLETED SUCCESSFULLY!"
        echo " 1. Synthesized Netlist : syn/netlists/bharatvoice_top_netlist.v"
        echo " 2. Timing Reports      : syn/reports/"
        echo " 3. Tapeout GDSII File  : output/bharatvoice_top.gds"
        echo " 4. DRC & LVS Reports   : pnr/reports/"
        echo "======================================================================="
        exit 0
        ;;
    *)
        echo "[WARNING] Unknown state '$CURRENT_STAGE'. Resetting to GENUS."
        set_state "STAGE" "GENUS"
        run_genus
        run_tempus
        run_innovus
        ;;
esac

echo ""
echo "======================================================================="
echo " CADENCE ASIC FLOW FINISHED WITH 100% SUCCESS!"
echo " Output GDSII: output/bharatvoice_top.gds"
echo "======================================================================="

# Final push of results and reports to GitHub
git add syn/reports/ pnr/reports/ output/ .cadence_state 2>/dev/null || true
git commit -m "[Cadence-Signoff] Full flow completed from Genus to GDSII cleanly" || true
git push origin main || true
