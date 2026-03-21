## Context

The MicArray project already has the microphone frontend, record-control layer, packer, CDC write FIFO, and SDRAM write path in place. The current top-level integration can record one fixed window and store the packed words in SDRAM, but the UART pins are still idle and there is no readback path from SDRAM to the PC.

For the current milestone, the project does not need real-time streaming, ring buffers, or payload post-processing inside the FPGA. It only needs to move one completed window to the host so the payload can be inspected and converted later on the PC side.

The user has already frozen several constraints for this change:

- record one fixed window, then export that same fixed window
- SDRAM write and SDRAM read both start from linear address `0`
- payload length is fixed by `WINDOW_LENGTH * (MIC_CNT + 1)` words
- the payload format remains unchanged: one error word plus `MIC_CNT` sample words per frame
- `header` and `frame_words` are UART transport words only and are not stored in SDRAM
- the UART serializer sends each `16-bit` word as `MSB` first, then `LSB`
- the read FIFO belongs inside `Sdram.sv` because it bridges the SDRAM clock domain to the system/UART domain

## Goals / Non-Goals

**Goals:**
- Add a minimal readback path that reads one fixed payload window from SDRAM after recording completes.
- Keep SDRAM burst timing decoupled from UART timing by placing a read FIFO inside `Sdram.sv`.
- Expose a simple `16-bit` valid/ready payload stream outside `Sdram.sv` for the UART sender.
- Add a UART sender that injects `16'hA55A` and `frame_words = MIC_CNT + 1` before the payload words.
- Preserve payload ordering exactly: the first word written into SDRAM for the window is the first payload word exported to UART.
- Provide a reference host script that receives one window packet and stores the raw payload for offline parsing.

**Non-Goals:**
- This change does not implement real-time or continuous streaming.
- This change does not add CRC, checksum, or transport-level integrity guarantees.
- This change does not add a ring buffer, multi-window queue, or overlapping record/read execution.
- This change does not change the packed payload semantics established by `RecordControl` and `RecordPacker`.
- This change does not move UART-specific transport logic into `Sdram.sv`.

## Decisions

### 1. Keep the read FIFO inside `Sdram.sv`

The readback path will add a read-side FIFO wrapper inside `Sdram.sv`, with its write side in the PLL-owned SDRAM clock domain and its read side in the system/UART clock domain.

Why:
- SDRAM read bursts run in the SDRAM domain and should not be paced directly by the slow UART path.
- The FIFO is the natural CDC and elasticity point for moving read payload words out of the SDRAM subsystem.
- This keeps SDRAM-specific timing and clocking concerns contained inside `Sdram.sv`.

Alternative considered:
- Put the read FIFO outside `Sdram.sv`.
- Rejected because it leaks SDRAM-domain timing concerns into the top-level export path.

### 2. Keep the UART sender outside `Sdram.sv`

`Sdram.sv` will expose read payload words as a plain valid/ready stream. The UART sender remains in the system clock domain and is responsible for transport prefix injection and byte serialization.

Why:
- `Sdram.sv` should stop at “memory window becomes a payload stream.”
- The UART path is transport logic, not SDRAM control logic.
- This keeps the SDRAM subsystem reusable if UART is replaced later.

Alternative considered:
- Let `Sdram.sv` own the UART framing and transmission path.
- Rejected because it couples the memory subsystem to one specific output transport.

### 3. Use a fixed two-word UART prefix only

The UART export path will prepend exactly two `16-bit` words before the payload:

- `header = 16'hA55A`
- `frame_words = MIC_CNT + 1`

Neither of these words is stored in SDRAM.

Why:
- The header gives the host a clear window boundary.
- `frame_words` tells the host how to slice each frame without changing the payload itself.
- The window length is fixed by project configuration, so a total-length field is unnecessary for the first version.

Alternative considered:
- Add more transport metadata such as total payload length or CRC.
- Rejected for now because the immediate goal is a minimal end-to-end path, not a generalized transport protocol.

### 4. Preserve the payload exactly as written

The readback path will not reconstruct frames, reformat payload words, or inject transport metadata into SDRAM. Payload words leave SDRAM in the same order they were written during recording.

Why:
- The current packed format is already sufficient for the host to interpret one frame at a time.
- Avoiding in-FPGA payload transformation keeps the readback path small and easy to debug.
- Any richer decoding can happen later on the host without touching the FPGA readback core.

Alternative considered:
- Rebuild frames or add per-frame transport markers in FPGA logic.
- Rejected because it adds unnecessary complexity for the current milestone.

### 5. Serialize the full flow at top level

Top-level control will remain strictly serialized:

