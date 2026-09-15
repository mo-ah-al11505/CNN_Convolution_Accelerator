# ============================================================
# run_vivado.tcl
# Vivado batch flow: synthesis + implementation + reports + FOM
# Target: Zynq-7000 XC7Z020 (PYNQ-Z2)
# Usage:  vivado -mode batch -source ../scripts/run_vivado.tcl
# ============================================================

set part        "xc7z020clg400-1"
set top         "conv_accel_top"
set out_dir     "../vivado_out"
set rpt_dir     "../vivado_out/reports"
set xdc_file    "../constraints/conv_accel_top.xdc"

file mkdir $out_dir
file mkdir $rpt_dir

# ---- Read sources ----
read_verilog [glob ../rtl/*.v]

# ---- Read timing/IO constraints ----
if {![file exists $xdc_file]} {
    puts "ERROR: constraints file not found at $xdc_file"
    exit 1
}
read_xdc $xdc_file

# ---- Synthesis (out-of-context, no board needed) ----
synth_design -top $top -part $part -mode out_of_context
write_checkpoint -force $out_dir/post_synth.dcp
report_utilization      -file $rpt_dir/utilization_synth.rpt
report_timing_summary   -file $rpt_dir/timing_synth.rpt

# ---- Implementation ----
opt_design
place_design
phys_opt_design
route_design

# ---- Reports ----
report_utilization        -file $rpt_dir/utilization.rpt
report_timing_summary     -file $rpt_dir/timing.rpt
report_clock_utilization  -file $rpt_dir/clock_utilization.rpt
report_power              -file $rpt_dir/power.rpt
report_drc                -file $rpt_dir/drc.rpt

write_checkpoint -force $out_dir/post_route.dcp

# ============================================================
# Parse key numbers out of the reports above and compute the
# competition's Figure of Merit:
#   FOM = Throughput / (Power * (LUTs + 50*DSPs + 100*BRAMs))
# Throughput is taken as 1 output pixel/cycle (this architecture's
# steady-state rate once the pipeline is full) - edit $throughput
# below if your design's steady-state rate differs.
# ============================================================

proc read_file_text {path} {
    set fh [open $path r]
    set txt [read $fh]
    close $fh
    return $txt
}

proc grab_number {pattern text {group 1}} {
    if {[regexp $pattern $text -> val]} {
        return $val
    }
    return "N/A"
}

set util_txt  [read_file_text $rpt_dir/utilization.rpt]
set power_txt [read_file_text $rpt_dir/power.rpt]
set timing_txt [read_file_text $rpt_dir/timing.rpt]

# --- Utilization: Slice LUTs, Slice Registers, DSPs, Block RAM Tile ---
set luts  [grab_number {Slice LUTs\s*\|\s*(\d+)} $util_txt]
set ffs   [grab_number {Slice Registers\s*\|\s*(\d+)} $util_txt]
set dsps  [grab_number {DSPs\s*\|\s*(\d+)} $util_txt]
set brams [grab_number {Block RAM Tile\s*\|\s*([\d.]+)} $util_txt]

# --- Power: Total On-Chip Power (W) ---
set power_w [grab_number {Total On-Chip Power \(W\)\s*\|\s*([\d.]+)} $power_txt]

# --- Timing: Worst Negative Slack (WNS) ---
set wns [grab_number {WNS\(ns\)\s*\n[-\s]*\n\s*([\-\d.]+)} $timing_txt]
if {$wns eq "N/A"} {
    # fallback: some Vivado versions format the summary table differently
    set wns [grab_number {Slack\s*\(\S*\)\s*:\s*([\-\d.]+)} $timing_txt]
}

# --- Derive achieved Fmax from the constrained period + WNS ---
set clk_period_ns [get_property PERIOD [get_clocks clk]]
if {$wns ne "N/A" && $clk_period_ns ne ""} {
    set achieved_period [expr {$clk_period_ns - $wns}]
    if {$achieved_period > 0} {
        set fmax_mhz [expr {1000.0 / $achieved_period}]
    } else {
        set fmax_mhz "N/A (negative/zero achieved period - check timing.rpt)"
    }
} else {
    set fmax_mhz "N/A"
}

# --- FOM ---
set throughput 1.0
set fom "N/A"
if {$luts ne "N/A" && $dsps ne "N/A" && $brams ne "N/A" && $power_w ne "N/A" && $power_w > 0} {
    set denom [expr {$power_w * ($luts + 50.0*$dsps + 100.0*$brams)}]
    if {$denom > 0} {
        set fom [expr {$throughput / $denom}]
    }
}

set summary "
==============================================
  conv_accel_top - Post-Implementation Summary
==============================================
Constrained clock period : $clk_period_ns ns
Worst Negative Slack(WNS): $wns ns
Achieved Fmax            : $fmax_mhz MHz
------------------------------------------------
Slice LUTs                : $luts
Slice Registers (FFs)     : $ffs
DSPs                      : $dsps
Block RAM Tiles           : $brams
Total On-Chip Power (W)   : $power_w
------------------------------------------------
Throughput (px/cycle)     : $throughput
Figure of Merit (FOM)     : $fom
==============================================
NOTE: If WNS or Fmax show N/A, open $rpt_dir/timing.rpt manually -
the exact text layout of the timing summary can vary slightly
between Vivado versions and the regex above may need a small tweak.
"

puts $summary
set fh [open $rpt_dir/summary.txt w]
puts $fh $summary
close $fh

puts "=============================================="
puts "DONE. Reports in $rpt_dir/"
puts "=============================================="