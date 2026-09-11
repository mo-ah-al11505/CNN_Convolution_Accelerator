# ============================================================
# run_vivado.tcl
# Vivado batch flow: synthesis + implementation + reports
# Target: Zynq-7000 XC7Z020 (PYNQ-Z2)
# Usage:  vivado -mode batch -source run_vivado.tcl
# ============================================================

set part       "xc7z020clg400-1"
set top        "top_accelerator"
set out_dir    "vivado_out"
set rpt_dir    "vivado_out/reports"

file mkdir $out_dir
file mkdir $rpt_dir

# ---- Read sources ----
read_verilog rtl/rtl.v

# ---- Synthesis (out-of-context, no board needed) ----
synth_design -top $top -part $part -mode out_of_context
write_checkpoint -force $out_dir/post_synth.dcp
report_utilization -file $rpt_dir/utilization_synth.rpt
report_timing_summary -file $rpt_dir/timing_synth.rpt

# ---- Implementation ----
opt_design
place_design
route_design

# ---- Reports ----
report_utilization       -file $rpt_dir/utilization.rpt
report_timing_summary    -file $rpt_dir/timing.rpt
report_power             -file $rpt_dir/power.rpt
report_drc               -file $rpt_dir/drc.rpt

write_checkpoint -force $out_dir/post_route.dcp

puts "=============================================="
puts "DONE. Reports in $rpt_dir/"
puts "=============================================="