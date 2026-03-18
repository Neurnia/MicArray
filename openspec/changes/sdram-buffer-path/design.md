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
- Move the SDRAM-side logic onto a dedicated PLL-generated clock domain owned by `Sdram.sv`, rather than trying to execute the SDRAM path directly on the 50 MHz system clock.
- Use a lightweight transaction boundary with separate command, write-data, and read-data channels so future readback can be added without redesigning the controller interface.
- Preserve a streaming data path so the write scheduler does not need a second burst-sized staging buffer beyond `RecordWrFifo`.

**Non-Goals:**
- This change does not implement the read scheduler or the UART export path.
- This change does not implement a multi-master, AXI, or Wishbone SDRAM subsystem.
- This change does not finalize board-level SDRAM clock phase tuning beyond what is needed to bring up the first PLL-based SDRAM clock domain.
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

### 6. Keep the first controller hierarchy split into `SdramCore` and `SdramData`

- `SdramCore` owns the controller state machine, timing counters, refresh arbitration, transaction progress, and SDRAM command/address generation.
- `SdramData` handles bidirectional DQ bus behavior and write/read beat data movement.

Why:
- Open-source SDR SDRAM controllers more commonly keep state progression and command/address generation together in one controller core.
- The command-generation logic is tightly coupled to controller state and wait-counter progression, so splitting it out too early would create an unnecessary internal protocol.
- Separating `SdramData` still preserves a clean boundary around the bidirectional DQ bus, which is the most distinct hardware-facing concern.

Alternative considered:
- Split the controller into `SdramCore`, `SdramCmd`, and `SdramData`.
- Rejected for the first implementation because it adds interface overhead between internal modules without enough benefit at the current controller complexity.

Alternative considered:
- Implement one monolithic `SdramControl`.
- Rejected because the data-bus handling and tristate behavior are still easier to reason about when `SdramData` remains separate.

### 7. Put PLL-owned SDRAM clocking inside `Sdram.sv`

`Sdram.sv` owns the PLL that generates the SDRAM-side clock domain. The 50 MHz project clock remains the record-side/system clock, while the SDRAM-side FIFO read interface, `SdramFifoCtrl`, and `SdramControl` run in the PLL-generated SDRAM domain. The SDRAM chip clock output is also derived inside the SDRAM subsystem rather than exposed as a top-level clock-planning concern.

Why:
- `RecordWrFifo` is already the explicit CDC boundary between the record path and the SDRAM path.
- The SDRAM controller should be timed against the SDRAM-domain clock it actually uses, not the unrelated 50 MHz system clock.
- Keeping the PLL inside `Sdram.sv` contains SDRAM-specific clocking concerns inside the SDRAM subsystem.

Alternative considered:
- Keep the SDRAM path on the 50 MHz system clock.
- Rejected because the project already intends to cross into an SDRAM-specific clock domain and a slower direct-system-clock design would make the final controller clock plan harder to evolve.

Alternative considered:
- Put the PLL at `MicArrayTop` and distribute the SDRAM clocks from the project root.
- Rejected for this change because the PLL is currently only a dependency of the SDRAM subsystem and does not yet justify a project-wide clock manager.

### 8. Keep the first `SdramControl` as a single-transaction executor with a minimal execution flow

The first controller version accepts at most one transaction at a time. After initialization, it stays in `IDLE` until either refresh must be serviced or one command transaction is accepted. Once a command is accepted, the controller follows the execution path implied by the command's write/read flag and does not accept another command until that path returns to `IDLE`.

Minimal control flow:

```text
INIT
  ->
IDLE
  -> if refresh_due         -> REFRESH
  -> if cmd_fire && we=1    -> ACTIVATE -> WRITE -> PRECHARGE -> IDLE
  -> if cmd_fire && we=0    -> ACTIVATE -> READ  -> PRECHARGE -> IDLE
```

Where:
- `cmd_fire` means the controller has accepted one transaction header from the command channel.
- `we=1` selects the write execution path and `we=0` selects the read execution path.
- The controller remains busy until the selected path completes and returns to `IDLE`.

