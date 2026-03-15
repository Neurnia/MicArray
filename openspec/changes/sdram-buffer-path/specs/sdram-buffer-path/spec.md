## ADDED Requirements

### Requirement: SDRAM buffer architecture shall separate scheduling from SDRAM transaction execution
The system SHALL separate SDRAM scheduling policy from SDRAM chip-level transaction execution. Upper-layer schedulers SHALL decide when to issue transactions, while `SdramControl` SHALL execute SDRAM commands, timing, refresh, and address translation.

#### Scenario: Write scheduler owns burst policy
- **WHEN** the write path decides whether enough data is buffered to start a burst or flush a tail
- **THEN** that decision SHALL be made outside `SdramControl`

#### Scenario: Controller owns chip protocol
- **WHEN** a transaction is issued to `SdramControl`
- **THEN** `SdramControl` SHALL perform the SDRAM initialization, refresh, activate, read/write, and precharge behavior required to execute that transaction

### Requirement: SDRAM control boundary shall use separate command and data channels
`SdramControl` SHALL expose a lightweight transaction boundary with a command channel and separate data channels for write input and read output.

#### Scenario: Command channel starts a transaction
- **WHEN** an upper-layer scheduler starts a transaction
- **THEN** it SHALL provide transaction direction, starting linear word address, and transaction length through the command channel

#### Scenario: Write data flows independently from command acceptance
- **WHEN** a write transaction is active
- **THEN** write payload words SHALL be transferred through a dedicated write-data channel beat by beat

#### Scenario: Read data boundary is reserved for future readback
- **WHEN** a future read scheduler is added
- **THEN** it SHALL receive returned payload words through a dedicated read-data channel without changing the controller boundary

### Requirement: Write scheduler shall consume the packed record stream without another burst buffer
The write scheduler SHALL consume the `16-bit` packed stream from `RecordWrFifo` in the SDRAM clock domain without requiring an additional burst-sized staging buffer outside the existing FIFO.

#### Scenario: FIFO stream feeds write data channel
- **WHEN** `RecordWrFifo` presents valid write data in the SDRAM clock domain
- **THEN** the write scheduler SHALL forward that stream into the controller write-data channel

#### Scenario: FIFO advances only on accepted write beats
- **WHEN** the controller accepts one write beat
- **THEN** the write scheduler SHALL advance the FIFO stream by exactly one `16-bit` word

### Requirement: SDRAM transactions shall use linear `16-bit` word addresses
Upper-layer schedulers SHALL track buffer progress using linear `16-bit` word addresses, and `SdramControl` SHALL translate those addresses into SDRAM bank, row, and column fields internally.

#### Scenario: Sequential bursts advance linearly
- **WHEN** a write burst of length `N` completes successfully
- **THEN** the next sequential write burst SHALL start at the previous linear word address plus `N`

#### Scenario: Controller translates chip address fields internally
- **WHEN** `SdramControl` executes a transaction
- **THEN** it SHALL derive SDRAM bank, row, and column values from the supplied linear word address internally

### Requirement: The first write path shall support standard bursts and final tail flushes
The write scheduler SHALL start standard write bursts once FIFO fill level reaches the configured threshold and SHALL flush the remaining words after `window_done` even when fewer than the standard burst length remain.

#### Scenario: Scheduler starts a standard burst when FIFO reaches threshold
- **WHEN** FIFO fill level is greater than or equal to the configured standard burst length
- **THEN** the write scheduler SHALL issue a write command whose length matches that standard burst length

#### Scenario: Scheduler flushes a final short burst
- **WHEN** `window_done` is asserted and FIFO still contains unwritten data fewer than the standard burst length
- **THEN** the write scheduler SHALL issue a final write command whose length matches the remaining FIFO word count

### Requirement: SDRAM control logic shall remain internally partitioned by responsibility
The first SDRAM buffer-path implementation SHALL keep `SdramControl` internally partitioned into state/timing control, command generation, and data-bus handling.

#### Scenario: Controller hierarchy exposes distinct responsibilities
- **WHEN** the SDRAM buffer path is implemented
- **THEN** the controller hierarchy SHALL include `SdramCore` for timing/state control, `SdramCmd` for SDRAM command/address output generation, and `SdramData` for DQ bus handling
