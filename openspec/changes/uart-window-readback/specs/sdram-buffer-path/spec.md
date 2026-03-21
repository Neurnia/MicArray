## ADDED Requirements

### Requirement: SDRAM subsystem shall read back one fixed window through an internal read FIFO
The SDRAM subsystem SHALL support reading one completed recording window from linear word address `0` after the record phase finishes. The returned payload words SHALL be buffered inside `Sdram.sv` by a read FIFO wrapper that crosses from the PLL-owned SDRAM clock domain back to the system/UART clock domain.

#### Scenario: SDRAM subsystem starts readback only after the write path is fully flushed
- **WHEN** the current recording window has finished propagating through the write path and has been fully committed into SDRAM
- **THEN** the SDRAM subsystem SHALL begin the fixed-window readback phase from within `Sdram.sv` without requiring a separate top-level authorization signal for write safety

#### Scenario: Readback starts from the fixed window base
- **WHEN** top-level control starts readback for the completed window
- **THEN** the SDRAM subsystem SHALL begin issuing read transactions from linear word address `0`

#### Scenario: Readback targets the fixed payload size
- **WHEN** one export operation is started
- **THEN** the SDRAM subsystem SHALL read exactly `WINDOW_LENGTH * (MIC_CNT + 1)` payload words for that window

#### Scenario: Read FIFO buffers SDRAM-domain return data
- **WHEN** `SdramControl` returns read payload beats in the SDRAM clock domain
- **THEN** `Sdram.sv` SHALL enqueue those payload words into its internal read FIFO wrapper before exposing them to the system domain

#### Scenario: System domain consumes a payload stream
- **WHEN** the UART-side logic is ready to transmit payload words
- **THEN** the SDRAM subsystem SHALL expose the internal read FIFO contents as a `16-bit` valid/ready stream outside `Sdram.sv`

### Requirement: Read scheduler shall pace SDRAM bursts against FIFO space
The SDRAM read scheduler SHALL launch read transactions according to available free space in the internal read FIFO, rather than according to UART beat timing.

#### Scenario: Scheduler waits for free FIFO space
- **WHEN** the internal read FIFO does not have enough free entries for the next standard read burst
- **THEN** the read scheduler SHALL delay issuing that burst until sufficient free space is available

#### Scenario: Scheduler issues standard read bursts while window data remains
- **WHEN** enough unread payload words remain and the internal read FIFO has enough free space for a full standard burst
- **THEN** the read scheduler SHALL issue a read transaction whose logical length matches that standard burst length

#### Scenario: Scheduler issues a final short read burst
- **WHEN** fewer payload words remain than the standard burst length
- **THEN** the read scheduler SHALL issue one final read transaction whose logical length matches the remaining unread payload word count
