#!/usr/bin/env bash
# =============================================================================
# Cadence Conformal LEC Execution Wrapper
# Flow Stage: [3/5] CONFORMAL Logic Equivalence Checking
# =============================================================================

set -e

PRJ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PRJ_ROOT"

mkdir -p lec

echo "======================================================================="
echo " [CADENCE CONFORMAL] Starting Logic Equivalence Checking (LEC)"
echo " Comparing: Golden RTL vs. Synthesized Gate Netlist"
echo "======================================================================="

# Auto-detect technology library location
LIB=""
for l in "/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/typical.lib" \
         "/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/gsclib090_typical.lib" \
         "$PRJ_ROOT/typical.lib" \
         "$PRJ_ROOT/syn/typical.lib"; do
    if [ -f "$l" ]; then
        LIB="$l"
        break
    fi
done

if [ -n "$LIB" ]; then
    echo "[INFO] Using standard cell library: $LIB"
    sed -i "s|read library -statename typical .* -both|read library -statename typical $LIB -both|" lec/conformal_lec.do
fi

# Run Conformal LEC in batch mode
lec -nogui -dofile lec/conformal_lec.do -logfile lec/conformal.log

echo "======================================================================="
echo " [CADENCE CONFORMAL] LEC Verification Complete!"
echo " Report: lec/lec_verification.rpt"
echo "======================================================================="
