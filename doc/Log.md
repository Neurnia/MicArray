# Log for mic array project.

## 2025-08-19

### Planned

- [x] Test if microphone module is functioning and learn the wiring.
    - Tie all grounds together to keep the output stable.
    - Verified the module works.

## 2025-10-18

### Planned

- [x] Pick things up again.
    - Figured out the structure of AD7606 chip for ADC module.
    - Initialized the git repo.

## 2025-10-21

### Planned

- [ ] Wire ADC module, microphone module and FPGA module.
    - Work still in progress.
    - Connected ADC digital inputs to the FPGA but still no activity on the `busy` pin.
- [ ] Figure out the correct voltage for data transmissions between FPGA and ADC.
    - Haven’t started this task yet.

### Additional
- Worked out the theoretical sequence to trigger the ADC, but the FPGA can’t make it fire yet.
- Dropped in a prototype with two HDL modules for the bring-up test.

## 2025-10-22

### Planned

- [x] Confirm there is anything output from `convst A/B` pin.
    - Assigned pins to the system clock to make the code work.
- [x] Test if there is signal output from `busy` pin.
    - There isn't. The problem is from FPGA's output. The digital signals to ADC is incorrect.
- [ ] Wire ADC module and FPGA module.
    - Haven't started this task yet.

## 2025-10-25

### Planned

- [x] Test if there is signal output from `busy` pin.
    - Confirmed a clean BUSY pulse train after removing the unintended RESET strap.
    - Root cause: tying RESET to an FPGA pin left it parked high, which held the AD7606 in reset and suppressed BUSY; releasing the line (or holding RESET low) lets conversions run normally.

NOTE: A GREAT PROGRESS!

- [x] Test the communication between pc and FPGA.
    - confirmed that it is able to use UART link to communicate.

## 2025-10-28

### Planned

- [x] Test the level translator.
    - Verified the TXS0108E shifts BUSY from ~4 V down to a clean 3.3 V.
- [x] Test the loop in ADC (use the signal from `busy` to trigger the next `convst`)
    - The BUSY-driven conversion loop now runs end-to-end; FRSTDATA responds as expected and control timing looks healthy on the scope.

## 2025-11-07

NOTE: Transitioned the project from the analog AD7606 front end to digital INMP441 microphones; repository structure and docs now reflect the new architecture.

### Planned

- [x] Update documentation and reorganize legacy files.
- [ ] Research how to drive the new digital microphone interface.
    - The microphone board has only six wires: L/R, WS, SCK, SD, VDD, GND.

## 2025-11-12

### Planned

- [x] Research how to drive the new digital microphone interface.
    - Captured valid SCK/WS waveforms and confirmed, via the scope, that the INMP441 actively drives SD once clocks are present.
    - Added FPGA modules that generate the I²S clocks, deserialize the serial SD stream into 24-bit words (shift registers aligned to the I²S frame), and decimate the samples (currently forwarding every 8th word).
- [x] Deliver data from the FPGA to PC.
    - Streamed captured samples over the on-board USB-UART with simple framing.
    - Verified data reception on the PC via a serial terminal; next step is a live viewer.

### Additional

- INMP441 outputs 24-bit two's-complement samples (I²S framing, MSB first); our current UART test forwards only the upper 16 bits of every 8th sample with a frame header (`0xA5`) and newline terminator for easy parsing.
- The raw data rate is still much higher than the UART can sustain; if we want continuous full-bandwidth streaming we’ll need a faster link (e.g., HDMI, USB FIFO, or on-board SDRAM buffer with bulk readout).

## 2025-11-20

### Planned

- [ ] Research how to get real-time data from the microphone on PC.
    - Observed continuous UART frames (~42k) with minimal drops, but samples still decode to 0 even though `sample_valid` fires; tried right-channel select and added a POR reset—no change in the PC viewer. Next: verify the mic LR strap vs. `CHANNEL_SELECT`, and tap full `sample_data[0..23]` in SignalTap to confirm non-zero bits.

### Additional

- Consider lowering the mic sample rate to ~16 kHz and raising the UART baud to 921,600 so the capture rate stays below the UART link; buffer with FIFO if needed to avoid loss.

## 2025-11-26

### Planned

- [ ] Lower the mic sample rate and validate real-time capture over UART to isolate the issue.
    - Still seeing drops; suspected root cause is inter-module handshake/timing, not the raw rate.
- [ ] Extract raw PCM data from the FPGA for inspection.
    - Pending; plan is to capture framed bytes and decode offline.

## 2025-12-09

### Planned

- [x] Switch from real-time probe to a fixed window (5 s capture) to make transmit async and predictable.
- [x] Replace the split UART chain with an integrated framed TX (fractional baud) to remove handshake slips.
    - Verified end-to-end: FIFO + framed TX + PC listener now plays back the recorded audio from the mic.

NOTE: A GREAT PROGRESS! Single-mic path works end-to-end; next step is the full mic array.

## 2025-12-10

### Planned
- [ ] Shorten the capture window to 1 s and increase FIFO depth (ADDR_WIDTH → 14/15) so the full window fits without overflow.
- [ ] Swap the hand-written FIFO for a Quartus IP core to improve robustness.
- [ ] Bring up dual-mic capture on shared BCLK/WS; instantiate two I2sCapture blocks (SD0/SD1).
- [ ] Extend the UART frame to include ch_id (e.g., A5, ch, D23..16, D15..8, D7..0, 0A) and update the PC script to demux per-channel data.
- [ ] Validate 1 s dual-channel recording over UART (offline playback), checking channel alignment and FIFO usage.

