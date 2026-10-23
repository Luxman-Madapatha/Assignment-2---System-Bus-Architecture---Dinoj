# ModelSim: cd to this sim folder, then:  do sim_decoder.do
if {[file exists work]} {vdel -lib work -all}
vlib work
vlog ../rtl/arbiter.v ../rtl/addr_decoder.v ../rtl/bus_top.v ../rtl/master_model.v ../rtl/slave_model.v ../tb/tb_addr_decoder.v
vsim -onfinish stop -voptargs=+acc work.tb_addr_decoder
add wave -radix hex tb_addr_decoder/addr
add wave -radix binary tb_addr_decoder/slave_sel
add wave -radix unsigned tb_addr_decoder/sel_code
add wave tb_addr_decoder/hit
run -all
wave zoom full
