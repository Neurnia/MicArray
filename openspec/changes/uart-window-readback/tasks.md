## 1. SDRAM Readback Path

- [x] 1.1 Add a read-side FIFO wrapper inside `Sdram.sv` that writes in the SDRAM clock domain and exposes a `16-bit` valid/ready payload stream in the system clock domain
- [x] 1.2 Implement a fixed-window read scheduler that starts from linear address `0`, reads `WINDOW_LENGTH * (MIC_CNT + 1)` payload words, and launches bursts only when the read FIFO has enough free space
- [x] 1.3 Integrate the read scheduler with `SdramControl` so SDRAM read data fills the internal read FIFO without coupling burst timing directly to UART timing

## 2. Top-Level Control And UART Export

- [x] 2.1 Add top-level integration that prevents overlapping record and export phases, with `Sdram.sv` sequencing write/read locally and `MicArrayTop.sv` gating new `record_start` events while UART export is busy
- [x] 2.2 Implement a UART word-stream sender that starts on first payload availability, emits `16'hA55A`, then `MIC_CNT + 1`, then drains the payload stream from `Sdram`
- [x] 2.3 Track one active window-send session and a fixed payload-word counter so UART packet completion is driven by `WINDOW_LENGTH * frame_words`, not by FIFO empty transitions
- [x] 2.4 Freeze the UART word serialization rule as `MSB` first then `LSB`, and connect the sender to the exported `Sdram` valid/ready payload stream

## 3. Host Capture And Verification

- [x] 3.1 Add or replace the PC-side capture script so it finds the `16'hA55A` header, reads `frame_words`, and captures one fixed window payload from the serial port
- [x] 3.2 Save the captured window payload in a raw format that preserves the original exported word order for later offline parsing
- [x] 3.3 Add read-path verification artifacts for the scheduler, FIFO wrapper, and UART prefix behavior, and run the associated ModelSim benches
