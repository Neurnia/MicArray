# do file for tb_SdramRdCtrl.sv
# NOTE: execute from inside the modelsim project.

# set directories
set MS_DIR [file normalize [pwd]]
set PRJ_ROOT [file normalize [file join $MS_DIR ..]]
set WORK_DIR [file normalize [file join $MS_DIR work]]

set HDL_DIR [file normalize [file join $PRJ_ROOT hdl]]
set SIM_DIR [file normalize [file join $PRJ_ROOT sim]]

# check if work libs exist
if {![file exists $WORK_DIR]} {
    vlib $WORK_DIR
}

# map work libs
vmap work $WORK_DIR

# compile (DUT first)
vlog -work work -sv [file join $HDL_DIR Sdram SdramRdCtrl.sv]
vlog -work work -sv [file join $SIM_DIR tb_SdramRdCtrl.sv]

# simulation
vsim work.tb_SdramRdCtrl

# wave
add wave *

# run
run -all
view wave
wave zoom full
