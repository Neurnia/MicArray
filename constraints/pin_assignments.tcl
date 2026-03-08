# INMP441 base pin assignments

set_location_assignment PIN_M2  -to clk_sys_i
set_location_assignment PIN_M1  -to rst_n_i

set_location_assignment PIN_D11 -to led_n_o[0]   ;# LED0 (active-low)
set_location_assignment PIN_C11 -to led_n_o[1]   ;# LED1 (active-low)
set_location_assignment PIN_E10 -to led_n_o[2]   ;# LED2 (active-low)
set_location_assignment PIN_F9  -to led_n_o[3]   ;# LED3 (active-low)

set_location_assignment PIN_M7  -to uart_tx_o
set_location_assignment PIN_N5  -to uart_rx_i

# I2S clocks
set_location_assignment PIN_B13 -to i2s_bclk_o
set_location_assignment PIN_A13 -to i2s_ws_o

# Microphone data inputs
set_location_assignment PIN_F7  -to i2s_sd0_i
set_location_assignment PIN_E7  -to i2s_sd1_i
