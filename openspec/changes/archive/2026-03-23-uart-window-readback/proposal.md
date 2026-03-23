## Why

The repository can already capture one fixed recording window and write the packed `16-bit` words into SDRAM, but it still cannot move that window back to the PC. The immediate need is a minimal end-to-end path that exports one completed window over UART so the captured data can be inspected and processed on the host.

## What Changes

- Extend the SDRAM buffer subsystem with a fixed-window readback path that reads one completed window from linear address `0`.
- Add a read-side FIFO wrapper inside `Sdram.sv` so SDRAM burst reads stay in the SDRAM clock domain while UART drains data from the system clock domain.
- Expose the SDRAM readback payload as a `16-bit` valid/ready stream outside `Sdram.sv`.
- Add a UART export path that prepends two `16-bit` words in the UART domain: a fixed header `16'hA55A` and `frame_words = MIC_CNT + 1`.
- Keep the payload format unchanged: each frame still contains one error word followed by the channel sample words, and payload words leave SDRAM in the same order they were written.
- Add a simple host capture script that synchronizes on the header, reads `frame_words`, and captures one fixed window for later offline parsing.

## Capabilities

### New Capabilities
- `uart-window-export`: Export one completed recording window to the PC over UART using a fixed two-word prefix and the unchanged packed payload stream.

### Modified Capabilities
- `sdram-buffer-path`: Extend the SDRAM subsystem from write-first buffering to fixed-window readback through an internal read FIFO and a system-domain payload stream.

## Impact

- Affected HDL: `hdl/Sdram.sv`, `hdl/Sdram/SdramWrCtrl.sv`, `hdl/Sdram/SdramRdCtrl.sv`, `hdl/Sdram/SdramRdFifo.sv`, `hdl/Sdram/SdramControl.sv`, `hdl/Sdram/SdramControl/SdramData.sv`, `hdl/UartSender.sv`, and `hdl/MicArrayTop.sv`.
- Affected interfaces: `Sdram` gains a readback stream boundary; the SDRAM subsystem owns write-to-read sequencing locally; top-level integration gates new record starts while UART export is active.
- Affected transport format: UART emits `16'hA55A`, then `frame_words`, then the raw payload words with each word serialized `MSB` first and `LSB` second.
- Affected host tooling: add or replace the PC-side capture script to receive one fixed window packet and save the raw window payload.
