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
