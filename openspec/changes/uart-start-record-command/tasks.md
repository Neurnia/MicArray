## 1. UART Receive Path

- [x] 1.1 Add `hdl/UartReceiver.sv` with UART 8N1 receive logic parameterized by `CLK_HZ` and `BAUD_HZ`
- [x] 1.2 Implement exact ASCII `START\n` matching in `UartReceiver` and emit a one-cycle `start_record_o` pulse on a successful idle-time command
- [x] 1.3 Implement `uart_busy_i` handling in `UartReceiver` so busy-time bytes are discarded and partial match state is cleared

## 2. Top-Level Integration

- [x] 2.1 Update `hdl/MicArrayTop.sv` to instantiate `UartReceiver` and connect its `start_record_o` output to the existing record-start path
- [x] 2.2 Remove the active push-button debounce and edge-detect start path from `MicArrayTop.sv`
- [x] 2.3 Keep the existing SDRAM and `UartSender` export path behavior unchanged after the new UART trigger is integrated

## 3. Verification Assets

- [x] 3.1 Add a focused UART receiver testbench that covers valid `START\n`, invalid input, and busy-time discard behavior
- [x] 3.2 Update or add a top-level integration testbench that starts recording through UART RX input instead of the push button
- [x] 3.3 Update simulation scripts as needed so the new receiver and top-level UART-triggered flow can be validated manually in ModelSim
