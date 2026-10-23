# ModelSim: in the Transcript, cd to this sim folder, then:  do sim_arbiter.do
if {[file exists work]} {vdel -lib work -all}
vlib work
vlog ../rtl/arbiter.v ../rtl/addr_decoder.v ../rtl/bus_top.v ../rtl/master_model.v ../rtl/slave_model.v ../tb/tb_arbiter.v
vsim -onfinish stop -voptargs=+acc work.tb_arbiter
add wave -divider Inputs
add wave tb_arbiter/clk tb_arbiter/rst_n tb_arbiter/req0 tb_arbiter/req1
add wave -divider Outputs
add wave tb_arbiter/gnt0 tb_arbiter/gnt1 tb_arbiter/busy
add wave -radix binary tb_arbiter/dut/state
run -all
wave zoom full
