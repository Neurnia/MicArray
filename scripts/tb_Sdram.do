# do file for tb_Sdram.sv
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

# compile IP
vlog -work work [file join $IP_DIR Sdram_pll.v]
vlog -work work [file join $IP_DIR SdramWr_dcfifo.v]
vlog -work work [file join $IP_DIR SdramRd_dcfifo.v]

# compile HDL
vlog -work work -sv [file join $HDL_DIR Sdram SdramWrFifo.sv]
vlog -work work -sv [file join $HDL_DIR Sdram SdramWrCtrl.sv]
vlog -work work -sv [file join $HDL_DIR Sdram SdramRdCtrl.sv]
vlog -work work -sv [file join $HDL_DIR Sdram SdramRdFifo.sv]
vlog -work work -sv [file join $HDL_DIR Sdram SdramControl SdramCore.sv]
vlog -work work -sv [file join $HDL_DIR Sdram SdramControl SdramData.sv]
vlog -work work -sv [file join $HDL_DIR Sdram SdramControl.sv]
vlog -work work -sv [file join $HDL_DIR Sdram.sv]

# compile TB
vlog -work work -sv [file join $SIM_DIR tb_Sdram.sv]

# simulation
vsim -L altera_mf work.tb_Sdram

# wave
add wave *

# run
run -all
view wave
wave zoom full