Why:
- It matches the current project scope, which only needs one write-side scheduler and does not yet need command queuing.
- It keeps refresh handling explicit without mixing scheduler policy into the controller.
- It leaves a clean insertion point for a future read scheduler without redesigning the controller boundary.

Alternative considered:
- Add a command queue or accept a second transaction before the first completes.
- Rejected because it would add arbitration and transaction-tracking complexity before the first write path is proven.

### 9. Terminate command flow in `SdramCore` and payload flow in `SdramData`

Inside `SdramControl`, the command channel terminates at `SdramCore`, while the write-data and read-data payload channels terminate at `SdramData`. `SdramCore` remains responsible for transaction lifetime, timing, and SDRAM protocol progression, but it should drive `SdramData` only with phase-level control instead of sitting directly in the payload path.

In practice, this means:

- `cmd_*` is consumed by `SdramCore`
- `wr_*` and `rd_*` are exposed at the `SdramControl` boundary and terminate in `SdramData`
- `SdramCore` tells `SdramData` when write beats or read beats are legal, but `wr_data` and `rd_data` themselves do not pass through `SdramCore`

For the first implementation, the internal `SdramCore` -> `SdramData` control should be understood in two layers:

- `*_phase` indicates that the controller is currently in the corresponding data phase
- `*_beat` indicates that one beat shall be executed in the current cycle
- `*_beat_fire` indicates that the requested beat completed successfully in that cycle

This keeps beat-level progress explicit without routing the payload path itself through `SdramCore`.

Why:
- It keeps the controller core focused on state, counters, refresh, and chip command progression.
- It prevents the data module from owning transaction policy while still keeping the payload path out of the core.
- It matches the hardware distinction between SDRAM command sequencing and bidirectional DQ bus handling.

Alternative considered:
- Route write/read payload data and ready/valid handshakes directly through `SdramCore`.
- Rejected because it makes the core look like part of the data path rather than the transaction/timing controller.

Alternative considered:
- Let `SdramData` infer transaction progress and own payload timing by itself.
- Rejected because it would duplicate controller state and split transaction lifetime across two modules.

## Risks / Trade-offs

- **[Risk] The controller boundary may still be too narrow for the eventual readback path.** -> Mitigation: define both write-data and read-data channels now, even if only the write side is exercised in this change.
- **[Risk] The first PLL-generated SDRAM clock plan may still need board-specific phase tuning.** -> Mitigation: include PLL ownership and SDRAM-domain integration in this change, but keep the exact phase relationship parameterized and avoid overcommitting the first implementation to a final board-level timing choice.
- **[Risk] Final short-burst flushes add scheduler complexity compared with fixed-length bursts only.** -> Mitigation: keep the write scheduler focused on one FIFO source and verify tail flush behavior explicitly.
- **[Risk] UART export later will need its own read-side buffering because UART is much slower than SDRAM.** -> Mitigation: keep read scheduling out of scope for this change, but preserve a streaming read-data boundary so a later read FIFO can be inserted cleanly.

## Migration Plan

1. Freeze the write-first, read-aware SDRAM layer boundaries in OpenSpec.
2. Implement `SdramFifoCtrl` against the current `RecordWrFifo` outputs using the agreed write scheduling policy.
3. Add the first PLL-owned SDRAM clock domain under `Sdram.sv` and connect the SDRAM-side FIFO read path, scheduler, controller, and chip clock output to it.
4. Implement the first `SdramControl` hierarchy around the lightweight transaction boundary, with `SdramCore` handling state/timing/command generation and `SdramData` handling DQ behavior.
5. Add write-path benches for the scheduler and controller hierarchy.
6. Integrate the write path into `Sdram.sv` and `MicArrayTop.sv`.
7. Add read scheduling and UART export in a follow-up change without redesigning `SdramControl`.

## Open Questions

- What exact command and data channel signal names should be frozen in HDL comments and ports?
- What standard burst length gives the best trade-off between simplicity and efficiency on the chosen SDRAM clock?