```text
IDLE -> RECORD -> READBACK -> UART_SEND -> IDLE
```

The system will not record a new window while exporting the previous one.

Why:
- Only one fixed window is needed.
- Serial execution keeps control logic simple and avoids concurrent access to SDRAM.
- This removes the need for arbitration between write and read traffic in the first readback version.

Alternative considered:
- Allow concurrent recording and export.
- Rejected because it would introduce buffering and arbitration complexity that the current goal does not need.

### 6. Start SDRAM readback inside the SDRAM subsystem once the write path is fully flushed

The handoff from write path to read path will be decided inside the SDRAM subsystem. After the current window has been fully written into SDRAM, `Sdram.sv` will begin the fixed-window readback path without requiring a separate top-level “safe to read” decision.

Why:
- The SDRAM-side logic has the most accurate view of when the current window is fully committed to memory.
- Keeping the write-to-read transition in one subsystem avoids exporting another cross-domain completion handshake just to authorize readback.
- This keeps top-level control focused on the higher-level serialized flow while SDRAM-side control owns its own local safety boundary.

Alternative considered:
- Let top-level logic decide when SDRAM readback is allowed.
- Rejected because top-level logic would need another derived completion signal whose true meaning already belongs inside the SDRAM subsystem.

### 7. Pace SDRAM reads by FIFO space, not UART beats

The read scheduler will issue SDRAM read transactions only when the internal read FIFO has enough free space for the next burst or the final short tail. SDRAM burst progress will not be stalled beat-by-beat by UART backpressure.

Why:
- SDRAM bursts must run according to controller timing once started.
- The read FIFO already provides the correct decoupling layer.
- This keeps the scheduler aligned with the existing write-side architecture.

Alternative considered:
- Bind SDRAM beat issuance directly to UART readiness.
- Rejected because it defeats the purpose of the read FIFO and makes burst handling brittle.

### 8. Let the UART sender start on first payload availability and finish by fixed payload count

The UART sender will treat the first observed payload word from the `Sdram` read stream as the start trigger for one window packet. After that trigger, it shall lock into one window-send session, emit the two prefix words once, then emit payload words until a fixed payload-word counter reaches `WINDOW_LENGTH * frame_words`.

Why:
- The sender only needs one simple external start condition: “payload for one window has begun to appear.”
- The sender must not infer packet completion from FIFO empty transitions, because the read FIFO may temporarily drain and refill while the same window is still in flight.
- A dedicated “sending current window” latch plus a fixed payload counter makes the UART packet boundary deterministic.

Alternative considered:
- End one UART packet when the payload FIFO becomes empty.
- Rejected because FIFO emptiness is only an instantaneous buffering state, not proof that the fixed window payload is complete.

### 9. Freeze UART word byte order as `MSB` then `LSB`

For every `16-bit` prefix or payload word, the UART sender will serialize `word[15:8]` before `word[7:0]`.

Why:
- The user has explicitly frozen this rule.
- It gives the host script one simple, deterministic reassembly rule.

Alternative considered:
- `LSB` first.
- Rejected because it conflicts with the chosen project convention for this export path.

## Risks / Trade-offs

- **[Risk] No transport integrity check is included.** -> Mitigation: keep the protocol intentionally minimal for the first version and rely on a strong header plus fixed-length host capture; add checksum only if real data collection shows it is needed.
- **[Risk] Fixed address `0` and fixed window length prevent back-to-back queued captures.** -> Mitigation: accept this as part of the single-window scope and defer multi-window buffering to a later change.
- **[Risk] UART throughput is much lower than SDRAM throughput.** -> Mitigation: keep the read FIFO inside `Sdram.sv` and schedule read bursts based on FIFO free space instead of UART beat timing.
- **[Risk] The host script depends on local project configuration for `WINDOW_LENGTH`.** -> Mitigation: keep the script intentionally project-specific and use the prefixed `frame_words` field only for frame slicing, not for dynamic protocol negotiation.

## Migration Plan

1. Extend `Sdram.sv` with the read-side FIFO wrapper and system-domain payload stream interface.
2. Add the read scheduler and integrate it with the existing `SdramControl` read channel.
3. Add top-level control that starts readback only after the fixed recording window has completed.
4. Add the UART sender that emits the two prefix words and then drains the payload stream.
5. Add or replace the host capture script so one window can be captured and saved from the serial port.
6. Add read-path benches and UART framing checks, with any actual simulation execution left to human validation.

## Open Questions

- What exact burst-launch threshold should the read scheduler use when the read FIFO depth matches the write FIFO depth?
- Should the host script save the captured window as raw bytes or reconstructed `16-bit` words by default?
