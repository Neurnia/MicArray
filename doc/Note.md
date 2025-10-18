# Developer Notes

## Quartus workflow

- Project file: open `quartus/MicArray.qpf` in Quartus Prime.
- Set the compilation output directory to `../build` so generated folders (`db/`, `incremental_db/`, `output_files/`) stay out of the HDL sources.
- Prefer regenerating IP cores rather than checking in bulky auto-generated files; keep configuration `.ip`/`.qsys` files alongside the project.
- Add the usual Quartus build directories (`build/db/`, `build/output_files/`, `build/incremental_db/`) to `.gitignore` to avoid committing large binaries.

## Repository reminders

- Keep daily notes in `doc/Log.md`. Convert any lasting design decisions into dedicated docs as needed.
- Place synthesizable HDL in `hdl/`. Separate testbenches and simulation models under `sim/`.
- Store board-specific constraint files in `constraints/`.
- Use `scripts/` for helper utilities (e.g., bitstream packaging, coefficient generation).
- Point collaborators to the top-level `README.md` for a high-level overview.
