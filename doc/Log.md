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

A GREAT PROGRESS!


