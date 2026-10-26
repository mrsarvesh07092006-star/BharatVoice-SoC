# ==============================================================================
# BharatVoice SoC — Synopsys Design Constraints (SDC)
# Target: 50 MHz System Clock (20.0 ns period)
# File  : syn/constraints/bharatvoice.sdc
# ==============================================================================

# Operating Units
set_units -time ns -resistance kOhm -capacitance pF -voltage V -current mA

# ------------------------------------------------------------------------------
# 1. Primary Clock Definition
# Target: 65.6 MHz System Clock (15.24 ns period) to achieve 0-50 ps slack
# ------------------------------------------------------------------------------
create_clock -name clk_sys -period 15.240 -waveform {0.000 7.620} [get_ports clk_i]

# Clock Network Attributes
set_clock_uncertainty -setup 0.250 [get_clocks clk_sys]
set_clock_uncertainty -hold  0.100 [get_clocks clk_sys]
set_clock_transition 0.150 [get_clocks clk_sys]

# ------------------------------------------------------------------------------
# 2. Asynchronous / False Paths
# ------------------------------------------------------------------------------
# Asynchronous external power-on reset (synchronized on-chip by 2-stage synchronizer)
set_false_path -from [get_ports rst_ni]

# Asynchronous on-chip reset synchronizer output (drives 11k+ async reset .RN pins)
catch { set_false_path -from [get_pins -hier *rst_ff2*/Q] }
catch { set_false_path -from [get_pins rst_ff2_reg/Q] }

# JTAG static/debug inputs (asynchronous to system clock)
set_false_path -from [get_ports {jtag_tck_i jtag_tms_i jtag_tdi_i}]
set_false_path -to   [get_ports jtag_tdo_o]

# ------------------------------------------------------------------------------
# 2.1 Multicycle Paths
# ------------------------------------------------------------------------------
# Allow 2 clock cycles for CRC calculation handshake into payment engine
set_multicycle_path -setup 2 -from [get_cells -hier *u_crc_checker*] -to [get_cells -hier *u_payment_engine*]
set_multicycle_path -hold  1 -from [get_cells -hier *u_crc_checker*] -to [get_cells -hier *u_payment_engine*]

# ------------------------------------------------------------------------------
# 3. Input Constraints
# ------------------------------------------------------------------------------
# External inputs: UART RX stream and SPI MISO line
set_input_delay -clock clk_sys -max 4.000 [get_ports {uart_rx_i spi_miso_i}]
set_input_delay -clock clk_sys -min 1.000 [get_ports {uart_rx_i spi_miso_i}]

# Input driving cell assumption (standard buffer equivalent)
set_input_transition 0.200 [get_ports {uart_rx_i spi_miso_i rst_ni}]

# ------------------------------------------------------------------------------
# 4. Output Constraints
# ------------------------------------------------------------------------------
# SPI outputs, PWM audio output, GPIO status LEDs
set_output_delay -clock clk_sys -max 4.000 [get_ports {spi_sclk_o spi_mosi_o spi_cs_n_o pwm_audio_o gpio_o[*]}]
set_output_delay -clock clk_sys -min 0.500 [get_ports {spi_sclk_o spi_mosi_o spi_cs_n_o pwm_audio_o gpio_o[*]}]

# External capacitive load (50 fF standard IO pad load)
set_load -pin_load 0.050 [get_ports {spi_sclk_o spi_mosi_o spi_cs_n_o pwm_audio_o gpio_o[*]}]

# ------------------------------------------------------------------------------
# 5. Design Rule Constraints (DRC limits for synthesis)
# ------------------------------------------------------------------------------
set_max_transition 0.500 [current_design]
set_max_fanout 16.000 [current_design]
set_max_capacitance 0.200 [current_design]
