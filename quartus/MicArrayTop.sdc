create_clock -name clk_i -period 20.000 [get_ports {clk_i}]

derive_pll_clocks
derive_clock_uncertainty
