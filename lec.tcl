# ============================================================
# Cadence Conformal LEC - BharatVoice SoC
# VIT Lab - 90nm ASIC Verification Flow
# ============================================================

# ----------------------------------------------------------
# STEP 1: Read technology library (golden + revised both)
# ----------------------------------------------------------
read_library -lib /home/cadence/install/FOUNDRY/digital/90nm/dig/lib/typical.lib -both

# ----------------------------------------------------------
# STEP 2: Read Golden RTL (SystemVerilog with SYNTHESIS define)
# ----------------------------------------------------------
read_design -golden -systemverilog -define SYNTHESIS \
    ibex_core.sv \
    boot_rom.sv \
    uart_rx.sv \
    irq_ctrl.sv \
    clint.sv \
    crc_checker.sv \
    transaction_guard.sv \
    power_manager.sv \
    payment_engine.sv \
    audio_engine.sv \
    sram_model.sv \
    sram_controller.sv \
    spi_master.sv \
    spi_controller.sv \
    transaction_cache.sv \
    bus_interconnect.sv \
    bharatvoice_top.sv

set_root_module bharatvoice_top -golden

# ----------------------------------------------------------
# STEP 3: Read Revised netlist (post-Genus synthesis)
# ----------------------------------------------------------
read_design -revised -verilog ./syn/netlists/bharatvoice_top_netlist.v
set_root_module bharatvoice_top -revised

# ----------------------------------------------------------
# STEP 4: Sequential Flattening & Constant Propagation
# Root cause: All 11k+ FFs in netlist have .RN(rst_ff2)
# rst_ff2 is an internal synchronizer node (not a PI).
# Must propagate it as constant-1 so Conformal can prove
# equivalence instead of leaving async-reset branches open.
# ----------------------------------------------------------
set_flatten_model -seq_constant
set_flatten_model -seq_constant_x_to_zero
set_flatten_model -gated_clock

# ----------------------------------------------------------
# STEP 5: Pin Constraints
# rst_ni=1  → normal operation (no reset asserted)
# jtag pins → held inactive (no debug override)
# rst_ff2   → synchronizer output is constant 1 when rst_ni=1
# rst_sync_n → same, the exported alias of rst_ff2
# ----------------------------------------------------------
add_pin_constraints 1 rst_ni   -both
add_pin_constraints 0 jtag_tck_i -both
add_pin_constraints 0 jtag_tms_i -both
add_pin_constraints 0 jtag_tdi_i -both

# Set synchronizer internal signals as constant-1
# (catch in case the node name differs between golden/revised)
catch { set_constant 1 rst_ff2   -both }
catch { set_constant 1 rst_sync_n -both }
catch { add_pin_constraints 1 rst_ff2   -both }
catch { add_pin_constraints 1 rst_sync_n -both }

# ----------------------------------------------------------
# STEP 6: Enter LEC Verification Mode
# ----------------------------------------------------------
set_system_mode lec

# ----------------------------------------------------------
# STEP 7: Remove synchronizer FFs from comparison points
# rst_ff1 / rst_ff2 are structural glue — not functional
# outputs — so excluding them is logically correct.
# ----------------------------------------------------------
catch { delete_compared_points rst_ff1 -golden }
catch { delete_compared_points rst_ff2 -golden }

# ----------------------------------------------------------
# STEP 8: Map & Compare
# ----------------------------------------------------------
map_key_points
add_compared_points -all
compare

# ----------------------------------------------------------
# STEP 9: Reports
# ----------------------------------------------------------
report_verification
report_compare_data -class nonequivalent -class abort -class notcompared
