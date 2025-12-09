# INMP441-era base pin assignments
# Active design only exercises the board clock, reset, UART, and LEDs.
# The clk_sys_i/rst_n_i/led_n_o/uart_* nets are tied to fixed resources on the EP4CE10
# development board; update the remaining placeholders once custom wiring exists.
# Add the INMP441 PDM/I2S nets here once their FPGA pins are finalized.

set_location_assignment PIN_M2  -to clk_sys_i
set_location_assignment PIN_M1  -to rst_n_i

set_location_assignment PIN_D11 -to led_n_o[0]   ;# board LED0 (active-low)
set_location_assignment PIN_C11 -to led_n_o[1]   ;# board LED1 (active-low)
set_location_assignment PIN_E10 -to led_n_o[2]   ;# board LED2 (active-low)
set_location_assignment PIN_F9  -to led_n_o[3]   ;# board LED3 (active-low)

set_location_assignment PIN_M7  -to uart_tx_o  ;# on-board CH340 bridge
set_location_assignment PIN_N5  -to uart_rx_i  ;# on-board CH340 bridge

# INMP441 I2S drive lines (single-mic bring-up)
set_location_assignment PIN_E7  -to i2s_bclk_o   ;# shared SCK toward the mic
set_location_assignment PIN_B8  -to i2s_ws_o     ;# word-select / LRCLK
set_location_assignment PIN_E5  -to i2s_lr_sel_o ;# strap pin feeding the mic's L/R select

# Microphone data input
set_location_assignment PIN_C6  -to i2s_sd0_i
