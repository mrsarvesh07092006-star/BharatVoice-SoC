#!/usr/bin/env bash
# =============================================================================
# BharatVoice SoC — Autonomous ASIC Pilot Daemon
# =============================================================================
# Constantly monitors GitHub for commits from Antigravity AI or user.
# When a commit is detected:
#   1. Force-syncs the workspace cleanly to avoid divergent merge conflicts.
#   2. Executes run_cadence_flow.sh (auto-resumes from last checkpoint).
#   3. If any error occurs, run_cadence_flow.sh pushes the error report to GitHub.
#   4. Antigravity AI reads the error, patches the fix, and pushes to GitHub.
#   5. This daemon detects the fix and automatically resumes until GDS2 is taped out!
# =============================================================================

echo "================================================================="
echo "   BHARATVOICE AI AUTOPILOT DAEMON STARTED ON CADENCE SERVER"
echo "   Listening for changes from GitHub..."
echo "================================================================="

# Set Licenses & Tools
export CDS_LIC_FILE="5280@14.139.1.126:1717@14.139.1.126"
export LM_LICENSE_FILE="5280@14.139.1.126:1717@14.139.1.126"
export PATH=/home/cadence/install/GENUS211/bin:$PATH
export PATH=/home/cadence/install/INNOVUS211/bin:$PATH
export PATH=/home/cadence/install/XCELIUM2209/bin:$PATH
export PATH=/home/cadence/install/XCELIUM2209/tools.lnx86/bin:$PATH
export PATH=/home/cadence/install/CONFRML211/bin:$PATH

while true; do
    git fetch origin main >/dev/null 2>&1
    LOCAL=$(git rev-parse HEAD 2>/dev/null || echo "0")
    REMOTE=$(git rev-parse origin/main 2>/dev/null || echo "1")

    if [ "$LOCAL" != "$REMOTE" ]; then
        echo ""
        echo "[$(date '+%H:%M:%S')] 🚀 New commit detected from GitHub! Syncing workspace..."
        git reset --hard origin/main

        echo "[$(date '+%H:%M:%S')] ⚙️ Running ASIC Flow (Auto-resumes from checkpoint)..."
        bash run_cadence_flow.sh
    fi
    sleep 5
done
