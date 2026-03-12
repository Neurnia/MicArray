# do file for tb_I2sCapture.sv
# NOTE: execute from inside the modelsim project.

# set directories
set MS_DIR [file normalize [pwd]]
set PRJ_ROOT [file normalize [file join $MS_DIR ..]]
set WORK_DIR [file normalize [file join $MS_DIR work]]

set HDL_DIR [file normalize [file join $PRJ_ROOT hdl]]
set FRONTEND_DIR [file normalize [file join $HDL_DIR MicFrontend]]
set SIM_DIR [file normalize [file join $PRJ_ROOT sim]]

# check if work libs exist
if {![file exists $WORK_DIR]} {
    vlib $WORK_DIR
}

# map work libs
vmap work $WORK_DIR

# compile (DUT first)
vlog -work work -sv [file join $FRONTEND_DIR I2sCapture.sv]
vlog -work work -sv [file join $SIM_DIR tb_I2sCapture.sv]

# simulation
vsim work.tb_I2sCapture

# wave
add wave *
add wave sim:/tb_I2sCapture/u_dut/state
add wave sim:/tb_I2sCapture/u_dut/next_state

# run
run -all
view wave
wave zoom full
