# MicArrayTop pin assignments

# system
set_location_assignment PIN_M2  -to clk_i
set_location_assignment PIN_M1  -to rst_n_i

# keys
set_location_assignment PIN_E16 -to key_n_i

# leds (active-low)
set_location_assignment PIN_D11 -to led_n_o[0]
set_location_assignment PIN_C11 -to led_n_o[1]
set_location_assignment PIN_E10 -to led_n_o[2]

# usb uart
set_location_assignment PIN_M7  -to uart_tx_o
set_location_assignment PIN_N5  -to uart_rx_i

# i2s signal for syb-array 1
set_location_assignment PIN_P9  -to i2s_bclk_o[0]
set_location_assignment PIN_N9  -to i2s_ws_o[0]
# i2s signal for syb-array 2
set_location_assignment PIN_B13 -to i2s_bclk_o[1]
set_location_assignment PIN_A13 -to i2s_ws_o[1]
# sub-array 1
set_location_assignment PIN_L10 -to i2s_sd_i[0]
set_location_assignment PIN_K9  -to i2s_sd_i[1]
set_location_assignment PIN_N8  -to i2s_sd_i[2]
set_location_assignment PIN_P6  -to i2s_sd_i[3]
set_location_assignment PIN_M8  -to i2s_sd_i[4]
set_location_assignment PIN_P8  -to i2s_sd_i[5]
set_location_assignment PIN_L9  -to i2s_sd_i[6]
set_location_assignment PIN_M9  -to i2s_sd_i[7]
set_location_assignment PIN_N6  -to i2s_sd_i[8]
set_location_assignment PIN_T14 -to i2s_sd_i[9]
set_location_assignment PIN_T13 -to i2s_sd_i[10]
set_location_assignment PIN_G2  -to i2s_sd_i[11]
set_location_assignment PIN_R11 -to i2s_sd_i[12]
set_location_assignment PIN_R12 -to i2s_sd_i[13]
set_location_assignment PIN_R13 -to i2s_sd_i[14]
set_location_assignment PIN_R14 -to i2s_sd_i[15]
# sub-array 2
set_location_assignment PIN_A5  -to i2s_sd_i[16]
set_location_assignment PIN_A6  -to i2s_sd_i[17]
set_location_assignment PIN_B3  -to i2s_sd_i[18]
set_location_assignment PIN_B4  -to i2s_sd_i[19]
set_location_assignment PIN_A7  -to i2s_sd_i[20]
set_location_assignment PIN_A4  -to i2s_sd_i[21]
set_location_assignment PIN_B7  -to i2s_sd_i[22]
set_location_assignment PIN_B6  -to i2s_sd_i[23]
set_location_assignment PIN_C6  -to i2s_sd_i[24]
set_location_assignment PIN_E5  -to i2s_sd_i[25]
set_location_assignment PIN_B8  -to i2s_sd_i[26]
set_location_assignment PIN_E7  -to i2s_sd_i[27]
set_location_assignment PIN_F7  -to i2s_sd_i[28]
set_location_assignment PIN_F6  -to i2s_sd_i[29]
set_location_assignment PIN_D6  -to i2s_sd_i[30]
set_location_assignment PIN_F5  -to i2s_sd_i[31]

# sdram
set_location_assignment PIN_B14 -to sdram_clk
set_location_assignment PIN_G11 -to sdram_ba[0]
set_location_assignment PIN_F13 -to sdram_ba[1]
set_location_assignment PIN_J12 -to sdram_cas_n
set_location_assignment PIN_F16 -to sdram_cke
set_location_assignment PIN_K11 -to sdram_ras_n
set_location_assignment PIN_J13 -to sdram_we_n
set_location_assignment PIN_K10 -to sdram_cs_n
set_location_assignment PIN_J14 -to sdram_dqm[0]
set_location_assignment PIN_G15 -to sdram_dqm[1]
set_location_assignment PIN_F11 -to sdram_addr[0]
set_location_assignment PIN_E11 -to sdram_addr[1]
set_location_assignment PIN_D14 -to sdram_addr[2]
set_location_assignment PIN_C14 -to sdram_addr[3]
set_location_assignment PIN_A14 -to sdram_addr[4]
set_location_assignment PIN_A15 -to sdram_addr[5]
set_location_assignment PIN_B16 -to sdram_addr[6]
set_location_assignment PIN_C15 -to sdram_addr[7]
set_location_assignment PIN_C16 -to sdram_addr[8]
set_location_assignment PIN_D15 -to sdram_addr[9]
set_location_assignment PIN_F14 -to sdram_addr[10]
set_location_assignment PIN_D16 -to sdram_addr[11]
set_location_assignment PIN_F15 -to sdram_addr[12]
set_location_assignment PIN_P14 -to sdram_data[0]
set_location_assignment PIN_M12 -to sdram_data[1]
set_location_assignment PIN_N14 -to sdram_data[2]
set_location_assignment PIN_L12 -to sdram_data[3]
set_location_assignment PIN_L13 -to sdram_data[4]
set_location_assignment PIN_L14 -to sdram_data[5]
set_location_assignment PIN_L11 -to sdram_data[6]
set_location_assignment PIN_K12 -to sdram_data[7]
set_location_assignment PIN_G16 -to sdram_data[8]
set_location_assignment PIN_J11 -to sdram_data[9]
set_location_assignment PIN_J16 -to sdram_data[10]
set_location_assignment PIN_J15 -to sdram_data[11]
set_location_assignment PIN_K16 -to sdram_data[12]
set_location_assignment PIN_K15 -to sdram_data[13]
set_location_assignment PIN_L16 -to sdram_data[14]
set_location_assignment PIN_L15 -to sdram_data[15]
