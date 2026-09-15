# modelsim
# do ../Scripts/run.do
# vsim -do ../Scripts/run.do

vlib work
vlog ../RTL/*.v ../tb/*.v
vsim work.tb_conv_accel_top
add wave *
run -all