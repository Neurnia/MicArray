# MicArray

MicArray is an FPGA-based microphone array platform built around Intel FPGAs and the Quartus Prime toolchain. The project explores multi-channel audio capture, beamforming, and supporting digital signal processing blocks.

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

## Toolchain

- **FPGA vendor tools:** Intel Quartus Prime (project files live in `quartus/`).
- **Simulation:** Populate `sim/` with testbenches compatible with your preferred simulator (ModelSim, Questa, etc.).
- **Source files:** HDL resides in `hdl/`, with associated constraints in `constraints/`.

## Documentation

- `doc/Log.md` tracks ongoing development notes.
- Additional developer-facing guidance, including Quartus workflow tips, is collected in `doc/Notes.md`.

Contributions and feedback are welcome; please align new HDL modules and documentation with the structure described above.
