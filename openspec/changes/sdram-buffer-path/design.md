## Context

The MicArray project already has a stable microphone frontend, frame-level record control, frame packing, and a write-side CDC FIFO. The missing layer is the SDRAM buffer path that can store captured windows before they are exported through the much slower UART link.

The current write-side record stream has several important properties:

1. `RecordPacker` emits a serialized `16-bit` word stream.
2. `RecordWrFifo` is already the only clock-domain crossing and elasticity boundary between the record layer and the SDRAM layer.
3. The project still needs a future readback path so stored data can later be fetched from SDRAM and sent to the PC over UART.

This means the immediate implementation target is the write path, but the SDRAM control boundary cannot be designed as a write-only dead end. The controller must execute write transactions now while keeping a clean path for future read transactions.

## Goals / Non-Goals

**Goals:**
- Define an SDRAM buffer architecture whose first implementation writes captured data from `RecordWrFifo` into SDRAM.
- Keep `SdramFifoCtrl` responsible for write scheduling only: burst launch policy, write-address progression, and final tail flush behavior.
- Keep `SdramControl` responsible for SDRAM chip-level transaction execution only: initialization, refresh, activate, write, read, precharge, and address translation.
- Use a lightweight transaction boundary with separate command, write-data, and read-data channels so future readback can be added without redesigning the controller interface.
- Preserve a streaming data path so the write scheduler does not need a second burst-sized staging buffer beyond `RecordWrFifo`.

**Non-Goals:**
- This change does not implement the read scheduler or the UART export path.
- This change does not implement a multi-master, AXI, or Wishbone SDRAM subsystem.
- This change does not finalize PLL generation or board-level phase-shifted SDRAM clocks.
- This change does not change the semantics of `MicFrontend`, `RecordControl`, `RecordPacker`, or `RecordWrFifo` beyond interface alignment with the SDRAM layer.

## Decisions

### 1. Treat `RecordWrFifo` as the only write-side buffer

`RecordWrFifo` remains the only CDC and buffering boundary between the record layer and the SDRAM layer. The write scheduler consumes the FIFO stream directly instead of introducing another burst-sized buffer.

Why:
- The FIFO already provides the needed elasticity between frame-oriented capture and SDRAM burst timing.
- A second burst buffer would duplicate storage responsibility and make the write path harder to reason about.

Alternative considered:
- Add a burst-sized staging buffer inside `SdramFifoCtrl` or `SdramControl`.
- Rejected because it complicates the architecture without solving a missing problem in the current pipeline.

### 2. Make `SdramControl` a transaction executor, not a scheduler

`SdramControl` owns SDRAM protocol execution, timing, refresh, and address translation. Scheduling policies stay outside the controller.

Why:
- The write scheduler already has the FIFO context needed to decide when to launch a burst.
- A future read scheduler will need its own policy for when and how much data to fetch for UART export.
- Keeping policy outside the controller makes `SdramControl` reusable by both write and read paths.

Alternative considered:
- Let `SdramControl` inspect FIFO state and own burst policy directly.
- Rejected because it would bind controller internals to the record pipeline and make future readback integration much harder.

### 3. Use a lightweight transaction interface with separate command, write-data, and read-data channels

The controller boundary will separate:

- a command channel for transaction start, address, length, and direction
- a write-data channel for per-beat write input
- a read-data channel for per-beat read output

The first implementation may only exercise the write command and write-data sides, but the controller boundary will be defined around both write and future read traffic.

Why:
- It keeps command flow distinct from per-beat data flow.
- It avoids overloading a single `req/ack` pair with both transaction acceptance and data acceptance semantics.
- It provides a natural place for future readback without forcing a controller redesign.

Alternative considered:
- Use a smaller private write-only interface such as `wr_req/wr_addr/wr_burst/wr_ack/wr_data`.
- Rejected because it is convenient for the first write path but becomes awkward once readback is added.

### 4. Keep write data streaming through the scheduler

The write scheduler should not store whole bursts of payload data. Instead, it launches a write transaction and then streams FIFO words to the controller beat by beat as the controller accepts them.

Why:
- The upstream data is already a streaming FIFO source.
- This preserves the existing buffering boundary and minimizes duplicated state.
- It fits the eventual read path model, where the controller will also stream data out beat by beat.

Alternative considered:
- Require the scheduler to gather a full burst locally before issuing the command.
- Rejected because it turns the scheduler into a second storage stage instead of a control module.

### 5. Use linear `16-bit` word addresses at the scheduler-controller boundary

The scheduler tracks progress in a linear word address space. `SdramControl` translates those addresses into SDRAM bank, row, and column fields internally.

Why:
- Linear addressing is simple for schedulers that only care about sequential buffer progress.
- Bank/row/column translation belongs to chip-level control logic rather than policy logic.

Alternative considered:
- Expose bank/row/column directly in the command interface.
- Rejected because it leaks physical SDRAM details into upper-layer scheduling logic.

### 6. Keep the controller hierarchy split into `SdramCore`, `SdramCmd`, and `SdramData`

- `SdramCore` owns the controller state machine, timing counters, refresh arbitration, and transaction progress.
- `SdramCmd` generates SDRAM command and address outputs from controller state.
- `SdramData` handles bidirectional DQ bus behavior and write/read beat data movement.

Why:
- The separation matches the real responsibilities inside an SDR SDRAM controller.
- It keeps future read support localized rather than forcing a monolithic rewrite.

Alternative considered:
- Implement one monolithic `SdramControl`.
- Rejected because the command, timing, and data-bus concerns are easier to verify and extend when separated.

## Risks / Trade-offs

- **[Risk] The controller boundary may still be too narrow for the eventual readback path.** -> Mitigation: define both write-data and read-data channels now, even if only the write side is exercised in this change.
- **[Risk] SDRAM timing constants depend on the final controller clock plan.** -> Mitigation: keep timing values parameterized and freeze the architectural boundary before board-level clock work.
- **[Risk] Final short-burst flushes add scheduler complexity compared with fixed-length bursts only.** -> Mitigation: keep the write scheduler focused on one FIFO source and verify tail flush behavior explicitly.
- **[Risk] UART export later will need its own read-side buffering because UART is much slower than SDRAM.** -> Mitigation: keep read scheduling out of scope for this change, but preserve a streaming read-data boundary so a later read FIFO can be inserted cleanly.

## Migration Plan

1. Freeze the write-first, read-aware SDRAM layer boundaries in OpenSpec.
2. Implement `SdramFifoCtrl` against the current `RecordWrFifo` outputs using the agreed write scheduling policy.
3. Implement the first `SdramControl` hierarchy around the lightweight transaction boundary, with write execution active and read-side structure reserved.
4. Add write-path benches for the scheduler and controller hierarchy.
5. Integrate the write path into `Sdram.sv` and `MicArrayTop.sv`.
6. Add read scheduling and UART export in a follow-up change without redesigning `SdramControl`.

## Open Questions

- What exact command and data channel signal names should be frozen in HDL comments and ports?
- Should the first controller version accept only one outstanding transaction at a time, or should command queuing be considered later?
- What standard burst length gives the best trade-off between simplicity and efficiency on the chosen SDRAM clock?
