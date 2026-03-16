# MicArray

MicArray 是一个基于 Intel FPGA 和 Quartus Prime 工具链构建的 FPGA 麦克风阵列平台。该项目用于探索多通道音频采集、波束形成以及相关的数字信号处理模块。

## 项目目标

给定一个具有已知特性的声源和一组麦克风，本项目的目标是在 FPGA 上采集每个麦克风的信号，将其中一个麦克风作为参考，并计算其余麦克风相对于参考麦克风的位置。通过测量每个通道相对于参考通道的到达时间差（TDOA），我们可以推断麦克风阵列的几何结构，并跟踪麦克风位置的漂移。

## 仓库结构

```
MicArray/
├── constraints/  # 板级引脚分配和时序约束
├── doc/          # 项目文档和进度日志
├── hdl/          # 阵列的可综合 HDL 源文件
├── openspec/     # 由 Openspec 驱动的规格化开发计划
├── quartus/      # Quartus 工程文件（.qpf/.qsf）和自定义 IP 元数据
├── scripts/      # 开发过程中使用的辅助脚本
└── sim/          # 测试平台和仿真资源
```

## 工具链

- **FPGA 厂商工具：** Intel Quartus Prime Lite 20.1.x（工程文件位于 `quartus/`）。
- **仿真：** ModelSim/Questa 风格的测试平台位于 `sim/`，辅助 `.do` 脚本位于 `scripts/`。
- **生成的 IP：** Quartus 生成的 IP 文件在使用时保存在 `quartus/ipcores/` 下。
- **源码组织：** 活跃的 HDL 源文件位于 `hdl/`，约束文件位于 `constraints/`。

## 文档

- `doc/Log.md` 记录持续的开发笔记。
- `doc/Style.md` 包含本项目的代码风格和命名规范。

## 硬件清单

- “Intel Cyclone IV EP4CE10F17C8 development board”，带板载 CH340 USB-UART 桥接器和 W9825G6KH-6 SDRAM。
- “InvenSense INMP441 digital MEMS microphone modules”，向 FPGA 提供 I2S/PDM 数据流。

**已退役**
- “Analog Devices AD7606 8-channel simultaneous sampling ADC module”（已退役前端）。
- “TXS0108E 8-channel bidirectional level shifter”（AD7606 路径中遗留的电平转换配套模块）。
