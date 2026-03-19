## 1. Interface And Architecture Freeze

- [x] 1.1 Define the lightweight `SdramControl` transaction boundary in HDL comments and module ports, covering the command channel plus separate write-data and read-data channels
- [x] 1.2 Document that `SdramFifoCtrl` is a write scheduler and that future read scheduling will remain outside `SdramControl`
- [x] 1.3 Document the linear `16-bit` word-address convention at the scheduler-controller boundary
- [x] 1.4 Document that `Sdram.sv` owns the PLL-generated SDRAM clock domain and that `RecordWrFifo` remains the CDC boundary into that domain

## 2. Write Scheduler

- [x] 2.1 Implement `SdramFifoCtrl` against the current `RecordWrFifo` outputs for data, valid, level, and `window_done`
- [x] 2.2 Implement standard-burst launch logic once FIFO fill level reaches the configured threshold
- [x] 2.3 Implement final short-burst flush behavior after `window_done`
- [x] 2.4 Implement sequential write-address tracking across consecutive bursts
- [x] 2.5 Stream FIFO payload words into the controller write-data channel without adding another burst-sized staging buffer

## 3. SDRAM Controller Write-First Core

- [x] 3.1 Implement `SdramControl` top-level ports around the lightweight transaction interface while reserving the future read-data side
- [x] 3.2 Implement `SdramCore` state sequencing for the datasheet-compliant initialization flow, refresh arbitration, activate, and write-with-auto-precharge within a single-transaction controller flow
- [x] 3.3 Implement SDRAM command/address generation inside `SdramCore`, including internal linear-address translation to SDRAM bank/row/column fields and `DQM` generation for masked tail beats
- [x] 3.4 Freeze and implement the internal write-burst control semantics so `wr_phase` spans the full physical burst window while `wr_beat` and `wr_beat_fire` apply only to logical payload beats
- [x] 3.5 Implement `SdramData` write-side DQ driving and tri-state behavior for accepted write beats while preserving the module boundary needed for future reads
- [x] 3.6 Add the first PLL-generated SDRAM clock domain under `Sdram.sv` and connect the SDRAM-side FIFO read path, scheduler, controller, and chip clock output to it

## 4. Verification And Integration Preparation

- [x] 4.1 Add a self-checking simulation bench for `SdramFifoCtrl` covering standard bursts and final short-burst flushes
- [x] 4.2 Add a write-path SDRAM controller bench using an SDRAM model to verify initialization and burst writes through the new transaction boundary
- [x] 4.3 Integrate the write path into `Sdram.sv` and `MicArrayTop.sv` once the scheduler and controller benches pass
