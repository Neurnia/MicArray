# AD7606 control interface pin assignments
#
# Update the data bus and status signal locations to match your wiring.
# Example: source this file inside MicArray.qsf using `source ../constraints/pin_assignments.tcl`

set_location_assignment PIN_N9  -to convst_a
set_location_assignment PIN_P9  -to convst_b
set_location_assignment PIN_L10 -to adc_reset_n
set_location_assignment PIN_M9  -to rd_n
set_location_assignment PIN_K9  -to cs_n

# System clock and reset
set_location_assignment PIN_M2  -to clk50
set_location_assignment PIN_M1  -to sys_rst_n

# Debug LEDs
set_location_assignment PIN_D11 -to led[0]
set_location_assignment PIN_C11 -to led[1]
set_location_assignment PIN_E10 -to led[2]
set_location_assignment PIN_F9  -to led[3]

# UART bridge (CH340) pins
set_location_assignment PIN_M7 -to uart_tx
set_location_assignment PIN_N5 -to uart_rx

# AD7606 status signals
set_location_assignment PIN_L9 -to busy
set_location_assignment PIN_P8 -to frstdata

# Uncomment and fill in once BUSY/FRSTDATA/data bus are connected to FPGA
# set_location_assignment PIN_?? -to db[0]
# set_location_assignment PIN_?? -to db[1]
# ...
# set_location_assignment PIN_?? -to db[15]
