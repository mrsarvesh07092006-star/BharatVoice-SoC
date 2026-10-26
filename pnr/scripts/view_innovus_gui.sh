#!/usr/bin/env bash
# =============================================================================
# View Innovus Layout in GUI Mode
# Design: BharatVoice SoC (bharatvoice_top)
# Tool  : Cadence Innovus
# =============================================================================

# 1. Source Cadence environment scripts if present
[ -f /home/cadence/install/setup.sh ] && source /home/cadence/install/setup.sh >/dev/null 2>&1 || true
[ -f /home/cadence/setup.sh ]         && source /home/cadence/setup.sh         >/dev/null 2>&1 || true

# 2. Dynamically probe and add Innovus to PATH if not already found
if ! command -v innovus >/dev/null 2>&1; then
    for d in \
        /home/cadence/install*/INNOVUS*/bin \
        /home/cadence/install*/innovus*/bin \
        /home/cadence/install_RB_8.7/INNOVUS*/bin \
        /opt/cadence/INNOVUS*/bin \
        /opt/cadence/innovus*/bin \
        /tools/cadence/INNOVUS*/bin \
        /eda/cadence/INNOVUS*/bin; do
        if [ -d "$d" ]; then
            export PATH="$d:$PATH"
            break
        fi
    done
fi

if ! command -v innovus >/dev/null 2>&1; then
    echo "[ERROR] 'innovus' binary not found in PATH or standard install locations."
    echo "Please run: which innovus   or locate the binary on your server."
    exit 1
fi

echo "[INFO] Using Innovus: $(command -v innovus)"
echo "[INFO] Loading routed design (06_route.enc.dat) into GUI..."

# Check if design checkpoint exists in current directory or pnr/
DESIGN_FILE=""
if [ -d "06_route.enc.dat" ] || [ -f "06_route.enc" ]; then
    DESIGN_FILE="06_route.enc.dat"
elif [ -d "pnr/06_route.enc.dat" ] || [ -f "pnr/06_route.enc" ]; then
    DESIGN_FILE="pnr/06_route.enc.dat"
fi

if [ -n "$DESIGN_FILE" ]; then
    innovus -execute "restoreDesign $DESIGN_FILE bharatvoice_top; win"
else
    # Fallback: Open Innovus GUI blank so user can load via File -> Restore Design
    innovus
fi
