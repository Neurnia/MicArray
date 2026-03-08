# Coding Style

Personal coding style for this project.  
The goal is to keep HDL code consistent, readable, and easy to extend.

---

## 1. Module and File Naming

- Module names use **PascalCase** (CamelCase starting with a capital letter):

  - Functional modules: `I2sRx`, `MicArrayCore`, `FifoAsync`
  - Top-level for the project: `MicArrayTop`
  - Testbenches: `I2sRxTb`, `MicArrayCoreTb`

- **File name = module name + `.v` or `.sv`**

  - `I2sRx.v`
  - `MicArrayTop.v`
  - `I2sRxTb.v`

Each file should normally contain one main module whose name matches the file.

---

## 2. Port Naming

- Ports use **snake_case + direction suffix**:

  - Inputs: `*_i`
  - Outputs: `*_o`
  - Inouts: `*_io`

- Examples:

  - `clk_i`, `clk_sys_i`
  - `rst_n_i`
  - `i2s_sck_i`, `i2s_ws_i`, `i2s_sd_i`
  - `sample_o`, `sample_valid_o`

- **Active-low signals** always end with `_n`:

  - `rst_n_i`, `cs_n_o`

---

## 3. Clock and Reset

- Clock signals start with `clk`:

  - `clk_i`, `clk_sys_i`

- Default reset is **active-low**, named `rst_n`:

  - Port: `rst_n_i`
  - Internal signal: `rst_n`

All active-low signals (not only reset) use the `_n` suffix.

---

## 4. Instance and Parameter Naming

- Module instances use the prefix `u_`:

  - `u_i2s_rx`, `u_fifo_left`, `u_mic_array_core`

- In testbenches, the DUT (device under test) instance is named `u_dut`:

  ```verilog
  I2sRx u_dut (
      .clk_i          (clk),
      .rst_n_i        (rst_n),
      .i2s_sck_i      (i2s_sck),
      .i2s_ws_i       (i2s_ws),
      .i2s_sd_i       (i2s_sd),
      .sample_o       (sample),
      .sample_valid_o (sample_valid)
  );
  ```

---

## 5. Testbench Conventions

- All testbenches live in the `sim/` directory.

- Testbench module names starts with `tb_`:

  - `tb_I2sRx`, `tb_MicArrayCore`

- Testbenches are allowed to use simulation-only constructs:

  - `initial`, `#10`, `$display`, `$monitor`, `$dumpvars`, etc.

These files are **never** used for synthesis; they are only for simulation.

---