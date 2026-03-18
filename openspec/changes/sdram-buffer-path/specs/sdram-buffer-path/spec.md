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

### Requirement: The SDRAM subsystem shall own a dedicated PLL-generated SDRAM clock domain
The SDRAM subsystem SHALL run on a dedicated PLL-generated SDRAM clock domain rather than executing the SDRAM path directly on the 50 MHz system clock. `RecordWrFifo` SHALL remain the CDC boundary into that domain.

#### Scenario: SDRAM-side logic runs in the SDRAM clock domain
- **WHEN** the first SDRAM buffer path is integrated
- **THEN** the FIFO read side, `SdramFifoCtrl`, and `SdramControl` SHALL operate in the PLL-generated SDRAM clock domain

#### Scenario: SDRAM chip clock is owned by the SDRAM subsystem
- **WHEN** the SDRAM subsystem drives the external SDRAM chip
- **THEN** the SDRAM chip clock output SHALL be derived inside the SDRAM subsystem from the same PLL-owned clock plan

### Requirement: The first `SdramControl` implementation shall execute one transaction at a time
The first `SdramControl` implementation SHALL behave as a single-transaction executor. It SHALL accept at most one command transaction at a time, execute the SDRAM flow required for that transaction, and only then become able to accept the next command transaction.

#### Scenario: Controller accepts one command only while idle
- **WHEN** `SdramControl` is in its idle command-accepting state and one command transaction is handshaken
- **THEN** it SHALL latch that transaction and stop accepting additional command transactions until the current transaction completes

#### Scenario: Write transaction follows chip-level write flow
- **WHEN** the accepted transaction is marked as a write
- **THEN** `SdramControl` SHALL perform the SDRAM activation, write, and precharge behavior needed to complete that write transaction before accepting a new command transaction

#### Scenario: Read transaction follows chip-level read flow
- **WHEN** the accepted transaction is marked as a read
- **THEN** `SdramControl` SHALL perform the SDRAM activation, read, and precharge behavior needed to complete that read transaction before accepting a new command transaction

#### Scenario: Refresh is serviced between transactions
- **WHEN** refresh becomes due while no transaction is active
- **THEN** `SdramControl` SHALL service refresh before accepting or starting the next transaction

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
The first SDRAM buffer-path implementation SHALL keep `SdramControl` internally partitioned so that controller-state/timing/command generation remain separate from bidirectional data-bus handling.

#### Scenario: Controller hierarchy exposes distinct responsibilities
- **WHEN** the SDRAM buffer path is implemented
- **THEN** the controller hierarchy SHALL include `SdramCore` for timing/state control and SDRAM command/address generation, and `SdramData` for DQ bus handling

#### Scenario: Command and payload paths terminate in different internal modules
- **WHEN** `SdramControl` receives command traffic and write/read payload traffic
- **THEN** command acceptance and transaction progression SHALL terminate in `SdramCore`, while write-data and read-data payload movement SHALL terminate in `SdramData`

#### Scenario: Data-path timing remains controlled by the core
- **WHEN** `SdramData` accepts write beats or presents read beats
- **THEN** those payload transfers SHALL occur only under phase/timing control from `SdramCore`, rather than from transaction state inferred independently inside `SdramData`

#### Scenario: Payload progress advances on completed beats
- **WHEN** the controller is executing a write-data phase or read-data phase
- **THEN** progress through that phase SHALL advance based on explicitly completed payload beats, rather than on payload data being routed through `SdramCore`
