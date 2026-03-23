## ADDED Requirements

### Requirement: UART export shall prepend a fixed two-word transport prefix
The UART export path SHALL prepend two `16-bit` transport words before sending payload data for one completed window. The first prefix word SHALL be `16'hA55A`. The second prefix word SHALL be `MIC_CNT + 1`, representing the number of payload words in one frame.

#### Scenario: Prefix is sent before payload
- **WHEN** one window export starts
- **THEN** the UART sender SHALL transmit `16'hA55A` first, `MIC_CNT + 1` second, and only then begin transmitting payload words

#### Scenario: Prefix is not stored in SDRAM
- **WHEN** the recording window is written into SDRAM
- **THEN** the stored payload SHALL contain only the packed frame words and SHALL NOT contain the UART header or the `frame_words` prefix

### Requirement: UART export shall preserve payload word and byte order
The UART export path SHALL preserve the SDRAM payload ordering exactly. Each `16-bit` word SHALL be serialized as its high byte first and its low byte second.

#### Scenario: Payload word order matches SDRAM read order
- **WHEN** payload words are drained from the `Sdram` read stream
- **THEN** the UART sender SHALL transmit those payload words in the same order without reordering frames or words

#### Scenario: Each word is serialized MSB first
- **WHEN** one prefix word or payload word is transmitted on UART
- **THEN** the UART sender SHALL emit `word[15:8]` before `word[7:0]`

### Requirement: UART sender shall close one packet by fixed payload count
The UART sender SHALL treat the first available payload word as the start trigger for one window packet, and it SHALL remain in that packet until it has transmitted exactly `WINDOW_LENGTH * frame_words` payload words. Temporary payload FIFO emptiness SHALL NOT terminate the packet or retrigger the prefix.

#### Scenario: First payload availability starts one window-send session
- **WHEN** the UART sender is idle and the `Sdram` payload stream first becomes valid for one exported window
- **THEN** the UART sender SHALL enter one active window-send session and SHALL emit the prefix exactly once for that session

#### Scenario: Temporary FIFO drain does not split the window packet
- **WHEN** the UART sender is already in an active window-send session and the payload stream temporarily becomes unavailable before the fixed payload count is reached
- **THEN** the UART sender SHALL wait for later payload words and SHALL NOT restart the prefix or end the packet early

#### Scenario: Fixed payload count ends the window packet
- **WHEN** the UART sender has transmitted exactly `WINDOW_LENGTH * frame_words` payload words for the active session
- **THEN** it SHALL mark the packet complete and return to its idle state

### Requirement: Project shall provide a host capture flow for one fixed window
The project SHALL provide a host-side capture flow that receives one exported window packet, synchronizes on the fixed header, reads the `frame_words` prefix, and captures one fixed payload window for later offline parsing.

#### Scenario: Host script synchronizes on the header
- **WHEN** the host capture script reads bytes from the serial port
- **THEN** it SHALL search for the exported `16'hA55A` header before treating subsequent bytes as a window packet

#### Scenario: Host script slices frames using frame_words
- **WHEN** the host capture script has consumed the second prefix word
- **THEN** it SHALL interpret that word as the number of payload words per frame for later frame slicing

#### Scenario: Host script captures one fixed payload window
- **WHEN** the host capture script begins collecting payload for one window
- **THEN** it SHALL read exactly `WINDOW_LENGTH * frame_words` payload words and save that window for later offline parsing