---

## 2026-03-07

NOTE: Started migrating active I2S-related modules and testbenches from Verilog to SystemVerilog.

### Planned
- [x] Rewrite I2S capture files.
- [x] Write Test bench for capture files (ModelSim).

## 2026-03-08

### Planned
- [x] Rewrite and test I2s clock generation module.
- [x] Test all I2s related modules.

## 2026-03-09

### Planned
- [x] Rearrange the simulation-related project structure (`sim/`, `scripts/`, and `modelsim/`).
- [x] Write ModelSim `.do` scripts for all active I2S test benches.
- [x] Come up with a new procedure.
    - Instead of capturing and sending the data simultaneously, we now use a SDRAM to store the data first and then send it to pc.
    - Format the data before storage.
    - For data formatting and storing, we plan to use three modules: `FrameCollect` to format, `RecordControl` to record frame related information and control record windows, `SdramWrite` to write to SDRAM.
- [x] Implement and test `FrameCollect` module. (ModelSim)

## 2026-03-11

### Planned
- [x] Clarify duty of modules.
    - `RecordControl` handles the whole process of recording, collecting data (and some metadata of frames) and committing them downstream.
    - `SdramWrite` receive data from `RecordControl` and store it inside a FIFO. This help keep SDRAM writing process separate from the frames.
- [x] Finish writing and testing `RecordControl` module.

## 2026-03-12

### Planned
- [x] Investigate into Quartus official IP cores.
    - There is no SDRAM controller IP core.
    - Data width and depth of FIFO IP core is fixed, which means all data must be serialized first before storage.
- [x] Come up with a new structure.
    - Separate modules into three layers. 
    - First is `MicFrontend`, whose duty is to convert multiple raw I2S microphone streams into frame-aligned multi-channel samples. This is what we have already done, including `I2sClockGen`, `I2sCapture` x microphone number and `FrameCollect`. We have already finished this part.
    - Second is record control layer. Here we don't plan to make a wrapper module. The layer includes `RecordControl`, recording windows based on frames (the frames are generated from ws in `I2sClockGen`), `RecordPacker`, converting a parallel frame produced by `RecordControl` into a fixed-width sequential data stream and `RecordWrFifo`, using FIFO to decouple upstream "frames" and downstream SDRAM burst writes.
    - Third is `Sdram`. It should provide a simplified memory interface to the upper layers while connecting to the actual SDRAM controller and chip pins. This layer includes `SdramFifoCtrl` and `SdramControl`. `SdramFifoCtrl` translates FIFO states into SDRAM controller requests. `SdramControl` is the actual SDRAM controller, responsible for implementing the SDRAM chip-level protocol.
- [x] Clarify the structure inside `SdramControl`.
    - `SdramCore`, maintains the controller state machine and determines which operational phase the system is currently in.
    - `SdramCmd`, translates the controller state from `SdramCore` into actual SDRAM command signals.
    - `SdramData`, responsible for handling the bidirectional DQ data bus.

## 2026-03-14

### Planned
- [x] Finish writing `RecordPacker` module and following test bench.

## 2026-03-15

### Planned
- [x] Write and test `RecordWrFifo` module.  
    - Learned some basic knowledge about CDC (clock domain crossing) and IP cores.

## 2026-03-16

### Planned
- [x] Write `SdramFifoCtrl` module.
    - Rethought the whole structure of the prototype we are currently working on. Decided to take reading path into account when implementing `SdramControl` module later.

## 2026-03-17

### Planned
- [x] Specify the interface of `SdramControl` module and its submodules.
    - Deleted `SdramCmd` module. `SdramCore` module will handle all of its duty.
    - Specified that inside the SDRAM module data flow should be separate from command flow.
    - Decided to add a PLL to SDRAM module.

## 2026-03-19

### Planned
- [x] Finish `SdramControl` module.
    - Decide to add a PLL wrapper inside Sdram domain.

## 2026-03-20

### Planned
- [ ] Plan the read path.

### Additional
- Changed the names of modules to make the project easier to comprehend.

## 2026-03-21

### Planned
- [x] Continue to plan the read path.
    - Came up with three modules: `SdramRdCtrl` (Sdram domain), `SdramRdFifo` and `UartSender`.
        - `SdramRdCtrl` is responsible for data extraction from Sdram. The interface should be aligned with `SdramWrCtrl`.
        - `SdramRdFifo` is FIFO IP core wrapper.
        - `UartSender` handles the FPGA-PC data flow.
    - Interfaces in `SdramControl` should be changed accordingly.
    - Need future arbiter implementation in SDRAM top.

## 2026-03-22

### Planned
- [x] Write `SdramRdCtrl` module.
- [x] Write `SdramRdFifo` module.

### Additional
- Finished all modules planned and rewrote the py script.

## 2026-03-22

### Planned
- [x] Test if current design works on real board.
    - Reset the capture length to 24 bits in I2S domain. The data would be truncated later.
    - Fixed a lost-signal bug in frame_error capturing in `RecordControl` module.
    - fixed the SDRAM read back pressure bug.

## 2026-04-07

### Planned
- [x] Expand the system into 32 channels.
    - Successfully obtained a 10s-long data in 32 channels.