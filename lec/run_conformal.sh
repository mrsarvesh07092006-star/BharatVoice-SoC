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

# Run Conformal LEC in batch mode
lec -nogui -dofile lec/conformal_lec.do -logfile lec/conformal.log

echo "======================================================================="
echo " [CADENCE CONFORMAL] LEC Verification Complete!"
echo " Report: lec/lec_verification.rpt"
echo "======================================================================="
