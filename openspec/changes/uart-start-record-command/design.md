## Context

`MicArrayTop.sv` currently derives `record_start` from a debounced push button and gates that start event while the UART export path is busy. The UART RX pin already exists at top level, but it is reserved and does not participate in control.

For this change, the host application becomes the only trigger source for one capture/export cycle. The desired behavior is intentionally minimal:

- the host sends ASCII `START\n`
- the FPGA starts one recording window when idle
- the FPGA ignores UART input while the export path is busy
- the existing record, SDRAM, and UART export flow remains unchanged

The project already has a working transmit-side UART path in `UartSender.sv`, so the design should stay aligned with its parameter style and clock-domain assumptions. Simulation is required for confidence, but ModelSim execution remains a manual validation step.

## Goals / Non-Goals

**Goals:**
- Replace the active push-button start path with a UART-driven start command.
- Add one dedicated receive-side HDL module, `UartReceiver`, that recognizes `START\n` and emits a one-cycle `start_record_o` pulse in the system clock domain.
- Make `uart_busy_i` an explicit input to the receiver so busy-time input is discarded inside the receiver rather than queued in top-level logic.
- Keep the rest of the capture/export pipeline behavior unchanged.

**Non-Goals:**
- This change does not add ACK, BUSY, DONE, or any other return messages.
- This change does not introduce a general UART command framework or a unified UART subsystem wrapper.
- This change does not change the UART export framing, SDRAM payload format, or host capture flow.
- This change does not preserve the push-button as a second active trigger source.

## Decisions

### 1. Add one dedicated `UartReceiver` module instead of building a general UART framework now

This change will introduce a single new file, `hdl/UartReceiver.sv`, whose job is limited to receiving UART bytes and recognizing one command, `START\n`.

Why:
- The requested behavior is narrow and does not justify restructuring the already-working transmit path.
- A dedicated receiver keeps the implementation focused on the new control input while staying aligned with `UartSender.sv` naming and parameter style.
- The file-level symmetry between `UartSender` and `UartReceiver` keeps the UART boundary easy to understand in the current repository.

Alternative considered:
- Refactor `UartSender` and the new receive path into one larger UART subsystem.
- Rejected for this change because it expands the scope from “add UART start input” to “re-architect UART infrastructure,” which adds risk without helping the immediate requirement.

### 2. Keep the receiver interface explicit and top-level oriented

`UartReceiver` will expose:

- `clk_i`
- `rst_n_i`
- `uart_rx_i`
- `uart_busy_i`
- `start_record_o`

Why:
- `uart_busy_i` makes the discard condition self-documenting.
- `start_record_o` names the output after the only system action this receiver is allowed to trigger.
- The interface matches the intended top-level integration point and avoids leaking lower-level parse/control signals into `MicArrayTop.sv`.

Alternative considered:
- Use a generic control input such as `ignore_i` or expose byte-level outputs from the receiver.
- Rejected because the current change needs one concrete behavior, not a reusable parser API.

### 3. Parse exactly one command: ASCII `START\\n`

The receiver will accept only the uppercase ASCII sequence `S`, `T`, `A`, `R`, `T`, newline. Any mismatch resets the match state back to idle.

Why:
- A fixed command keeps the first control protocol deterministic and easy to test.
- ASCII is convenient for the host application and easy to inspect during bring-up.
- Tight matching avoids accidental starts from unrelated serial noise or partial text.

Alternative considered:
- Single-byte trigger commands.
- Rejected because they are more fragile and less self-describing for host-driven control.

### 4. Discard bytes while UART export is busy, and clear partial command state

When `uart_busy_i` is asserted, `UartReceiver` will ignore all received input and force its command matcher back to the idle state. Busy-time bytes will not be buffered, replayed, or allowed to complete a command later.

Why:
- The required semantics are “busy-time commands are dropped,” not “busy-time commands are delayed.”
- Clearing partial match state prevents a half-received command before or during busy from generating a stale trigger after busy ends.
- This keeps command lifetime local to the receiver and avoids top-level replay edge cases.

Alternative considered:
- Gate only the final `start_record_o` pulse with `!uart_busy`.
- Rejected because it can leave partial parser state alive and blur the meaning of “discard while busy.”

### 5. Remove the push-button start path from active control

`MicArrayTop.sv` will no longer generate `record_start` from the debounced key path. Instead, it will instantiate `UartReceiver` and forward `start_record_o` into `RecordControl`.

Why:
- The project wants one authoritative trigger source: the host application.
- Eliminating the active button path removes dual-control ambiguity and simplifies verification.
- The existing downstream path already expects only a one-cycle `record_start` pulse, so the trigger source can change without restructuring the rest of the design.

Alternative considered:
- Keep both key and UART as trigger sources.
- Rejected because it introduces unnecessary arbitration and extra behavioral cases for a feature that is meant to be host-controlled.

## Risks / Trade-offs

- [Risk] A strict `START\n` matcher will reject other host line endings such as `\r\n`. → Mitigation: freeze the host behavior to emit exactly `START\n` for this change and keep the parser narrow on purpose.
- [Risk] Removing the active button path reduces on-board manual bring-up options. → Mitigation: accept this trade-off because the target operating mode is host-controlled capture, and minimizing control paths simplifies the design.
- [Risk] The receive path introduces UART timing and parsing logic in the system clock domain. → Mitigation: keep the receiver dedicated to one ASCII command and validate it with focused simulation before hardware bring-up.
