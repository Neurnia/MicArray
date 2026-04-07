## ADDED Requirements

### Requirement: UART receiver shall start one recording window from ASCII `START\n`
The system SHALL provide a UART receive path in the system clock domain that recognizes the exact ASCII command `START\n` and emits one record-start pulse for the existing capture path.

#### Scenario: Exact command starts recording
- **WHEN** the system is idle and the UART receive path receives the exact byte sequence `S`, `T`, `A`, `R`, `T`, `\n`
- **THEN** the receiver SHALL emit one `start_record` pulse that can start one recording window

#### Scenario: Non-matching input does not start recording
- **WHEN** the UART receive path receives any byte sequence other than the exact ASCII command `START\n`
- **THEN** the receiver SHALL NOT emit a record-start pulse

### Requirement: UART receiver shall discard commands while export is busy
The UART receive path SHALL treat `uart_busy` as a hard ignore condition. While `uart_busy` is asserted, received bytes SHALL be discarded and partial command-match state SHALL be cleared.

#### Scenario: Busy-time command is dropped
- **WHEN** the UART receive path receives the exact ASCII command `START\n` while `uart_busy` is asserted
- **THEN** the receiver SHALL NOT emit a record-start pulse for that command

#### Scenario: Partial command does not survive a busy interval
- **WHEN** a partial `START\n` command is in progress and `uart_busy` becomes asserted before the command completes
- **THEN** the receiver SHALL clear its partial match state and SHALL require a new full `START\n` command after `uart_busy` is deasserted

### Requirement: Top-level record control shall use UART input as the active start source
The top-level integration SHALL derive the active record-start control from the UART receiver output rather than from the push-button path.

#### Scenario: UART receiver drives record start
- **WHEN** the top-level integration instantiates the recording pipeline
- **THEN** it SHALL connect the UART receiver start pulse to the existing record-start input used by `RecordControl`

#### Scenario: Push button is not an active trigger source
- **WHEN** the top-level integration is built for this change
- **THEN** the push button SHALL NOT act as a parallel active trigger for starting a recording window
