# do file for tb_RecordWrFifo.sv
# NOTE: execute from inside the modelsim project.

# set directories
set MS_DIR [file normalize [pwd]]
set PRJ_ROOT [file normalize [file join $MS_DIR ..]]
set WORK_DIR [file normalize [file join $MS_DIR work]]

set HDL_DIR [file normalize [file join $PRJ_ROOT hdl]]
set SIM_DIR [file normalize [file join $PRJ_ROOT sim]]
set IP_DIR [file normalize [file join $PRJ_ROOT quartus ipcores]]
set MTI_ALTERA_MF_DIR [file normalize [file join $env(MODEL_TECH) .. altera verilog altera_mf]]

# check if work libs exist
if {![file exists $WORK_DIR]} {
    vlib $WORK_DIR
}

# map work libs
vmap work $WORK_DIR
vmap altera_mf $MTI_ALTERA_MF_DIR

# compile (IP first, then DUT, then TB)
vlog -work work [file join $IP_DIR RecordWr_dcfifo.v]
vlog -work work -sv [file join $HDL_DIR RecordWrFifo.sv]
vlog -work work -sv [file join $SIM_DIR tb_RecordWrFifo.sv]

# simulation
vsim -L altera_mf work.tb_RecordWrFifo

# wave
add wave *

# run
run -all
view wave
wave zoom full
