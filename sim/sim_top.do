# ModelSim: cd to this sim folder, then:  do sim_top.do
# Two-board clock phasing: do sim_top_inv.do
if {[file exists work]} {vdel -lib work -all}
vlib work
vlog ../rtl/arbiter.v ../rtl/addr_decoder.v ../rtl/bus_top.v ../rtl/master_model.v ../rtl/slave_model.v ../tb/tb_top.v
vsim -onfinish stop -voptargs=+acc work.tb_top
add wave -divider Clock/Reset
add wave tb_top/clk tb_top/rst_n
add wave -divider Master0
add wave tb_top/m0_req tb_top/m0_gnt tb_top/m0_valid
add wave -radix hex tb_top/m0_dout tb_top/m0_rd
add wave -divider Master1
add wave tb_top/m1_req tb_top/m1_gnt tb_top/m1_valid
add wave -radix hex tb_top/m1_dout tb_top/m1_rd
add wave -divider Bus_to_slaves
add wave -radix unsigned tb_top/s_sel
add wave tb_top/s_valid
add wave -radix hex tb_top/s_wdata
add wave -divider Response
add wave tb_top/m_ready
add wave -radix hex tb_top/m_rdata
add wave tb_top/dec_err
add wave -radix hex tb_top/s0_rd tb_top/s1_rd tb_top/s2_rd
run -all
wave zoom full
