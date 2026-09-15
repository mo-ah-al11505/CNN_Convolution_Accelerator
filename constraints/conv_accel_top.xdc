# ---- Primary clock ----
# Edit ONLY this period to retarget frequency; every other constraint
# below is written relative to this clock, not a hardcoded number.
# 10.000 ns = 100 MHz (PYNQ-Z2's PS commonly hands the PL a 100 MHz
# FCLK by default, so this is a safe, realistic starting point).
create_clock -period 7.000 -name clk [get_ports clk]

# ---- Clock uncertainty (jitter + skew allowance) ----
set_clock_uncertainty 0.150 [get_clocks clk]

# ---- Reset is asynchronous - exclude it from setup/hold analysis ----
set_false_path -from [get_ports rst_n]

# ---- I/O delay assumptions ----
# These matter once this block is integrated with real driving/receiving
# logic; for a standalone OOC run they simply give Vivado's timing engine
# sensible numbers for input/output paths instead of leaving them
# completely unconstrained (which would hide real I/O timing issues).
set_input_delay  -clock clk -max 2.000 [get_ports {pixel_in* pixel_valid kernel_we kernel_addr* kernel_data*}]
set_input_delay  -clock clk -min 0.500 [get_ports {pixel_in* pixel_valid kernel_we kernel_addr* kernel_data*}]
set_output_delay -clock clk -max 2.000 [get_ports {pixel_out* pixel_out_valid frame_done}]
set_output_delay -clock clk -min 0.500 [get_ports {pixel_out* pixel_out_valid frame_done}]
