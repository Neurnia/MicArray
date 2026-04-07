## Why

The current design starts one recording window from a local push button, which leaves the FPGA capture flow disconnected from the host application that already receives the exported UART payload. We need a UART-driven start command so the host can trigger capture directly without relying on board-local input.

## What Changes

- Add a UART receive path that recognizes one ASCII command, `START\n`, and converts it into the existing one-cycle record-start pulse in the system clock domain.
- Remove the push-button start path from the active top-level control flow so recording is started only through UART input.
- Drop UART input bytes while the UART export path is busy, so a command received during payload transmission is ignored rather than queued or replayed later.
- Keep the existing SDRAM write/read sequencing and UART export payload format unchanged.

## Capabilities

### New Capabilities
- `uart-start-record-command`: Accept a host-issued UART ASCII command that starts one recording/export cycle when the system is idle.

### Modified Capabilities
- None.

## Impact

- Affected HDL: `hdl/MicArrayTop.sv` and a new UART receive module aligned with `hdl/UartSender.sv`.
- Affected simulations: new UART receive coverage plus top-level integration coverage for UART-triggered record start.
- No changes to the SDRAM buffer contract, UART export framing, or host payload parsing flow.
