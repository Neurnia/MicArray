# MicArray

MicArray is an FPGA-based microphone array platform built around Intel FPGAs and the Quartus Prime toolchain. The project explores multi-channel audio capture, beamforming, and supporting digital signal processing blocks.

## Project aim

Given a sound source with known characteristics and a cluster of microphones, the goal is to ingest the per-microphone signals on the FPGA, treat one microphone as the reference, and compute the relative positions of the remaining microphones. By measuring the time differences of arrival (TDOA) between the reference channel and every other channel, we can infer the geometry of the array and track any drift in microphone placement.

## Repository layout

```
MicArray/
├── constraints/  # Board-level pin assignments and timing constraints
├── doc/          # Project documentation and progress logs
├── hdl/          # Synthesizable HDL sources for the array
├── openspec/     # Spec-driven development plans powered by Openspec
├── quartus/      # Quartus project files (.qpf/.qsf) and custom IP metadata
├── scripts/      # Utility scripts used during development
└── sim/          # Testbenches and simulation assets
```

## Toolchain

- **FPGA vendor tools:** Intel Quartus Prime Lite 20.1.x (project files live in `quartus/`).
- **Simulation:** ModelSim/Questa-style testbenches live in `sim/`, and helper `.do` scripts live in `scripts/`.
- **Generated IP:** Quartus-generated IP files, when used, are kept under `quartus/ipcores/`.
- **Source organization:** Active HDL sources live in `hdl/`, with constraints in `constraints/`.

## Documentation

- `doc/Log.md` tracks ongoing development notes.
- `doc/Style.md` contains coding style and naming format for the project.

## Hardware inventory

- "Intel Cyclone IV EP4CE10F17C8 development board" with on-board CH340 USB-UART bridge and W9825G6KH-6 SDRAM.
- "InvenSense INMP441 digital MEMS microphone modules" providing the I2S/PDM data streams captured by the FPGA.

**Retired**
- "Analog Devices AD7606 8-channel simultaneous sampling ADC module" (retired front end).
- "TXS0108E 8-channel bidirectional level shifter" (legacy level-shifting companion to the AD7606 path).
