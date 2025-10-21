# MicArray

MicArray is an FPGA-based microphone array platform built around Intel FPGAs and the Quartus Prime toolchain. The project explores multi-channel audio capture, beamforming, and supporting digital signal processing blocks.

## Project aim

Given a sound source with known characteristics and a cluster of microphones, the goal is to ingest the per-microphone signals on the FPGA, treat one microphone as the reference, and compute the relative positions of the remaining microphones. By measuring the time differences of arrival (TDOA) between the reference channel and every other channel, we can infer the geometry of the array and track any drift in microphone placement.

## Repository layout

```
MicArray/
├── build/        # Generated bitstreams, timing reports, and build logs
├── constraints/  # Board-level pin assignments and timing constraints
├── doc/          # Project documentation and progress logs
├── hdl/          # Synthesizable HDL sources for the array
├── quartus/      # Quartus project files (.qpf/.qsf) and custom IP metadata
├── scripts/      # Utility scripts used during development
└── sim/          # Testbenches and simulation assets
```

The Quartus project (`quartus/MicArray.qpf`) is configured to emit build products into `build/` so auto-generated data stays separate from the source tree.

## How the system works

1. **Signal acquisition** – Convert each microphone output to digital form (external ADCs or on-board codec) and ingest samples into the FPGA fabric with synchronized clocks.
2. **Reference alignment** – Designate one microphone channel as the reference. Apply coarse alignment (sample delay buffers) so all channels share a common frame.
3. **Time difference measurement** – Implement cross-correlation or generalized cross-correlation (GCC-PHAT) between each channel and the reference to extract precise TDOA values.
4. **Distance estimation** – Translate the measured delays into distance offsets using the known speed of sound and environmental compensation (temperature, humidity).
5. **Geometry solver** – Feed the set of pairwise distances into a least-squares solver or multilateration step to recover the relative microphone coordinates.
6. **Calibration loop** – Store the computed positions, compare them to expected placements, and surface deviations for alignment or monitoring.

Simulation testbenches in `sim/` will exercise the DSP chain with synthetic microphone data before hardware bring-up. Quartus projects under `quartus/` integrate the HDL blocks, signal interfaces, and constraint sets needed to target the Cyclone IV device.

## Toolchain

- **FPGA vendor tools:** Intel Quartus Prime (project files live in `quartus/`).
- **Simulation:** Populate `sim/` with testbenches compatible with your preferred simulator (ModelSim, Questa, etc.).
- **Source files:** HDL resides in `hdl/`, with associated constraints in `constraints/`.

## Documentation

- `doc/Log.md` tracks ongoing development notes.
- Additional developer-facing guidance, including Quartus workflow tips, is collected in `doc/Notes.md`.

Contributions and feedback are welcome; please align new HDL modules and documentation with the structure described above.
