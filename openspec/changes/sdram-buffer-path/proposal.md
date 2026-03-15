## Why

The microphone frontend, record-control layer, and cross-domain write FIFO are already in place, but the project still lacks the SDRAM buffer path needed to store captured windows before sending them to the PC. The next step is to implement the write path now while defining the SDRAM control boundary in a way that will support later readback for UART export without redesigning the controller.

## What Changes

- Define an SDRAM buffer architecture that separates write scheduling from SDRAM chip-level control.
- Keep the first implementation focused on the write path from `RecordWrFifo` into SDRAM.
- Define `SdramControl` around a lightweight transaction interface with distinct command, write-data, and read-data channels so future readback can be added without changing the controller boundary.
- Implement the write-side scheduler that converts FIFO state into SDRAM write transactions, including standard bursts and final tail flushes after `window_done`.
- Implement the first `SdramControl` hierarchy as a single-transaction SDRAM executor split into `SdramCore`, `SdramCmd`, and `SdramData`.

## Capabilities

### New Capabilities
- `sdram-buffer-path`: Buffer packed record words in SDRAM through a write-first, read-aware SDRAM control architecture that preserves a future readback path for UART export.

### Modified Capabilities
- None.

## Impact

- Affected HDL: `hdl/Sdram/SdramFifoCtrl.sv`, `hdl/Sdram/SdramControl.sv`, `hdl/Sdram/SdramControl/SdramCore.sv`, `hdl/Sdram/SdramControl/SdramCmd.sv`, `hdl/Sdram/SdramControl/SdramData.sv`, `hdl/Sdram.sv`, and `hdl/MicArrayTop.sv`
- Affected interfaces: `RecordWrFifo -> SdramFifoCtrl -> SdramControl`
- Future interface reservation: `SdramRdCtrl -> SdramControl -> UART export path`
- Affected verification: new write-scheduler and SDRAM controller benches, plus interface-level checks that preserve future readback expansion
