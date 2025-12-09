# Timing

## reset synchronizer
```wavedrom
{ "signal": [
  { "name": "clk_i",      "wave": "p..........." },
  { "name": "rst_n_i",    "wave": "1.0...1....." },
  { "name": "rst_shift",  "wave": "3.3...33....", "data": ["11","00","01","11"] },
  { "name": "rst_n_sync", "wave": "1.0....1...." }
]}
```

## I2SClockGen (BCLK/WS)
```wavedrom
{ "signal": [
  { "name": "clk_i",  "wave": "p...................." },
  { "name": "bclk_o", "wave": "P....P....P....P...." , "period": 2 },
  { "name": "ws_o",   "wave": "0...............1..." , "phase": 8,
    "data": ["L (32 BCLK)","R (32 BCLK)"]
  }
]}
```

## I2sCapture (left channel)
```wavedrom
{ "signal": [
  { "name": "bclk_i",   "wave": "p................" },
  { "name": "ws_i",     "wave": "0.......1....0..." },
  { "name": "sd_i",     "wave": "x3456789abcdefgh", "data": ["MSB","...", "LSB"] },
  { "name": "sample_valid_o", "wave": "0...........10.." }
]}
```
WS toggles on BCLK falling edges; data is captured on BCLK rising edges with a one-bit delay after the WS transition. `sample_valid_o` pulses after 24 bits of the selected channel.

## SampleRamFifo handshake
```wavedrom
{ "signal": [
  { "name": "clk_i",       "wave": "p................" },
  { "name": "wr_valid_i",  "wave": "0.1..0.1..0....." },
  { "name": "wr_ready_o",  "wave": "1..............."},
  { "name": "rd_valid_o",  "wave": "0...1...1...1..." },
  { "name": "rd_ready_i",  "wave": "0.....1..0..1..." }
]}
```
`wr_valid_i` samples are written when `wr_ready_o` is high. `rd_valid_o` reflects FIFO non-empty; advancing requires `rd_ready_i`.

## PcmUartFramedTx (5-byte frame)
```wavedrom
{ "config": { "hscale": 2 },
  "signal": [
    { "name": "clk_i",          "wave": "p........................" },
    { "name": "sample_valid_i", "wave": "0.1....................." },
    { "name": "sample_ready_o", "wave": "1.0.......1............." },
    { "name": "uart_tx_o",      "wave": "1.0.1010.1010.1010.101.", 
      "data": ["A5","D23..16","D15..8","D7..0","0A"] }
]}
```
When `sample_valid_i` && `sample_ready_o`, the module latches the 24-bit word and serializes a 5-byte frame (start/data/stop bits per byte) using its internal fractional baud generator.
